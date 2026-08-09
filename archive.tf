# ---------------------------------------------------------------------------
# The archive pipeline: S3 in -> S3 out.
#
# This is the resilience story, deliberately kept separate from the CloudTrail
# pipeline, for two reasons.
#
# 1. It has to be. `ValidateUniqueTargets` in core enforces at most ONE incoming
#    edge per node, so a second input cannot join the existing chain.
#
# 2. It is better this way. Record count here is exactly 1:1 — nothing dedupes,
#    nothing splits — so "1500 records in, 1500 records out, nothing lost" is
#    checkable on screen. The CloudTrail pipeline can never show that, because
#    dedup and tiering deliberately change the numbers between in and out.
#
# Seed the input bucket with:
#   scripts/jfrog-demo/push-cloudtrail-events.py --count 1500 --objects 12 \
#     --to-s3 <ingest bucket>
#
# Created DISABLED. The input bucket is pre-populated, so enabling it starts the
# drain — that backlog IS the ingest spike, and it should be a deliberate beat
# rather than something that already happened while nobody was looking.
# ---------------------------------------------------------------------------

# The pull source. A pull source matters for the lossless claim: under
# back-pressure pull sources pause and resume losslessly, whereas push sources
# get 429 — and a generator that ignores 429 drops records at the generator,
# which looks exactly like Monad losing them.
#
# format = "jsonl" is required, not cosmetic. The jsonl handler scans
# line-by-line and emits one record per line; "json" would treat each whole
# object as a single record and 12 objects would ingest as 12 records.
resource "monad_input" "archive_source" {
  name        = "CloudTrail Archive (S3)"
  description = "Pull source reading NDJSON CloudTrail objects from the ingest bucket. Pre-populating the bucket creates a backlog the pipeline drains as fast as it can, which is the ingest spike."
  type        = "s3"

  config {
    settings = jsondecode(jsonencode({
      bucket           = var.s3_ingest_bucket
      region           = var.s3_region
      prefix           = "cloudtrail"
      role_arn         = var.s3_role_arn
      compression      = "none"
      format           = "jsonl"
      partition_format = "simple date"
      # Empty = full sync of everything present on the first run, incremental
      # thereafter. That full first sync is exactly the backlog we want.
      backfill_start_time = ""
    }))
  }
}

# The archive destination. Same bucket as the cold tier, different prefix, so a
# single bucket-policy Deny takes down both the cold tier and the archive while
# hot and warm keep flowing — one lever, and it demonstrates that buffering and
# replay are per-node rather than per-pipeline.
resource "monad_output" "archive_s3" {
  name        = "CloudTrail Archive (S3)"
  description = "Durable archive of every ingested record, unmodified. The destination taken offline in the outage-recovery scenario."
  type        = "s3"

  config {
    settings = jsondecode(jsonencode({
      role_arn         = var.s3_role_arn
      bucket           = var.s3_bucket
      region           = var.s3_region
      prefix           = "archive"
      compression      = "none"
      partition_format = "simple date"
      format_config = {
        Format      = "json"
        json_format = { type = "line" }
      }
      batch_config = {
        batch_record_count = 500
        batch_data_size    = 1048576
        publish_rate       = 5
      }
    }))
  }
}

# No transforms: the point is that the count going in equals the count coming
# out. Anything in the middle invites the question of whether the transform ate
# the difference.
resource "monad_pipeline" "archive" {
  name        = "CloudTrail Archive"
  description = "Durable S3-to-S3 archive. Demonstrates ingest-spike absorption (draining a pre-populated bucket) and lossless recovery from a destination outage. Record count is 1:1 end to end."
  enabled     = false

  nodes {
    slug           = "archive-source"
    component_type = "input"
    component_id   = monad_input.archive_source.id
  }
  nodes {
    slug           = "archive-sink"
    component_type = "output"
    component_id   = monad_output.archive_s3.id
  }

  edges {
    description             = "every record, unmodified — count in must equal count out"
    from_node_instance_slug = "archive-source"
    to_node_instance_slug   = "archive-sink"
    condition {
      operator = "always"
    }
  }
}
