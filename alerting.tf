# ---------------------------------------------------------------------------
# Alerting: the rule that detects, and the pipeline that delivers.
#
# Both halves are managed here. Provider 0.4.0 added `monad_alert_rule`, so the
# rule no longer has to be clicked into the UI or POSTed by hand and then lost
# on the next rebuild — it is declared next to the pipeline it watches, and a
# rebuild of the org recreates it with everything else.
#
# `rule_config` is free-form (each alert type has its own settings schema,
# validated by the API on write), exactly like `monad_transform.config`, so it
# uses the same jsondecode(jsonencode(...)) idiom. `type` is immutable: changing
# it forces a replace.
#
# The delivery pipeline below is what turns a fired rule into something a human
# sees. A rule on its own only demonstrates detection.
# ---------------------------------------------------------------------------

# Fires when the CloudTrail pipeline ingests more than 10,000 records in a
# five-minute window — the "ingest spike" beat of the demo. The archive
# pipeline's bucket drain and the push generator can both cross this on
# demand; steady-state demo traffic cannot, so a fired alert is always a
# deliberate act. Expect a lag of a few minutes between crossing the threshold
# and the alert reaching Slack.
resource "monad_alert_rule" "cloudtrail_ingest_spike" {
  name        = "CloudTrail — Ingest Volume Spike"
  description = "More than 10,000 records ingested by the CloudTrail pipeline in a 5-minute window. Fired by the demo's ingest-spike scenario; steady-state traffic never reaches it."
  type        = "threshold-alert"
  severity    = "critical"
  active      = true

  pipeline_ids = [monad_pipeline.cloudtrail.id]

  rule_config = jsondecode(jsonencode({
    settings = {
      metric_config = {
        type = "records"
        records = {
          direction = "ingress"
          threshold = 10000
        }
      }
      operator    = "greater_than"
      time_window = "5m"
    }
  }))
}

# Monad's own alerts stream — every rule that fires or resolves, org-wide.
# No settings and no cron: it is a JetStream consumer, not a poller.
resource "monad_input" "alerts" {
  name        = "Monad Alerts"
  description = "Consumes triggered and resolved alerts from the Monad alerting system, org-wide."
  type        = "monad-alerts"

  config {
    settings = jsondecode(jsonencode({}))
  }
}

# Slack will not render a raw alert payload usefully — see the jq for why.
#
# The jq is a templatefile: the pipeline id -> name map it uses to label alerts
# is rendered from the pipeline resources, so a rebuild (new UUIDs) updates this
# transform in place instead of leaving Slack messages that name nothing.
# The alerting pipeline itself is deliberately NOT in the map — it references
# this transform, so including its id would be a dependency cycle.
resource "monad_transform" "trim_alert_payload" {
  name        = "Trim Alert Payload"
  description = "Drops the full old_schema/new_schema snapshots a schema-detection alert carries (tens of KB on a normalized record) and resolves pipeline/rule ids into names and links, so the Slack template never prints a bare UUID as visible text."

  config = jsondecode(jsonencode({
    operations = [
      {
        operation = "jq"
        arguments = {
          key = ""
          query = templatefile("${path.module}/jq/trim-alert-payload.jq.tftpl", {
            base_url = var.monad_base_url
            pipelines_json = jsonencode({
              (monad_pipeline.cloudtrail.id) = monad_pipeline.cloudtrail.name
              (monad_pipeline.archive.id)    = monad_pipeline.archive.name
            })
          })
        }
      },
    ]
  }))
}

# The webhook secret is OWNED BY THE PARENT ORG (kenneth-testing) and shared into
# this one, so it is referenced by id and deliberately NOT declared as a
# monad_secret here: a share recipient can use a shared secret but cannot edit or
# delete it, and Terraform managing it would mean planning writes that 403.
resource "monad_output" "slack" {
  name        = "Slack — #kenneth-demo"
  description = "Posts fired and resolved Monad alerts to Slack via incoming webhook. The message template renders threshold alerts as a plain sentence with the measured value against the threshold."
  type        = "slack"

  config {
    settings = jsondecode(jsonencode({
      auth_config = {
        type = "webhook"
        webhook = {
          webhook_url = { id = var.slack_webhook_secret_id }
        }
      }
      message_template = file("${path.module}/slack-alert-template.tmpl")
    }))
  }
}

resource "monad_pipeline" "alerting" {
  name        = "Monad Alerting"
  description = "Delivers fired and resolved alerts to Slack. Trims the payload first so the message is readable rather than a wall of schema JSON."
  enabled     = true

  nodes {
    slug           = "alerts-in"
    component_type = "input"
    component_id   = monad_input.alerts.id
  }
  nodes {
    slug           = "trim"
    component_type = "transform"
    component_id   = monad_transform.trim_alert_payload.id
  }
  nodes {
    slug           = "slack"
    component_type = "output"
    component_id   = monad_output.slack.id
  }

  edges {
    from_node_instance_slug = "alerts-in"
    to_node_instance_slug   = "trim"
    condition {
      operator = "always"
    }
  }
  edges {
    description             = "every fired and resolved alert reaches Slack"
    from_node_instance_slug = "trim"
    to_node_instance_slug   = "slack"
    condition {
      operator = "always"
    }
  }
}
