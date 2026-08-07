# Transforms for the CloudTrail pipeline.
#
# `config` uses the jsondecode(jsonencode(...)) idiom established in inputs.tf:
# it hands the provider the decoded-object shape it expects while letting the
# operations be written as readable HCL rather than one escaped JSON blob.
#
# Operation-level `description` fields are deliberately NOT set. They are not a
# platform feature (nothing surfaces them), and the provider does not read them
# back on refresh — so setting them produces a diff on every single plan,
# forever. A repo whose whole premise is "a clean plan means nothing drifted"
# cannot afford permanent plan noise. The reasoning lives in these comments
# instead, where a reviewer actually reads it.
#
# The ECS normalizer's jq lives in jq/cloudtrail-to-ecs.jq rather than inline.
# An 18 KB jq program embedded in an escaped JSON string is not reviewable, and
# reviewing transform changes in a pull request is the point of this repo.

# ---------------------------------------------------------------------------
# 1 of 3 — runs FIRST, on the raw CloudTrail record.
#
# Reduces record size without giving up anything an investigation needs.
# Sub-key drops have to happen HERE: the ECS transform serializes
# requestParameters / responseElements / additionalEventData to JSON strings,
# and you cannot del() into a string.
#
# Deliberately NOT dropped, despite being tempting:
#   responseElements.credentials.accessKeyId  AWS documents a role's subsequent
#     calls as carrying "role identity only (no user)", so this is the only key
#     that joins a sign-in event to everything the resulting session then did.
#     It is an identifier, not a secret.
#   requestParameters.incomingTransitiveTags  carries the k8s pod / namespace /
#     service-account that assumed the role.
#   sharedEventID                             correlates one event across
#     accounts in an org trail.
# ---------------------------------------------------------------------------
resource "monad_transform" "drop_low_value_fields" {
  name        = "Drop Low-Value Fields"
  description = "Reduces CloudTrail record size without sacrificing incident-response value. Drops the live session token (a secret), AWS-internal request/trace identifiers, and values duplicated elsewhere in the raw record. Runs FIRST, before 'CloudTrail to ECS v8.11.0' - sub-key drops must happen here because the ECS transform serializes requestParameters/responseElements/additionalEventData to JSON strings."

  config = jsondecode(jsonencode({
    operations = [
      # A live, usable STS session token. Must never reach a destination, and
      # must be removed before the ECS step, which would otherwise copy it into
      # both response_elements and event.original.
      { operation = "drop_key", arguments = { key = "responseElements.credentials.sessionToken" } },

      # AWS-internal request id; no investigative value once eventID is present.
      { operation = "drop_key", arguments = { key = "requestID" } },

      # CloudTrail's schema version for the record, not a property of the activity.
      { operation = "drop_key", arguments = { key = "eventVersion" } },

      # AWS-internal S3 trace id.
      { operation = "drop_key", arguments = { key = "additionalEventData.ExtendedRequestId" } },

      # Duplicate of awsRegion, which becomes cloud.region.
      { operation = "drop_key", arguments = { key = "additionalEventData.RequestDetails.awsServingRegion" } },

      # Another AWS-internal S3 trace id. jq rather than drop_key because the
      # Drop Key UI rejects dashes in key names. Type-guarded because a bare
      # del() aborts the whole transform if additionalEventData is ever not an
      # object.
      {
        operation = "jq"
        arguments = {
          key   = ""
          query = "if (.additionalEventData | type) == \"object\" then del(.additionalEventData[\"x-amz-id-2\"]) else . end"
        }
      },
    ]
  }))
}

# ---------------------------------------------------------------------------
# 2 of 3 — normalizes to ECS v8.11.0 so the data lands usably in Elasticsearch.
#
# Two things this transform does that are easy to undo by accident:
#   - requestParameters / responseElements / additionalEventData are emitted as
#     JSON *strings*, matching the `keyword` type Elastic's own AWS CloudTrail
#     integration uses. As raw objects they cause mapping explosion and type
#     conflicts that silently REJECT documents (a live org trail sends
#     {"maxResults":"100"} from apigateway and {"maxResults":100} from ec2).
#   - user_identity.session_issuer sits as a SIBLING of session_context, which
#     is where Elastic's schema puts it.
# ---------------------------------------------------------------------------
resource "monad_transform" "cloudtrail_to_ecs" {
  name        = "CloudTrail to ECS v8.11.0"
  description = "Normalizes CloudTrail into ECS v8.11.0 for Elasticsearch. requestParameters, responseElements and additionalEventData are JSON strings (Elastic's own type) to avoid mapping explosion and type conflicts that reject documents; their security content is extracted into typed fields. Resolves the actor across all sign-in forms: IAM user, SAML/OIDC, Identity Center roles and users. No event.original. Runs between the two drop transforms."

  config = jsondecode(jsonencode({
    operations = [
      {
        operation = "jq"
        arguments = {
          key   = ""
          query = file("${path.module}/jq/cloudtrail-to-ecs.jq")
        }
      },
    ]
  }))
}

# ---------------------------------------------------------------------------
# 3 of 3 — runs LAST, on the normalized record. Keys are ECS paths, not raw
# CloudTrail paths; against raw paths these would silently match nothing.
#
# Only exact duplicates are dropped. Things that merely correlate are kept:
#   user_identity.invoked_by       the CALLING service, where event.provider is
#                                  the service being called — the service vs.
#                                  human signal, not a duplicate.
#   session_issuer.principal_id    the immutable role id, which survives a
#                                  role rename.
#   session_issuer.type            Role vs IAMUser vs Root session origin.
# ---------------------------------------------------------------------------
resource "monad_transform" "drop_cloudtrail_duplicated_data" {
  name        = "Drop CloudTrail Duplicated Data (ECS)"
  description = "Drops ECS fields whose values are duplicated verbatim elsewhere in the same normalized record. Runs AFTER 'CloudTrail to ECS v8.11.0' - keys are ECS paths, not raw CloudTrail paths. Deliberately does NOT drop anything that is merely correlated (e.g. user_identity.invoked_by, session_issuer.principal_id) - see the per-operation notes."

  config = jsondecode(jsonencode({
    operations = [
      # Exact duplicate of cloud.account.id, which the ECS transform sources
      # from this very field.
      { operation = "drop_key", arguments = { key = "aws.cloudtrail.recipient_account_id" } },

      # Exact duplicate of user_identity.account_id — both are the account that
      # owns the role.
      { operation = "drop_key", arguments = { key = "aws.cloudtrail.user_identity.session_issuer.account_id" } },

      # Promoted to user.effective.name (or user.name). Elastic's CloudTrail
      # schema has no session_issuer.user_name field at all.
      { operation = "drop_key", arguments = { key = "aws.cloudtrail.user_identity.session_issuer.user_name" } },

      # Exact duplicate of ECS error.code.
      { operation = "drop_key", arguments = { key = "aws.cloudtrail.error_code" } },

      # Exact duplicate of ECS error.message, and the longest duplicated string
      # on any failed call.
      { operation = "drop_key", arguments = { key = "aws.cloudtrail.error_message" } },
    ]
  }))
}
