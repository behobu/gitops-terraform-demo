# The syslog listener. Senders connect over TLS to
# <monad_pipeline.intake.id>.data.monad.com:6514; SNI selects the pipeline.
resource "monad_input" "syslog_tls" {
  name        = "Syslog TLS :6514"
  description = "RFC 3164/5424 syslog over TLS on <intake-pipeline-id>.data.monad.com:6514 (SNI selects the pipeline)."
  type        = "monad-syslog"
}

# One HTTP input per data type. The intake pipeline fans out to these through
# the matching HTTP outputs in outputs.tf.
resource "monad_input" "http_in_firewall" {
  name        = "HTTP In – Firewall"
  description = "Receives data_type=firewall records from the syslog intake pipeline."
  type        = "monad-http"
}

resource "monad_input" "http_in_linux_auth" {
  name        = "HTTP In – Linux Auth"
  description = "Receives data_type=linux_auth records from the syslog intake pipeline."
  type        = "monad-http"
}

resource "monad_input" "http_in_cef" {
  name        = "HTTP In – CEF Alerts"
  description = "Receives data_type=cef_alert records from the syslog intake pipeline."
  type        = "monad-http"
}
