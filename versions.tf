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
      # Pinned to the 0.3.x line on purpose. While the provider is pre-1.0 it
      # ships breaking changes as *minor* bumps — 0.2.0 made `config.secrets`
      # write-only and replaced the bare-string secret with a structured
      # object. A floating ">= 0.3.0" would adopt the next such break silently
      # on the first CI run after it publishes, so minor upgrades stay a
      # deliberate, reviewed commit (as #7 was).
      version = "~> 0.3.0"
    }
  }
}
