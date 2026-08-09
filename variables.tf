variable "monad_base_url" {
  type    = string
  default = "https://app.monad.com"
}

variable "monad_api_token" {
  type      = string
  sensitive = true
}

variable "monad_organization_id" {
  type = string
}

# The ct_bucket / ct_role_arn / ct_region variables were removed along with the
# live `cloudtrail` input. The HTTP input needs no AWS identifiers, so nothing
# in this repo references a Monad-internal account any more.

# HMAC key material for the dedup fingerprint. A salt, not a credential — see
# secrets.tf. Supplied via TF_VAR_dedup_hmac_key from an Actions secret so it is
# never committed and never lands in Terraform state.
#
# The validation is load-bearing, not decoration. A missing Actions secret does
# not fail the workflow — `${{ secrets.X }}` expands to an empty string, which
# Terraform happily accepts as a valid value for a string variable. Without this
# check the apply would create an empty-keyed secret and the failure would only
# surface later, at runtime, as a mask that cannot hash. Fail on the PR instead.
variable "dedup_hmac_key" {
  type        = string
  sensitive   = true
  description = "HMAC key material (>= 16 bytes) keying the deterministic dedup mask."

  validation {
    condition     = length(var.dedup_hmac_key) >= 16
    error_message = "dedup_hmac_key must be at least 16 bytes; the deterministic mask requires it. This almost always means the MONAD_DEDUP_HMAC_KEY Actions secret is unset — see the Setup section of the README."
  }
}

# Cold-tier S3 destination. Sensitive-but-not-secret identifiers, supplied via
# TF_VAR_* from Actions secrets so the AWS account id and role name never live
# in this public repo.
variable "s3_bucket" {
  type        = string
  description = "S3 bucket receiving the cold tier."

  validation {
    condition     = length(var.s3_bucket) > 0
    error_message = "s3_bucket is empty. A missing Actions secret expands to an empty string rather than failing the workflow — set MONAD_S3_BUCKET."
  }
}

variable "s3_role_arn" {
  type        = string
  description = "Cross-account IAM role ARN Monad assumes to write the bucket."

  validation {
    condition     = startswith(var.s3_role_arn, "arn:aws:iam::")
    error_message = "s3_role_arn must be an IAM role ARN. A missing Actions secret expands to an empty string rather than failing the workflow — set MONAD_S3_ROLE_ARN."
  }
}

variable "s3_region" {
  type    = string
  default = "us-west-2"
}

# Ingest bucket for the archive pipeline's S3 pull source. Separate from the
# egress bucket so the outage lever (a Deny on egress) never affects the source
# the pipeline is reading from.
variable "s3_ingest_bucket" {
  type        = string
  description = "S3 bucket the archive pipeline reads NDJSON CloudTrail objects from."

  validation {
    condition     = length(var.s3_ingest_bucket) > 0
    error_message = "s3_ingest_bucket is empty. A missing Actions secret expands to an empty string rather than failing the workflow — set MONAD_S3_INGEST_BUCKET."
  }
}

# How far back the archive pipeline reads on a FRESH deployment. Must be in the
# past: an empty value seeds the cursor from now and silently ingests nothing.
variable "archive_backfill_start_time" {
  type        = string
  default     = "2026-01-01T00:00:00Z"
  description = "RFC3339 timestamp the archive input backfills from on first run. Ignored once the input has saved state."

  validation {
    condition     = can(formatdate("YYYY-MM-DD", var.archive_backfill_start_time))
    error_message = "archive_backfill_start_time must be an RFC3339 timestamp, e.g. 2026-01-01T00:00:00Z. An empty value would silently mean \"start from now\"."
  }
}
