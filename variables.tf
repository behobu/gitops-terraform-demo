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

# --- CloudTrail input: sensitive-but-not-secret identifiers, supplied via
# TF_VAR_* from GitHub Actions secrets so the real AWS account id / role name
# never live in this public repo (mirrors the env: pass-through from the JSON
# demo). ---
variable "ct_bucket" {
  type        = string
  description = "S3 bucket holding the org CloudTrail logs."
}

variable "ct_role_arn" {
  type        = string
  description = "Cross-account IAM role ARN Monad assumes to read the bucket."
}

variable "ct_region" {
  type    = string
  default = "us-west-2"
}
