terraform {
  # Write-only arguments are a Terraform 1.11 feature, and the monad provider
  # declares `WriteOnly` on `config.secrets` (monad_input / monad_output /
  # monad_enrichment) and on `monad_secret.value`. Terraform releases before
  # 1.11 reject a schema carrying them.
  required_version = ">= 1.11"

  required_providers {
    monad = {
      source = "monad-inc/monad"
      # Pinned to the 0.5.x patch line on purpose. While the provider is pre-1.0
      # it ships breaking changes as *minor* bumps, so a minor upgrade stays a
      # deliberate, reviewed commit. 0.5.2 is the floor because it is the first
      # release where an imported connector with no secrets plans no update
      # (config.secrets_hash keeps its state value) and a timed-out create is
      # adopted instead of orphaned (ENG-10511).
      version = "~> 0.5.2"
    }
  }
}
