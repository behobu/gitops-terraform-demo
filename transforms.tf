# Every jq query lives in jq/<name>.jq so it can be read, diffed and tested
# on its own. chomp() strips the file's trailing newline so the query sent to
# the API is byte-identical to the file body.

# --- Intake ---------------------------------------------------------------
resource "monad_transform" "intake_parse_classify" {
  name        = "Syslog Intake – Parse & Classify"
  description = "Normalizes Syslog input fields into syslog{}, message, rebuilt _raw and _meta, and classifies data_type (firewall, cef_alert, linux_auth, unknown)."
  config = {
    operations = [{
      operation   = "jq"
      description = ""
      arguments   = { query = chomp(file("${path.module}/jq/intake-parse-classify.jq")) }
    }]
  }
}

resource "monad_transform" "intake_hygiene" {
  name        = "Syslog Intake – Hygiene"
  description = "Drops '-- MARK --' heartbeats and empty messages, then removes exact _raw duplicates within 1 minute. Nothing else is dropped."
  config = {
    operations = [{
      operation   = "jq"
      description = ""
      arguments   = { query = chomp(file("${path.module}/jq/intake-hygiene.jq")) }
      }, {
      operation   = "deduplicate"
      description = ""
      arguments = {
        fields = ["_raw"]
        window = "1m"
      }
    }]
  }
}

# --- Firewall (PAN-OS) ----------------------------------------------------
resource "monad_transform" "firewall_parse" {
  name        = "Firewall – Parse PAN-OS to CIM + Redact"
  description = "Splits PAN-OS CSV TRAFFIC/THREAT logs into CIM fields, sets index=netfw and sourcetype, then redacts credentials in every string."
  config = {
    operations = [{
      operation   = "jq"
      description = ""
      arguments   = { query = chomp(file("${path.module}/jq/firewall-parse.jq")) }
    }]
  }
}

resource "monad_transform" "firewall_risk_tier" {
  name        = "Firewall – Context, Risk & Tier"
  description = "Adds network zones, direction, asset criticality, user category, geo, static threat intel, risk factors/score, MITRE techniques and hot/warm/cold tier for firewall logs."
  config = {
    operations = [{
      operation   = "jq"
      description = ""
      arguments   = { query = chomp(file("${path.module}/jq/firewall-risk-tier.jq")) }
    }]
  }
}

# --- Linux auth -----------------------------------------------------------
resource "monad_transform" "linux_auth_parse" {
  name        = "Linux Auth – Parse to CIM + Redact"
  description = "Parses sshd/sudo/session messages into CIM authentication, session and privilege_escalation fields, sets index=os_auth / linux_secure, then redacts credentials in every string."
  config = {
    operations = [{
      operation   = "jq"
      description = ""
      arguments   = { query = chomp(file("${path.module}/jq/linux-auth-parse.jq")) }
    }]
  }
}

resource "monad_transform" "linux_auth_risk_tier" {
  name        = "Linux Auth – Context, Risk & Tier"
  description = "Adds host/network zones, direction, asset criticality, user category, geo, static threat intel, risk factors/score, MITRE techniques and hot/warm/cold tier for Linux auth events."
  config = {
    operations = [{
      operation   = "jq"
      description = ""
      arguments   = { query = chomp(file("${path.module}/jq/linux-auth-risk-tier.jq")) }
    }]
  }
}

# --- CEF IDS alerts -------------------------------------------------------
resource "monad_transform" "cef_parse" {
  name        = "CEF – Parse to CIM + Redact"
  description = "Parses CEF IDS alerts with convert-cef, maps them to CIM fields with index=ids / suricata:cef and severity labels, then redacts credentials in every string."
  config = {
    operations = [{
      operation   = "convert-cef"
      description = ""
      arguments = {
        dialect         = "cef"
        empty_to_null   = true
        header_fields   = ["cef_version", "device_vendor", "device_product", "device_version", "signature_id", "signature", "cef_severity"]
        key             = "message"
        numeric_columns = ["cef_severity", "sourcePort", "destinationPort"]
        output_mode     = "merge"
        preset          = "cef_full_names"
        resolve_labels  = true
        warnings_key    = "_parse_warnings"
      }
      }, {
      operation   = "jq"
      description = ""
      arguments   = { query = chomp(file("${path.module}/jq/cef-parse.jq")) }
    }]
  }
}

resource "monad_transform" "cef_risk_tier" {
  name        = "CEF – Context, Risk & Tier"
  description = "Adds network zones, direction, asset criticality, geo, static threat intel, risk factors/score, signature-based MITRE techniques and hot/warm/cold tier for CEF IDS alerts."
  config = {
    operations = [{
      operation   = "jq"
      description = ""
      arguments   = { query = chomp(file("${path.module}/jq/cef-risk-tier.jq")) }
    }]
  }
}
