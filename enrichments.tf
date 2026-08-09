# Dedup lookup: has this exact record been seen before?
#
# Joins on the HMAC digest staged by "Add Dedup Key" against the KV table that
# `monad_output.dedup_store` writes.
#
# ---------------------------------------------------------------------------
# Topology note — the lookup runs BEFORE the write, deliberately.
#
# The obvious wiring is to fan out from the fingerprint node to the KV writer
# and the KV reader in parallel. That is subtly wrong: both branches start at
# once, so a record's own key can land in the store before its own lookup
# returns, and a first sighting gets suppressed as a duplicate of itself —
# silent data loss.
#
# So the graph reads first and writes only on the not-seen branch. A record can
# never match itself, and the store still ends up with exactly the keys that
# passed. Verified end to end before this was built.
# ---------------------------------------------------------------------------
#
# omit_metadata is false on purpose: it makes a hit `code: "success"` and a miss
# `code: "no_match"`, which is an unambiguous test. With it true the payload is
# the raw value and a miss is a bare null, which is far easier to misread.
resource "monad_enrichment" "dedup_lookup" {
  name        = "Dedup Lookup"
  description = "Looks the record's fingerprint up in the KV table. A hit means this exact record has already passed through, so the duplicate is dropped rather than shipped twice."
  type        = "kv-lookup"

  config {
    settings = jsondecode(jsonencode({
      kv_lookup_output_id  = monad_output.dedup_store.id
      join_path            = "_dedup_key"
      destination_key      = "_dedup_seen"
      error_on_missing_key = false
      no_match_response    = "first-sighting"
      omit_metadata        = false
    }))
  }
}
