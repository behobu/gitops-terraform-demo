# Remote state in S3. Partial config — the bucket/key/region are supplied at
# `terraform init` time via -backend-config flags (see the workflows), so the
# bucket name stays out of this public repo. State can contain resolved secret
# values, so it must NOT be committed to git; S3 (private, encrypted) holds it.
terraform {
  backend "s3" {
    encrypt = true
  }
}
