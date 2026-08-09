# The pipeline is fed by an HTTP push endpoint rather than a live cloud source.
#
# It reads as "CloudTrail" throughout the demo because the records pushed to it
# ARE CloudTrail control-plane events — the downstream transforms and the ECS
# normalization are unchanged and still operate on genuine CloudTrail shapes.
# Only the delivery mechanism is mocked: events arrive by POST instead of being
# polled from an S3 bucket.
#
# This replaces a `cloudtrail` input that read a real, internal Monad AWS
# account's org trail. That is not ours to show, and a demo must never depend on
# whatever happens to be flowing through a production account at the time. A
# push endpoint also makes the demo deterministic and replayable, which the
# outage-recovery and dedup scenarios require.
resource "monad_input" "cloudtrail" {
  name        = "CloudTrail"
  description = "AWS CloudTrail control-plane events, pushed to Monad's HTTP ingest endpoint."
  type        = "monad-http"
  config {
    # No settings: the HTTP input needs no polling schedule and no credentials.
    # Declared explicitly (rather than omitting the block) so it matches the
    # empty settings object the API stores and does not plan a diff.
    settings = jsondecode(jsonencode({}))
  }
}
