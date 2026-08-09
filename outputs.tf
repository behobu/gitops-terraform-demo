resource "monad_output" "sink" {
  name        = "Elasticsearch"
  description = "Demonstration sink. dev-null discards all records — intentional for this demo. Swap type/settings for a real destination when needed."
  type        = "dev-null"
}

# The dedup KV table. Every record that survives the duplicate check writes its
# fingerprint here, so the next copy of the same record finds it.
#
# ttl is the JetStream KV ENTRY lifetime — how long a fingerprint stays
# remembered, i.e. the deduplication window. 48h is the documented maximum
# (bounds: 5s .. 48h, default 300s). Note this is NOT the enrichment's 10s
# in-process response cache, which is a hard-coded constant and a different
# thing entirely (ENG-9542 asks for it to be configurable).
#
# value_field stores just the digest rather than the whole record: nothing reads
# the value back, only the key's existence matters, and storing whole records
# here would be pure waste.
resource "monad_output" "dedup_store" {
  name        = "Dedup Fingerprints (KV)"
  description = "Key-value table of record fingerprints. Written only for records that passed the duplicate check; read by the Dedup Lookup enrichment. 48h TTL is the deduplication window."
  type        = "kv-lookup"

  config {
    settings = jsondecode(jsonencode({
      key_field   = "_dedup_key"
      value_field = "_dedup_key"
      ttl         = 172800
    }))
  }
}

# Warm and cold destinations for the tiering split.
#
# dev-null stand-ins, exactly like the "Elasticsearch" sink above: the point of
# the tiering demo is the SPLIT and the volume that never reaches the expensive
# tier, both visible as per-node throughput on the pipeline graph. The names say
# what each would be in a real deployment.
resource "monad_output" "warm_archive" {
  name        = "S3 Standard — warm"
  description = "Demonstration sink. dev-null discards all records — intentional for this demo. Stands in for general-purpose object storage holding the mid-value tier."
  type        = "dev-null"
}

# Superseded by monad_output.cold_s3 below. Kept declared, but no longer
# referenced by the pipeline, so this apply does not try to delete a component
# that is still wired in — the API refuses that, and Terraform schedules the
# delete in parallel with the pipeline update rather than after it. Removed in a
# follow-up PR once the pipeline no longer points at it.
resource "monad_output" "cold_archive" {
  name        = "S3 Glacier — cold (retired)"
  description = "Retired dev-null stand-in, superseded by the real S3 cold archive. Unreferenced; removed in a follow-up PR."
  type        = "dev-null"
}

# The real cold-tier destination: object storage in the Monad development
# account, reached by cross-account assume-role.
#
# This is what makes the outage scenario real. Denying s3:PutObject on the
# bucket takes exactly one destination offline while hot and warm keep flowing,
# which is the point: buffering and replay are per-node, not per-pipeline.
#
# Observed during a standalone rehearsal of this exact failure: the node logs
# the AWS error verbatim, backs off 0.98s -> 2.03s -> 4.07s -> 8.02s, then goes
# quiet as messages move to its own retry subject. Silence is expected, not a
# hang. Recovery after restoring the policy took ~60-90s for a ~5 minute outage
# and the whole buffer landed as a single object, with no duplicates and no
# gaps. Retry backoff is 2^n capped at 15 minutes with no dead-letter, so a
# LONGER outage costs a longer tail — keep the demo's Deny window short.
#
# Bucket and role arrive via TF_VAR_* from Actions secrets: this repo is public
# and the account id is sensitive-but-not-secret, the same reason the retired
# CloudTrail input's bucket/role were handled this way.
#
# compression is "none" deliberately. gzip is the realistic choice for an
# archive tier, but a demo benefits more from being able to open an object and
# read it than from a few saved bytes.
resource "monad_output" "cold_s3" {
  # Component names are unique per organization, and Terraform has no reason to
  # order this create after the rename above — it ran both in the same instant
  # and the create lost with `400 components with this name already exists`.
  # depends_on forces the old holder to release the name first. Remove this once
  # monad_output.cold_archive is gone.
  depends_on = [monad_output.cold_archive]

  name        = "S3 Glacier — cold"
  description = "Archival object storage for the cold tier: read-only API calls, the overwhelming majority of any real trail. Written as NDJSON, partitioned by date. This is the destination taken offline in the outage-recovery scenario."
  type        = "s3"

  config {
    settings = jsondecode(jsonencode({
      role_arn         = var.s3_role_arn
      bucket           = var.s3_bucket
      region           = var.s3_region
      prefix           = "cold"
      compression      = "none"
      partition_format = "simple date"
      format_config = {
        Format      = "json"
        json_format = { type = "line" }
      }
      # 5s publish rate so the demo does not wait on a batch timer. The record
      # and size limits are the minimum the connector accepts (500 / 1 MiB).
      batch_config = {
        batch_record_count = 500
        batch_data_size    = 1048576
        publish_rate       = 5
      }
    }))
  }
}
