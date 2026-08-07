# =================================================================
# AWS CloudTrail  ->  ECS v8.11.0  (COMPREHENSIVE, no event.original)
#
# Input: ONE CloudTrail event record per invocation, as emitted by
#   the Monad `cloudtrail` input connector. (For the S3/SQS
#   connector `aws-sqs-s3-cloudtrail` this depends on its Chunking
#   Mode: `per_record` already emits one bare event per record and
#   needs nothing extra, while `by_size` — the default — emits the
#   CloudTrail envelope with `Records` chunked, so explode
#   `.Records[]` in an upstream transform first.)
#
# Superset of the Core transform. In addition to the core ECS
# fields (event, cloud, user, source, user_agent, related) it maps
# every CloudTrail field with an ECS or aws.cloudtrail.* home:
#   - error.code / error.message          <- errorCode / errorMessage
#   - tls.version / tls.cipher / tls.client.server_name
#   - aws.cloudtrail.* (user_identity, session_context, resources,
#     request/response parameters, read_only, management_event, ...)
# Field names under aws.cloudtrail.* follow the Elastic AWS
# integration's snake_case convention.
#
# NOTE: event.original is deliberately NOT emitted. It re-embeds the
#   entire record as a string, roughly doubling the payload and
#   re-materializing anything dropped upstream. The typed extractions
#   (issued_credentials, federation, sign_in) plus the JSON-string
#   blobs already retain everything an investigation needs.
#
# ---- ELASTICSEARCH MAPPING NOTES --------------------------------
# requestParameters, responseElements and additionalEventData are
# emitted as JSON *strings*, not objects. This is deliberate and
# matches the type Elastic's own AWS CloudTrail integration uses
# (`aws.cloudtrail.request_parameters` is a `keyword`). Emitting
# them as objects breaks Elasticsearch two ways:
#   1. Mapping explosion - every parameter name of every AWS API
#      becomes a distinct field, blowing the index field limit.
#   2. Type conflicts that REJECT documents - the same key is not
#      consistently typed across APIs. Real example from a live org
#      trail: apigateway sends {"maxResults": "100"} (string) while
#      ec2 sends {"maxResults": 100} (number). Whichever indexes
#      first wins the mapping and the other is dropped.
# The security-relevant contents are ALSO extracted into typed,
# queryable fields (sign_in, federation, issued_credentials) so no
# investigation has to parse the string. If you want the blobs
# queryable too, map `aws.cloudtrail.flattened.*` as `flattened` in
# your index template and change json_str() to pass the object.
#
# Sub-keys cannot be pruned from these fields downstream once they
# are strings, so any field-level trimming (e.g. dropping a session
# token) must happen in an UPSTREAM transform on the raw record.
# =================================================================

def is_ip($s):
  ($s | type) == "string"
  and ($s | test("^(\\d{1,3}\\.){3}\\d{1,3}$") or (test(":") and test("^[0-9A-Fa-f:.]+$")));

# CloudTrail replaces a user name with this sentinel when a console
# sign-in fails because of bad username input, and IAM Identity
# Center does the same for additionalEventData.UserName. It is a
# redaction marker, not an identity - never surface it as user.name.
def real_name($s):
  if ($s | type) == "string" and $s != "HIDDEN_DUE_TO_SECURITY_REASONS"
  then $s else null end;

# requestParameters / responseElements / additionalEventData are not
# always JSON objects (a bare string aborts the whole transform when
# indexed), so every read of them goes through this guard.
def g($o; $k): if ($o | type) == "object" then $o[$k] else null end;

def sid($o): real_name(g($o; "sourceIdentity"));

# See the ELASTICSEARCH MAPPING NOTES above. null and {} collapse to
# null so prune drops them rather than storing the string "null".
def json_str($v):
  if $v == null then null
  elif ($v | type) == "object" and ($v | length) == 0 then null
  else ($v | tostring) end;

# The session-name half of an assumed-role principalId
# ("AROAEXAMPLE:session-name" -> "session-name").
def session_name($p):
  if ($p | type) == "string" and ($p | test(":"))
  then ($p | sub("^[^:]*:"; "")) else null end;

def prune:
  walk(
    if type == "object" then
      with_entries(select(.value != null and .value != {} and .value != []))
    elif type == "array" then
      map(select(. != null))
    else . end
  );

