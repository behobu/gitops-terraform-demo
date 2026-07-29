# Remote state in S3. Partial config — the bucket/key/region are supplied at
# `terraform init` time via -backend-config flags (see the workflows), so the
# bucket name stays out of this public repo.
#
# State must NOT be committed to git; S3 (private, encrypted) holds it. Note the
# reason is narrower than it used to be but has not gone away: connector
# `config.secrets` is write-only and never lands in state (see README), yet
# sensitive *settings* still do — the resolved `ct_bucket` and `ct_role_arn`
# among them.
terraform {
  backend "s3" {
    encrypt = true
  }
}
