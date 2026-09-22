terraform {
  # Write-only arguments are a Terraform 1.11 feature, and the monad provider
  # declares `WriteOnly` on `config.secrets` (monad_input / monad_output /
  # monad_enrichment) and on `monad_secret.value`. Terraform releases before
  # 1.11 reject a schema carrying them, so ">= 1.5" was never a workable floor
  # for this provider — it just went unnoticed because nothing here uses secrets
  # yet.
  required_version = ">= 1.11"

  required_providers {
    monad = {
      source = "monad-inc/monad"
      # Pinned to the 0.4.x line on purpose. While the provider is pre-1.0 it
      # ships breaking changes as *minor* bumps — 0.2.0 made `config.secrets`
      # write-only and replaced the bare-string secret with a structured
      # object; 0.4.0 made edge-condition `config.value` a scalar and turned
      # pipeline `nodes`/`edges` into sets. A floating ">= 0.4.0" would adopt
      # the next such break silently on the first CI run after it publishes, so
      # minor upgrades stay a deliberate, reviewed commit (as #7 and this one
      # were). 0.4.1 is the floor because it is the first release where a
      # `monad_secret` applies cleanly more than once (ENG-9867) and a
      # value-only rotation actually reaches the API (ENG-9235).
      version = "~> 0.4.1"
    }
  }
}
