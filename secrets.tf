# The pipeline-to-pipeline credential. The intake pipeline's three HTTP outputs
# send it as x-api-key to the per-type pipelines' HTTP inputs, which accept any
# org API key with pipeline:data:write.
#
# The value comes from the MONAD_SYSLOG_HTTP_INPUT_API_KEY Actions secret. It is
# write-only: sent to Monad, never stored in state. To rotate it, mint a new
# key in Monad, update the Actions secret, and run terraform-apply. The
# provider sees the changed fingerprint (value_hash) and re-sends the value.
resource "monad_secret" "http_input_api_key" {
  name        = "syslog-demo-http-input-api-key"
  description = "Org API key for syslog-9001 with pipeline:data:write (Contributor role or higher). Sent as the x-api-key header by the intake pipeline's three HTTP outputs (Intake → Firewall / Linux Auth / CEF Alerts) to the per-type pipelines' HTTP Inputs. Managed by Terraform (behobu/gitops-terraform-demo) from the MONAD_SYSLOG_HTTP_INPUT_API_KEY Actions secret."
  value       = var.http_input_api_key
}
