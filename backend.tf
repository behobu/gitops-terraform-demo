# Remote state in S3. Partial config — the bucket/key/region are supplied at
# `terraform init` time via -backend-config flags (see the workflows), so the
# bucket name stays out of this public repo.
#
# State must NOT be committed to git; S3 (private, encrypted) holds it. Connector
# `config.secrets` is write-only and never lands in state (see README), and no
# resource here currently has a sensitive *setting* either — but settings DO land
# in state, so the moment one is added (an endpoint, an account id, a role ARN)
# this is again load-bearing.
terraform {
  backend "s3" {
    encrypt = true
  }
}
