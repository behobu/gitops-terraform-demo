# Transforms for the CloudTrail pipeline.
#
# `config` uses the jsondecode(jsonencode(...)) idiom established in inputs.tf:
# it hands the provider the decoded-object shape it expects while letting the
# operations be written as readable HCL rather than one escaped JSON blob.
#
# The ECS normalizer's jq lives in jq/cloudtrail-to-ecs.jq rather than inline.
# That keeps it reviewable in a diff — which matters here, because reviewing a
# transform change in a pull request is the point of this repo.

# ---------------------------------------------------------------------------
# 1 of 3 — runs FIRST, on the raw CloudTrail record.
#
# Sub-key drops have to happen here: the ECS transform serializes
# requestParameters / responseElements / additionalEventData to JSON strings,
# and you cannot del() into a string.
# ---------------------------------------------------------------------------
resource "monad_transform" "drop_low_value_fields" {
  name        = "Drop Low-Value Fields"
  description = "Reduces CloudTrail record size without sacrificing incident-response value. Drops the live session token (a secret), AWS-internal request/trace identifiers, and values duplicated elsewhere in the raw record. Runs FIRST, before 'CloudTrail to ECS v8.11.0' - sub-key drops must happen here because the ECS transform serializes requestParameters/responseElements/additionalEventData to JSON strings."

  config = jsondecode(jsonencode({
    operations = [
      {
        operation   = "drop_key"
        description = "LIVE CREDENTIAL - a usable session token. Must never reach a destination or event.original."
        arguments   = { key = "responseElements.credentials.sessionToken" }
      },
      {
        operation   = "drop_key"
        description = "AWS-internal request id; no investigative value once eventID is present"
        arguments   = { key = "requestID" }
      },
      {
        operation   = "drop_key"
        description = "CloudTrail schema version of the record, not a property of the activity"
        arguments   = { key = "eventVersion" }
      },
      {
        operation   = "drop_key"
        description = "AWS-internal S3 trace id"
        arguments   = { key = "additionalEventData.ExtendedRequestId" }
      },
      {
        operation   = "drop_key"
        description = "duplicate of awsRegion / cloud.region"
        arguments   = { key = "additionalEventData.RequestDetails.awsServingRegion" }
      },
      {
        operation   = "jq"
        description = "AWS-internal S3 trace id. Needs jq because drop_key rejects dashes in key names; type-guarded because del() aborts the transform if additionalEventData is ever not an object."
        arguments = {
          key   = ""
          query = "if (.additionalEventData | type) == \"object\" then del(.additionalEventData[\"x-amz-id-2\"]) else . end"
        }
      },
    ]
  }))
}

# ---------------------------------------------------------------------------
# 2 of 3 — normalizes to ECS v8.11.0 for Elasticsearch.
# ---------------------------------------------------------------------------
resource "monad_transform" "cloudtrail_to_ecs" {
  name        = "CloudTrail to ECS v8.11.0"
  description = "Normalizes CloudTrail into ECS v8.11.0 for Elasticsearch. requestParameters, responseElements and additionalEventData are JSON strings (Elastic's own type) to avoid mapping explosion and type conflicts that reject documents; their security content is extracted into typed fields. Resolves the actor across all sign-in forms: IAM user, SAML/OIDC, Identity Center roles and users. No event.original. Runs between the two drop transforms."

  config = jsondecode(jsonencode({
    operations = [
      {
        operation   = "jq"
        description = "CloudTrail -> ECS v8.11.0"
        arguments = {
          key   = ""
          query = file("${path.module}/jq/cloudtrail-to-ecs.jq")
        }
      },
    ]
  }))
}

# ---------------------------------------------------------------------------
# 3 of 3 — runs LAST, on the normalized record. Keys are ECS paths.
# ---------------------------------------------------------------------------
resource "monad_transform" "drop_cloudtrail_duplicated_data" {
  name        = "Drop CloudTrail Duplicated Data (ECS)"
  description = "Drops ECS fields whose values are duplicated verbatim elsewhere in the same normalized record. Runs AFTER 'CloudTrail to ECS v8.11.0' - keys are ECS paths, not raw CloudTrail paths. Deliberately does NOT drop anything that is merely correlated (e.g. user_identity.invoked_by, session_issuer.principal_id) - see the per-operation notes."

  config = jsondecode(jsonencode({
    operations = [
      {
        operation   = "drop_key"
        description = "exact duplicate of cloud.account.id, which the ECS transform sources from it"
        arguments   = { key = "aws.cloudtrail.recipient_account_id" }
      },
      {
        operation   = "drop_key"
        description = "exact duplicate of aws.cloudtrail.user_identity.account_id (both are the role-owning account)"
        arguments   = { key = "aws.cloudtrail.user_identity.session_issuer.account_id" }
      },
      {
        operation   = "drop_key"
        description = "promoted to user.effective.name (or user.name); Elastic's CloudTrail schema has no session_issuer.user_name field"
        arguments   = { key = "aws.cloudtrail.user_identity.session_issuer.user_name" }
      },
      {
        operation   = "drop_key"
        description = "exact duplicate of ECS error.code"
        arguments   = { key = "aws.cloudtrail.error_code" }
      },
      {
        operation   = "drop_key"
        description = "exact duplicate of ECS error.message, and the longest duplicated string on a failed call"
        arguments   = { key = "aws.cloudtrail.error_message" }
      },
    ]
  }))
}
