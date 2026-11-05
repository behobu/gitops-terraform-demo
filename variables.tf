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

# Value of the pipeline-to-pipeline secret (secrets.tf): the API key the
# intake's HTTP outputs present as x-api-key when they post to the per-type
# pipelines' HTTP inputs. Supplied via TF_VAR_http_input_api_key from the
# MONAD_SYSLOG_HTTP_INPUT_API_KEY Actions secret; write-only, so it is never
# committed and never lands in Terraform state.
variable "http_input_api_key" {
  type        = string
  sensitive   = true
  description = "Org API key for syslog-9001 with pipeline:data:write, used between the demo's pipelines."

  validation {
    condition     = length(var.http_input_api_key) > 0
    error_message = "http_input_api_key is empty. Set the MONAD_SYSLOG_HTTP_INPUT_API_KEY Actions secret (see the README's Setup section)."
  }
}
