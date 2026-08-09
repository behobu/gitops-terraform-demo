# Make a Monad alert renderable as one readable Slack message.
#
# Two jobs:
#
# 1. DROP the schema snapshots. A schema-detection-alert payload embeds the
#    COMPLETE old_schema AND new_schema, every field with its types, first_seen,
#    last_seen and count. On a normalized CloudTrail record that is tens of
#    kilobytes, which overruns what Slack will render and buries the one line
#    that matters. The `changes` array already says what actually changed.
#
# 2. ADD a `display` object resolving raw UUIDs to names and links. The template
#    then never prints a bare id as visible text — ids appear only inside link
#    targets, where they belong.
del(.metadata.old_schema, .metadata.new_schema)
| {
    "ac10c550-1451-4776-9a5c-41d3bd847490": "Cloudtrail",
    "a6200350-546b-40e1-8812-40427795d084": "CloudTrail Archive"
  } as $pipelines
| (.resource.resource_id // null) as $rid
| .display = {
    "pipeline_name": (if $rid then ($pipelines[$rid] // null) else null end),
    "pipeline_url":  (if $rid then "https://app.monad.com/pipelines/" + $rid else null end),
    "rule_url":      (if (.rule_id // null) then "https://app.monad.com/alerting/rules/" + .rule_id else null end),
    "alerts_url":    "https://app.monad.com/alerting/alerts"
  }
