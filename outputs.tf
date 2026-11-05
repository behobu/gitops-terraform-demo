# ---------------------------------------------------------------------------
# Intake fan-out: one HTTP output per data type, posting to the per-type
# pipeline's HTTP input. The endpoint is that pipeline's ingest host, so these
# outputs depend on the per-type pipelines (never the reverse: no cycle).
# ---------------------------------------------------------------------------
locals {
  http_fanout_settings = {
    headers = [{
      header_key   = "Content-Type"
      header_value = "application/json"
    }]
    max_batch_record_count = 500
    method                 = "POST"
    payload_structure      = "array"
    rate_limit             = 20
  }

  # Write-only: sent to the API, never stored in state.
  http_fanout_secrets = {
    auth_headers = {
      "x-api-key" = { id = var.http_input_api_key_secret_id }
    }
  }
}

resource "monad_output" "http_out_firewall" {
  name        = "HTTP Out – Firewall pipeline"
  description = "Forwards data_type=firewall records from the syslog intake to the Firewall pipeline's HTTP input."
  type        = "http"
  config {
    settings = merge(local.http_fanout_settings, {
      endpoint = "https://${monad_pipeline.firewall.id}.data.monad.com"
    })
    secrets = local.http_fanout_secrets
  }
}

resource "monad_output" "http_out_linux_auth" {
  name        = "HTTP Out – Linux Auth pipeline"
  description = "Forwards data_type=linux_auth records from the syslog intake to the Linux Auth pipeline's HTTP input."
  type        = "http"
  config {
    settings = merge(local.http_fanout_settings, {
      endpoint = "https://${monad_pipeline.linux_auth.id}.data.monad.com"
    })
    secrets = local.http_fanout_secrets
  }
}

resource "monad_output" "http_out_cef" {
  name        = "HTTP Out – CEF Alerts pipeline"
  description = "Forwards data_type=cef_alert records from the syslog intake to the CEF IDS Alerts pipeline's HTTP input."
  type        = "http"
  config {
    settings = merge(local.http_fanout_settings, {
      endpoint = "https://${monad_pipeline.cef.id}.data.monad.com"
    })
    secrets = local.http_fanout_secrets
  }
}

# ---------------------------------------------------------------------------
# Destinations. All dev-null stand-ins for the real systems named below, so the
# demo runs with no customer credentials. Swap the type + config to go live.
# ---------------------------------------------------------------------------
resource "monad_output" "splunk_netfw" {
  name        = "Splunk – Network Traffic (index=netfw)"
  description = "dev-null stand-in for the Splunk HEC hot-tier destination for firewall logs (index=netfw, sourcetype pan:traffic / pan:threat)."
  type        = "dev-null"
}

resource "monad_output" "splunk_os_auth" {
  name        = "Splunk – Authentication (index=os_auth)"
  description = "dev-null stand-in for the Splunk HEC hot-tier destination for Linux auth logs (index=os_auth, sourcetype linux_secure)."
  type        = "dev-null"
}

resource "monad_output" "splunk_ids" {
  name        = "Splunk – Intrusion Detection (index=ids)"
  description = "dev-null stand-in for the Splunk HEC hot-tier destination for CEF IDS alerts (index=ids, sourcetype suricata:cef)."
  type        = "dev-null"
}

resource "monad_output" "warm_databricks" {
  name        = "Warm – Databricks Security Lake"
  description = "dev-null stand-in for the warm-tier Databricks security lake shared by all syslog data types."
  type        = "dev-null"
}

resource "monad_output" "cold_s3_archive" {
  name        = "Cold – S3 Archive (Glacier, 365d)"
  description = "dev-null stand-in for the cold-tier S3 archive (Glacier, 365-day retention) shared by all data types and unrecognized records; a real s3 output can use role_arn with no secret."
  type        = "dev-null"
}
