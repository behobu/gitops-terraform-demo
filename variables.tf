variable "monad_base_url" {
  type    = string
  default = "https://app.monad.com"
}

# An API key that can reach the target org. A missing Actions secret expands to
# an empty string rather than failing the workflow, so fail on the plan instead
# of with a confusing 401 from the provider.
variable "monad_api_token" {
  type      = string
  sensitive = true

  validation {
    condition     = length(var.monad_api_token) > 0
    error_message = "monad_api_token is empty. Set the MONAD_SYSLOG_API_TOKEN Actions secret to an API key that can reach the syslog-9001 org (see the README's Setup section)."
  }
}

# Not a secret: the org id is in the workflow env and terraform.tfvars.example.
variable "monad_organization_id" {
  type        = string
  description = "Org this demo manages. syslog-9001 (child of kenneth-testing)."
}

# The API key the intake's HTTP outputs present (x-api-key) when they post to
# the per-type pipelines' HTTP inputs. It is a real credential, so it is
# referenced by id rather than managed here: the value never touches this repo,
# the Actions secrets, or Terraform state. Create it once in the target org
# (Settings > Secrets) and pass its id when retargeting to a fresh org.
variable "http_input_api_key_secret_id" {
  type        = string
  default     = "7135f091-8fe7-4145-b98f-b105b1fda887"
  description = "Id of the 'syslog-demo-http-input-api-key' secret in the target org."
}
