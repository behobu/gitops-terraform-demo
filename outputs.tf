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

resource "monad_output" "cold_archive" {
  name        = "S3 Glacier — cold"
  description = "Demonstration sink. dev-null discards all records — intentional for this demo. Stands in for archival storage holding high-volume, low-value service chatter."
  type        = "dev-null"
}
