# Topology
#
#   Syslog – Intake:  syslog-in → parse-classify → hygiene ─┬─ data_type=firewall   → http-out-firewall   ─┐
#                                                           ├─ data_type=linux_auth → http-out-linux-auth ─┤ (HTTP, x-api-key)
#                                                           ├─ data_type=cef_alert  → http-out-cef        ─┤
#                                                           └─ anything else        → cold-s3-archive      │
#                                                                                                          ▼
#   Syslog – Firewall:   http-in → parse → geo-src → geo-dest → context ─┬─ tier=hot  → Splunk index=netfw
#   Syslog – Linux Auth: http-in → parse → geo-src → context ────────────┼─ tier=warm → Databricks (shared)
#   Syslog – CEF:        http-in → parse → geo-src → geo-dest → context ─┴─ tier=cold → S3 archive (shared)
#
# Edge conditions: a root must be a logical operator (and/or/nor/xor/always/never).

# ---------------------------------------------------------------------------
resource "monad_pipeline" "intake" {
  name        = "Syslog – Intake"
  description = "Receives syslog over TLS :6514, parses and classifies each record, drops heartbeats/empties/1-minute _raw duplicates, and fans out by data_type to the per-type pipelines; unrecognized records go to the cold archive."
  enabled     = true

  nodes {
    slug           = "syslog-in"
    component_type = "input"
    component_id   = monad_input.syslog_tls.id
  }
  nodes {
    slug           = "parse-classify"
    component_type = "transform"
    component_id   = monad_transform.intake_parse_classify.id
  }
  nodes {
    slug           = "hygiene"
    component_type = "transform"
    component_id   = monad_transform.intake_hygiene.id
  }
  nodes {
    slug           = "http-out-firewall"
    component_type = "output"
    component_id   = monad_output.http_out_firewall.id
  }
  nodes {
    slug           = "http-out-linux-auth"
    component_type = "output"
    component_id   = monad_output.http_out_linux_auth.id
  }
  nodes {
    slug           = "http-out-cef"
    component_type = "output"
    component_id   = monad_output.http_out_cef.id
  }
  nodes {
    slug           = "cold-s3-archive"
    component_type = "output"
    component_id   = monad_output.cold_s3_archive.id
  }

  edges {
    from_node_instance_slug = "syslog-in"
    to_node_instance_slug   = "parse-classify"
    condition { operator = "always" }
  }
  edges {
    from_node_instance_slug = "parse-classify"
    to_node_instance_slug   = "hygiene"
    condition { operator = "always" }
  }
  edges {
    name                    = "firewallLogs"
    description             = "PAN-OS firewall records (data_type=firewall) go to the Firewall pipeline."
    from_node_instance_slug = "hygiene"
    to_node_instance_slug   = "http-out-firewall"
    condition {
      operator = "and"
      conditions {
        type_id = "equals"
        config {
          key   = "data_type"
          value = "firewall"
        }
      }
    }
  }
  edges {
    name                    = "linuxAuthLogs"
    description             = "sshd/sudo/su/cron/login records (data_type=linux_auth) go to the Linux Auth pipeline."
    from_node_instance_slug = "hygiene"
    to_node_instance_slug   = "http-out-linux-auth"
    condition {
      operator = "and"
      conditions {
        type_id = "equals"
        config {
          key   = "data_type"
          value = "linux_auth"
        }
      }
    }
  }
  edges {
    name                    = "cefAlerts"
    description             = "CEF IDS alerts (data_type=cef_alert) go to the CEF IDS Alerts pipeline."
    from_node_instance_slug = "hygiene"
    to_node_instance_slug   = "http-out-cef"
    condition {
      operator = "and"
      conditions {
        type_id = "equals"
        config {
          key   = "data_type"
          value = "cef_alert"
        }
      }
    }
  }
  edges {
    name                    = "unrecognizedToArchive"
    description             = "Records that are not firewall, linux_auth or cef_alert are kept in the cold S3 archive, never dropped."
    from_node_instance_slug = "hygiene"
    to_node_instance_slug   = "cold-s3-archive"
    condition {
      operator = "nor"
      conditions {
        type_id = "equals_any"
        config {
          key    = "data_type"
          values = ["firewall", "linux_auth", "cef_alert"]
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
resource "monad_pipeline" "firewall" {
  name        = "Syslog – Firewall (PAN-OS)"
  description = "Parses PAN-OS firewall logs to CIM, redacts secrets, geolocates src/dest, scores risk and routes by tier to Splunk (netfw), Databricks or S3 archive."
  enabled     = true

  nodes {
    slug           = "http-in-firewall"
    component_type = "input"
    component_id   = monad_input.http_in_firewall.id
  }
  nodes {
    slug           = "parse-firewall"
    component_type = "transform"
    component_id   = monad_transform.firewall_parse.id
  }
  nodes {
    slug           = "geo-src"
    component_type = "enrichment"
    component_id   = monad_enrichment.geolocus_src.id
  }
  nodes {
    slug           = "geo-dest"
    component_type = "enrichment"
    component_id   = monad_enrichment.geolocus_dest.id
  }
  nodes {
    slug           = "context-firewall"
    component_type = "transform"
    component_id   = monad_transform.firewall_risk_tier.id
  }
  nodes {
    slug           = "splunk-netfw"
    component_type = "output"
    component_id   = monad_output.splunk_netfw.id
  }
  nodes {
    slug           = "warm-databricks"
    component_type = "output"
    component_id   = monad_output.warm_databricks.id
  }
  nodes {
    slug           = "cold-s3-archive"
    component_type = "output"
    component_id   = monad_output.cold_s3_archive.id
  }

  edges {
    from_node_instance_slug = "http-in-firewall"
    to_node_instance_slug   = "parse-firewall"
    condition { operator = "always" }
  }
  edges {
    from_node_instance_slug = "parse-firewall"
    to_node_instance_slug   = "geo-src"
    condition { operator = "always" }
  }
  edges {
    from_node_instance_slug = "geo-src"
    to_node_instance_slug   = "geo-dest"
    condition { operator = "always" }
  }
  edges {
    from_node_instance_slug = "geo-dest"
    to_node_instance_slug   = "context-firewall"
    condition { operator = "always" }
  }

  dynamic "edges" {
    for_each = {
      hot  = { name = "hotFirewall", to = "splunk-netfw", description = "Hot-tier firewall records (threat logs, risk_score >= 50, or blocked to PCI) go to Splunk index=netfw." }
      warm = { name = "warmFirewall", to = "warm-databricks", description = "Warm-tier firewall records go to the Databricks security lake." }
      cold = { name = "coldFirewall", to = "cold-s3-archive", description = "Cold-tier firewall records (low-risk allowed internal-to-internal traffic) go to the S3 archive." }
    }
    content {
      name                    = edges.value.name
      description             = edges.value.description
      from_node_instance_slug = "context-firewall"
      to_node_instance_slug   = edges.value.to
      condition {
        operator = "and"
        conditions {
          type_id = "equals"
          config {
            key   = "tier"
            value = edges.key
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
resource "monad_pipeline" "linux_auth" {
  name        = "Syslog – Linux Auth"
  description = "Parses sshd/sudo/session events to CIM, redacts secrets, geolocates src, scores risk and routes by tier to Splunk (os_auth), Databricks or S3 archive."
  enabled     = true

  nodes {
    slug           = "http-in-linux-auth"
    component_type = "input"
    component_id   = monad_input.http_in_linux_auth.id
  }
  nodes {
    slug           = "parse-linux-auth"
    component_type = "transform"
    component_id   = monad_transform.linux_auth_parse.id
  }
  nodes {
    slug           = "geo-src"
    component_type = "enrichment"
    component_id   = monad_enrichment.geolocus_src.id
  }
  nodes {
    slug           = "context-linux-auth"
    component_type = "transform"
    component_id   = monad_transform.linux_auth_risk_tier.id
  }
  nodes {
    slug           = "splunk-os-auth"
    component_type = "output"
    component_id   = monad_output.splunk_os_auth.id
  }
  nodes {
    slug           = "warm-databricks"
    component_type = "output"
    component_id   = monad_output.warm_databricks.id
  }
  nodes {
    slug           = "cold-s3-archive"
    component_type = "output"
    component_id   = monad_output.cold_s3_archive.id
  }

  edges {
    from_node_instance_slug = "http-in-linux-auth"
    to_node_instance_slug   = "parse-linux-auth"
    condition { operator = "always" }
  }
  edges {
    from_node_instance_slug = "parse-linux-auth"
    to_node_instance_slug   = "geo-src"
    condition { operator = "always" }
  }
  edges {
    from_node_instance_slug = "geo-src"
    to_node_instance_slug   = "context-linux-auth"
    condition { operator = "always" }
  }

  dynamic "edges" {
    for_each = {
      hot  = { name = "hotLinuxAuth", to = "splunk-os-auth", description = "Hot-tier auth events (risk_score >= 30) go to Splunk index=os_auth." }
      warm = { name = "warmLinuxAuth", to = "warm-databricks", description = "Warm-tier auth events go to the Databricks security lake." }
      cold = { name = "coldLinuxAuth", to = "cold-s3-archive", description = "Cold-tier auth events (session open/close) go to the S3 archive." }
    }
    content {
      name                    = edges.value.name
      description             = edges.value.description
      from_node_instance_slug = "context-linux-auth"
      to_node_instance_slug   = edges.value.to
      condition {
        operator = "and"
        conditions {
          type_id = "equals"
          config {
            key   = "tier"
            value = edges.key
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
resource "monad_pipeline" "cef" {
  name        = "Syslog – CEF IDS Alerts"
  description = "Parses CEF IDS alerts to CIM, redacts secrets, geolocates src/dest, scores risk and routes by tier to Splunk (ids), Databricks or S3 archive."
  enabled     = true

  nodes {
    slug           = "http-in-cef"
    component_type = "input"
    component_id   = monad_input.http_in_cef.id
  }
  nodes {
    slug           = "parse-cef"
    component_type = "transform"
    component_id   = monad_transform.cef_parse.id
  }
  nodes {
    slug           = "geo-src"
    component_type = "enrichment"
    component_id   = monad_enrichment.geolocus_src.id
  }
  nodes {
    slug           = "geo-dest"
    component_type = "enrichment"
    component_id   = monad_enrichment.geolocus_dest.id
  }
  nodes {
    slug           = "context-cef"
    component_type = "transform"
    component_id   = monad_transform.cef_risk_tier.id
  }
  nodes {
    slug           = "splunk-ids"
    component_type = "output"
    component_id   = monad_output.splunk_ids.id
  }
  nodes {
    slug           = "warm-databricks"
    component_type = "output"
    component_id   = monad_output.warm_databricks.id
  }
  nodes {
    slug           = "cold-s3-archive"
    component_type = "output"
    component_id   = monad_output.cold_s3_archive.id
  }

  edges {
    from_node_instance_slug = "http-in-cef"
    to_node_instance_slug   = "parse-cef"
    condition { operator = "always" }
  }
  edges {
    from_node_instance_slug = "parse-cef"
    to_node_instance_slug   = "geo-src"
    condition { operator = "always" }
  }
  edges {
    from_node_instance_slug = "geo-src"
    to_node_instance_slug   = "geo-dest"
    condition { operator = "always" }
  }
  edges {
    from_node_instance_slug = "geo-dest"
    to_node_instance_slug   = "context-cef"
    condition { operator = "always" }
  }

  dynamic "edges" {
    for_each = {
      hot  = { name = "hotCefAlerts", to = "splunk-ids", description = "Hot-tier IDS alerts (severity_id >= 4 or risk_score >= 50) go to Splunk index=ids." }
      warm = { name = "warmCefAlerts", to = "warm-databricks", description = "Warm-tier IDS alerts (severity_id 1-3) go to the Databricks security lake." }
      cold = { name = "coldCefAlerts", to = "cold-s3-archive", description = "Cold-tier IDS alerts (severity_id 0 or missing) go to the S3 archive." }
    }
    content {
      name                    = edges.value.name
      description             = edges.value.description
      from_node_instance_slug = "context-cef"
      to_node_instance_slug   = edges.value.to
      condition {
        operator = "and"
        conditions {
          type_id = "equals"
          config {
            key   = "tier"
            value = edges.key
          }
        }
      }
    }
  }
}
