# HMAC key material for the deterministic mask that produces the dedup digest.
#
# This is a salt, not a credential — nothing authenticates with it and it grants
# access to nothing. It still lives in an Actions secret rather than in this
# public repo, because committing key material is a habit worth not having, and
# because `monad_secret.value` is write-only (never persisted to Terraform
# state) only when it is supplied as a variable.
#
# Rotating it invalidates every dedup key already stored in the KV table, which
# simply means previously-seen records are treated as new again. That is a safe
# reset, not corruption.
resource "monad_secret" "dedup_hmac_key" {
  name        = "dedup-hmac-key"
  description = "HMAC key material for the deterministic mask that builds the whole-record dedup digest. Salt, not a credential."
  value       = var.dedup_hmac_key
}