. as $r
| ( $r.userIdentity // {} ) as $ui
| ( $ui.sessionContext // {} ) as $sc
| ( $r.requestParameters ) as $rp
| ( $r.responseElements ) as $re
| ( $r.additionalEventData ) as $aed

# ---- outcome ----------------------------------------------------
# additionalEventData.success covers the signin.amazonaws.com OAuth2
# events, which report failure there rather than via errorCode.
| ( if ($r.errorCode // null) != null then "failure"
    elif ($r.eventName // "") == "ConsoleLogin"
      then ( if (g($re; "ConsoleLogin") // "") == "Success"
             then "success" else "failure" end )
    elif (g($aed; "success") // "") == "false" then "failure"
    else "success" end ) as $outcome

# ---- event.category --------------------------------------------
# Every AWS sign-in form must land in `authentication`, because that
# is what SIEM detection content keys on:
#   - IAM user / root console password sign-in .. ConsoleLogin
#   - SAML or OIDC federated role assumption ... AssumeRoleWith*
#   - plain / chained role assumption .......... AssumeRole, AssumeRoot
#   - IAM Identity Center sign-in and tokens ... sso*/signin* events
| ( if (($r.eventName // "") | test("^(ConsoleLogin|SwitchRole|ExitRole|RenewRole|CheckMfa|AssumeRole|AssumeRoot|GetSessionToken|GetFederationToken|AssumeRoleWithSAML|AssumeRoleWithWebIdentity)$"))
      then ["authentication"]
    # IAM Identity Center sign-in and token/credential issuance.
    # This MUST be tested before the eventSource "iam" rule below,
    # which would otherwise swallow every sso./signin. event.
    elif (($r.eventSource // "") | test("^(sso|sso-oidc|signin|identitystore)\\."))
         and (($r.eventName // "") | test("^(Authenticate|UserAuthentication|CredentialChallenge|CredentialVerification|Federate|CreateToken|CreateTokenWithIAM|StartDeviceAuthorization|Authorize|AuthorizeOAuth2Access|CreateOAuth2Token|GetRoleCredentials|SSOSignIn)$"))
      then ["authentication"]
    elif ($r.eventSource // "") | test("^(iam|sso|signin)\\.")
      then ["iam"]
    else ["configuration"] end ) as $category

# ---- event.type (ECS allowed values) ---------------------------
# An authentication event is a session beginning, so it takes
# `start` rather than `access`. ECS pairs category=authentication
# with type=start/end/info, and detection content expects `start`.
# ExitRole ends a session instead.
| ( if ($r.eventName // "") == "ExitRole" then ["end"]
    elif $category == ["authentication"] then ["start"]
    elif ($r.readOnly // false) == true then ["access"]
    elif (($r.eventName // "") | test("^(Create|Add|Enable|Register|Put|Allocate|Import|Run|Provision|Attach|Associate)"))
      then ["creation"]
    elif (($r.eventName // "") | test("^(Delete|Remove|Deregister|Disable|Detach|Disassociate|Terminate|Revoke)"))
      then ["deletion"]
    elif (($r.eventName // "") | test("^(Update|Modify|Set|Change|Replace)"))
      then ["change"]
    else ["info"] end ) as $type

# ---- IDENTITY RESOLUTION ---------------------------------------
# CloudTrail puts the acting identity in a different place for each
# sign-in form, and for a plain assumed-role session it supplies no
# human at all. Resolved most-authoritative first:
#
#  1. sourceIdentity ....... the originating human, when STS is
#       configured to require it. Survives role chaining.
#  2. Identity Center role assumption (what a mature setup does:
#       IdP -> Identity Center -> permission set). userIdentity.type
#       is "AssumedRole" and onBehalfOf sits ALONGSIDE principalId,
#       whose session-name half is the Identity Center username.
#  3. additionalEventData.UserName .. Identity Center sign-in events
#       (CredentialChallenge / UserAuthentication). AWS documents
#       this as the only username source for Identity Center.
#  4. userIdentity.userName ... IAMUser (console password sign-in),
#       SAMLUser (the saml:sub), WebIdentityUser (the OIDC user id),
#       Root (the account alias).
#  5. sessionIssuer.userName .. last resort: the ROLE name, not a
#       person. Only used when nothing above identifies a human.
| ( g($ui.onBehalfOf; "userId") ) as $idc_user_id
| ( if $idc_user_id != null then session_name($ui.principalId)
    else null end ) as $idc_name
| ( sid($sc) // sid($rp) // sid($re) ) as $source_identity
| ( $source_identity
    // $idc_name
    // real_name(g($aed; "UserName"))
    // real_name($ui.userName) ) as $actor
# The role whose privileges are in effect. Null for non-session
# callers (IAM user, SAML/OIDC assume calls, Identity Center users).
| ( real_name($sc.sessionIssuer.userName) ) as $role_name

| {
    ecs: { version: "8.11.0" },

    "@timestamp": $r.eventTime,

    event: {
      kind: "event",
      module: "aws",
      dataset: "aws.cloudtrail",
      provider: $r.eventSource,
      action: $r.eventName,
      id: $r.eventID,
      category: $category,
      type: $type,
      outcome: $outcome
    },

    cloud: {
      provider: "aws",
      region: $r.awsRegion,
      account: { id: ($r.recipientAccountId // $ui.accountId) }
    },

    # ECS models user.* as the identity that INITIATED the action and
    # user.effective.* as the identity whose privileges were used -
    # the `sudo` model. Where CloudTrail gives us both a human and
    # the role they acted through, that maps exactly.
    #
    # NOTE user.name is intentionally bimodal: the human wherever one
    # is identifiable (see IDENTITY RESOLUTION above), otherwise the
    # role name, which is the only identity CloudTrail supplies for a
    # plain assumed-role session. user.effective.* is populated ONLY
    # when it differs from user.*, so it never merely duplicates it.
    user: (
      if $actor != null and $role_name != null then {
        # Identity Center supplies a stable, immutable user id; other
        # forms carry no id for the human, so user.id is omitted
        # rather than filled with the role session principal.
        id: $idc_user_id,
        name: $actor,
        effective: {
          id: $ui.principalId,
          name: $role_name
        }
      } else {
        id: ($idc_user_id // $ui.principalId),
        name: ($actor // $role_name)
      } end
    ),

    source: {
      address: $r.sourceIPAddress,
      ip: ( if is_ip($r.sourceIPAddress) then $r.sourceIPAddress else null end )
    },

    user_agent: { original: $r.userAgent },

    # error.* — only populated on failed calls.
    error: {
      code: $r.errorCode,
      message: $r.errorMessage
    },

    # tls.* — from CloudTrail tlsDetails when present.
    tls: {
      version: $r.tlsDetails.tlsVersion,
      cipher: $r.tlsDetails.cipherSuite,
      client: { server_name: $r.tlsDetails.clientProvidedHostHeader }
    },

    related: {
      ip: ( if is_ip($r.sourceIPAddress) then [$r.sourceIPAddress] else [] end ),
      # Every identifier for the actor seen anywhere on the event, so
      # a single related.user search finds the activity whichever
      # sign-in form produced it.
      user: ( [ $actor,
                $role_name,
                $source_identity,
                $idc_name,
                real_name($ui.userName),
                real_name(g($aed; "UserName")),
                real_name(g($re; "subject")) ]
              | map(select(. != null)) | unique )
    },

    # ---- Vendor namespace: full CloudTrail fidelity ------------
    aws: {
      cloudtrail: {
        event_version: $r.eventVersion,
        event_type: $r.eventType,
        event_category: $r.eventCategory,
        api_version: $r.apiVersion,
        management_event: $r.managementEvent,
        read_only: $r.readOnly,
        request_id: $r.requestID,
        recipient_account_id: $r.recipientAccountId,
        shared_event_id: $r.sharedEventID,
        vpc_endpoint_id: $r.vpcEndpointId,
        error_code: $r.errorCode,
        error_message: $r.errorMessage,

        # JSON strings, not objects — see ELASTICSEARCH MAPPING
        # NOTES at the top of this transform.
        request_parameters: json_str($rp),
        response_elements: json_str($re),
        additional_eventdata: json_str($aed),
        service_event_details: json_str($r.serviceEventDetails),

        # ---- Credentials issued by an AssumeRole* / GetSessionToken
        # THE pivot key for incident response. AWS documents that a
        # role's subsequent API calls carry "role identity only (no
        # user)", so access_key_id is what joins this sign-in event
        # to everything the resulting session went on to do:
        #   aws.cloudtrail.issued_credentials.access_key_id
        #     -> aws.cloudtrail.user_identity.access_key_id
        # An access key id is an identifier, not a secret (the secret
        # is the session token, which must be dropped upstream).
        issued_credentials: {
          access_key_id: g(g($re; "credentials"); "accessKeyId"),
          expiration: g(g($re; "credentials"); "expiration"),
          assumed_role_arn: g(g($re; "assumedRoleUser"); "arn"),
          assumed_role_id: g(g($re; "assumedRoleUser"); "assumedRoleId")
        },

        # ---- Federated sign-in detail (SAML and OIDC)
        # Identifies WHICH identity provider asserted the login -
        # the question that matters first when a federated account
        # is suspected of compromise.
        federation: {
          # SAMLUser: the saml:namequalifier. WebIdentityUser: the
          # OIDC provider ARN.
          identity_provider: $ui.identityProvider,
          # AssumeRoleWithSAML responseElements: the IdP issuer URL.
          issuer: g($re; "issuer"),
          subject: g($re; "subject"),
          subject_type: g($re; "subjectType"),
          audience: g($re; "audience"),
          name_qualifier: g($re; "nameQualifier"),
          saml_assertion_id: g($rp; "sAMLAssertionID"),
          # The IAM saml-provider / oidc-provider being trusted.
          principal_arn: g($rp; "principalArn"),
          # AssumeRoleWithWebIdentity: the OIDC subject.
          web_identity_subject: g($re; "subjectFromWebIdentityToken"),
          web_id_federated_provider: $sc.webIdFederationData.federatedProvider
        },

        # ---- Sign-in detail across all forms
        # Extracted from additionalEventData so these stay queryable
        # even though the blob itself is a string.
        sign_in: {
          # Console password sign-in (IAM user / root).
          mfa_used: g($aed; "MFAUsed"),
          mobile_version: g($aed; "MobileVersion"),
          login_to: g($aed; "LoginTo"),
          # IAM Identity Center sign-in sequence.
          auth_workflow_id: g($aed; "AuthWorkflowID"),
          credential_type: g($aed; "CredentialType"),
          user_name: g($aed; "UserName"),
          device_enrollment_required: g($aed; "DeviceEnrollmentRequired"),
          success: g($aed; "success")
        },

        user_identity: {
          type: $ui.type,
          principal_id: $ui.principalId,
          arn: $ui.arn,
          account_id: $ui.accountId,
          access_key_id: $ui.accessKeyId,
          user_name: $ui.userName,
          # The AWS service that made the call. NOT a duplicate of
          # event.provider (the service being called) - this is the
          # service/human distinction.
          invoked_by: $ui.invokedBy,
          # SAMLUser / WebIdentityUser identity provider.
          identity_provider: $ui.identityProvider,

          # Set when the caller uses a bearer token, such as an IAM
          # Identity Center authorized access token. Correlates the
          # AWS access portal actions taken in one signed-in session.
          credential_id: $ui.credentialId,

          # Present for IAM Identity Center callers - both
          # userIdentity.type "IdentityCenterUser" and, for Identity
          # Center role assumption, "AssumedRole" alongside
          # principalId. userId is the immutable Identity Store id
          # AWS recommends for identifying the person.
          on_behalf_of: {
            user_id: $idc_user_id,
            identity_store_arn: g($ui.onBehalfOf; "identityStoreArn")
          },

          # Which resource was issued these credentials (e.g. the
          # EC2 instance or Lambda function) - ties a session to the
          # compute that holds it.
          in_scope_of: {
            source_arn: g($ui.inScopeOf; "sourceArn"),
            source_account: g($ui.inScopeOf; "sourceAccount"),
            issuer_type: g($ui.inScopeOf; "issuerType"),
            credentials_issued_to: g($ui.inScopeOf; "credentialsIssuedTo")
          },

          # A product provider acting under delegated access.
          invoked_by_delegate_account_id: g($ui.invokedByDelegate; "accountId"),

          session_context: {
            mfa_authenticated: $sc.attributes.mfaAuthenticated,
            creation_date: $sc.attributes.creationDate,
            source_identity: $sc.sourceIdentity,
            # IMDSv1 ("1.0") vs IMDSv2 ("2.0") credential delivery.
            ec2_role_delivery: $sc.ec2RoleDelivery,
            # True for a management-account AssumeRoot session.
            assumed_root: $sc.assumedRoot,
            # Identifies the sign-in session more precisely than the
            # principal ARN; use it to audit or revoke by session.
            sign_in_session_arn: $sc.signInSessionArn
          },

          # Sibling of session_context, matching the field layout of
          # Elastic's AWS CloudTrail integration
          # (aws.cloudtrail.user_identity.session_issuer.*).
          session_issuer: {
            type: $sc.sessionIssuer.type,
            principal_id: $sc.sessionIssuer.principalId,
            arn: $sc.sessionIssuer.arn,
            account_id: $sc.sessionIssuer.accountId,
            user_name: $sc.sessionIssuer.userName
          }
        },

        resources: ( ($r.resources // [])
          | map({ arn: .ARN, account_id: .accountId, type: .type }) )
      }
    }
  }
| prune

