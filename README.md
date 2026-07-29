# Monad GitOps demo — Terraform

Declarative, Git-driven management of a [Monad](https://app.monad.com) security
data pipeline using **Terraform** and the `monad-inc/monad` provider. Edit the
`.tf`, open a PR; a workflow posts a `terraform plan`; on merge, a workflow runs
`terraform apply` against the Monad org. Sibling of the JSON/LLM demo
(`gitops-demo`) — same capabilities and constraints, native Terraform engine.

```
edit *.tf ──▶ open PR ──▶ [terraform-plan] posts plan comment ──▶ review + merge ──▶ [terraform-apply] applies to Monad
```

## Same capabilities, native mechanisms

The JSON demo hand-built these; Terraform gives them for free:

| Capability | JSON demo (LLM reconciler) | This repo (Terraform) |
|---|---|---|
| Object identity | `.monad-lock.json` (ref → id) | Terraform **state** (in S3) |
| Self-heal (deleted in UI) | LLM GET→404→recreate | `terraform apply` recreates drifted/missing resources |
| Prune | `prune: true` in the contract | remove the resource block → `apply` destroys it |
| Plan on PR / apply on merge | LLM `MODE=plan` / `MODE=apply` | `terraform plan` / `terraform apply` |
| Secrets / sensitive values | `env:VAR` pass-through | `TF_VAR_*` from GitHub secrets; connector `secrets` are write-only — never in state ([details](#secrets-write-only)) |
| Merge gate | `protect-main` ruleset | same `protect-main` ruleset |

**No LLM, no lockfile, no bypass actor.** Because apply writes state to S3 (not
back to the repo), nothing in CI pushes to `main`, so the JSON demo's deploy-key
bypass (Gotcha 1) is unnecessary here.

## Secrets (write-only)

Nothing in this repo currently needs a connector secret — the CloudTrail input
authenticates by cross-account assume-role, and the sink is `dev-null`. The
rules below apply the moment you add a connector that does, and they are why
`versions.tf` requires Terraform **>= 1.11** and pins the provider to `~> 0.3.0`.

- **`config.secrets` is write-only** on `monad_input`, `monad_output` and
  `monad_enrichment` (as is `monad_secret.value`). The value is sent to the
  Monad API and **never persisted to Terraform state**. Write-only arguments
  are a Terraform 1.11 feature — earlier versions reject the schema outright.
- **Each entry must be an object, not a bare string.** A bare string errors at
  apply. Either define a new secret or reference an existing one:

  ```hcl
  config {
    settings = jsondecode(jsonencode({ /* ... */ }))

    secrets = jsondecode(jsonencode({
      # a new secret — value/name/description must all be non-empty
      api_key = {
        value       = var.example_api_key # TF_VAR_example_api_key, from an Actions secret
        name        = "example-api-key"
        description = "API key for the example connector"
      }

      # or a reference to a secret that already exists in the org
      # api_key = { id = "00000000-0000-0000-0000-000000000000" }
    }))
  }
  ```

- **Rotation is detected via `config.secrets_hash`**, a computed HMAC
  fingerprint the provider maintains. Because the value is never read back,
  that hash is the only thing a plan can compare — so changing the configured
  secret shows up as a `secrets_hash` change, not as a diff on the secret.
- Keep supplying the material through `TF_VAR_*` from Actions secrets, exactly
  as `ct_bucket` / `ct_role_arn` are today. Never commit it.

Upgrading the provider across a minor version is deliberate for this reason:
while it is pre-1.0, breaking changes ship as minor bumps. 0.2.0 is what made
`secrets` write-only and replaced the bare-string form, so a floating
constraint would have adopted that break unreviewed.

## Layout

```
versions.tf     provider requirement (monad-inc/monad ~> 0.3.0, tf >= 1.11)
backend.tf      S3 remote state (partial config; filled at `terraform init`)
provider.tf     monad provider (base_url / api_token / organization_id vars)
variables.tf    inputs incl. ct_bucket / ct_role_arn (sensitive, from secrets)
inputs.tf       Org CloudTrail Logs (settings from vars)
transforms.tf   Drop Low-Value Fields, Drop CloudTrail Duplicated Data
outputs.tf      dev-null sink (named "Elasticsearch" — intentional demo sink)
pipelines.tf    Cloudtrail pipeline: input → 2 transforms → sink
.github/workflows/{plan,apply}.yml   (Terraform CLI pinned — bump both together)
```

## Setup

1. **S3 backend + AWS access (decide first — provisions AWS):**
   - An S3 bucket for state (private, encrypted, versioning on).
   - CI auth to it via GitHub OIDC: an IAM role trusting this repo, with
     `s3:GetObject/PutObject/ListBucket` on the state bucket. (Static IAM user
     keys work too — swap `role-to-assume` for `aws-access-key-id`/`-secret`.)
2. **Secrets** (Settings → Secrets and variables → Actions):
   - `MONAD_API_TOKEN` — Monad API key for the target org.
   - `MONAD_ORG_ID` — target organization id.
   - `MONAD_CT_BUCKET`, `MONAD_CT_ROLE_ARN` — CloudTrail bucket + role ARN.
   - `TF_STATE_BUCKET` — the S3 state bucket name.
   - `AWS_ROLE_ARN` — the OIDC role to assume.
3. **Merge gate:** the `protect-main` ruleset requires a PR approved by someone
   other than the author (needs a public repo or GitHub Pro). Solo-repo caveat:
   with only one collaborator no PR can self-approve, so add a second account or
   keep enforcement off while demoing alone.
4. **Provider registry:** `terraform init` pulls `monad-inc/monad` from the
   Terraform Registry — confirm it resolves for your setup.

## Try it

- **Create from scratch:** point `MONAD_ORG_ID` at a pipeline-free org; first
  `apply` creates all five resources.
- **Change a transform:** edit `transforms.tf`, open a PR → plan shows the diff;
  merge → apply updates it in place.
- **Self-heal:** delete the pipeline (then its components) in the Monad UI, run
  `terraform-apply` (Actions → Run workflow) → Terraform sees the drift in state
  and recreates them.
- **Prune:** delete a resource block → plan shows `- destroy` → merge removes it
  from Monad.
