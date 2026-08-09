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
