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
