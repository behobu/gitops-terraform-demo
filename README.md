# Monad GitOps demo — Terraform

Declarative, Git-driven management of a [Monad](https://app.monad.com) security
data pipeline using **Terraform** and the `monad-inc/monad` provider. Edit the
`.tf`, open a PR; a workflow posts a `terraform plan`; on merge, a workflow runs
`terraform apply` against the Monad org.

The demo is the **syslog demo**: syslog over TLS is parsed, classified, cleaned
and fanned out by data type to three per-type pipelines, which map each record
to CIM fields, redact credentials, geolocate it, score its risk and route it by
tier to Splunk, a Databricks lake or an S3 archive.

The target is the **syslog-9001** team (`f01458bb-f43d-4e57-aaed-7c808e235fb3`)
under `kenneth-testing`. It moved there from the Terraform team on 2026-11-05.
The org id is in the workflow `env` (it is not a secret), so retargeting is one
reviewed diff (see [Moving to another team](#moving-to-another-team)).

```
edit *.tf ──▶ open PR ──▶ [terraform-plan] posts plan comment ──▶ review + merge ──▶ [terraform-apply] applies to Monad
```

## What it builds (26 resources)

```
Syslog – Intake:  syslog-in → parse-classify → hygiene ─┬─ data_type=firewall   → HTTP Out → Syslog – Firewall (PAN-OS)
                                                        ├─ data_type=linux_auth → HTTP Out → Syslog – Linux Auth
                                                        ├─ data_type=cef_alert  → HTTP Out → Syslog – CEF IDS Alerts
                                                        └─ anything else        → Cold – S3 Archive

Per-type pipeline: HTTP In → parse to CIM + redact → Geolocus src (→ dest) → context, risk & tier ─┬─ hot  → Splunk (netfw | os_auth | ids)
                                                                                                    ├─ warm → Warm – Databricks Security Lake
                                                                                                    └─ cold → Cold – S3 Archive
```

- **Senders** connect to `<Syslog – Intake pipeline id>.data.monad.com:6514`
  over TLS (RFC 3164/5424); SNI selects the pipeline.
- **Hygiene** drops `-- MARK --` heartbeats and empty messages, then exact
  `_raw` duplicates within 1 minute. Nothing else is dropped; unrecognized
  records go to the cold archive.
- **The fan-out** posts to each per-type pipeline's HTTP input, authenticating
  with the `syslog-demo-http-input-api-key` secret as `x-api-key`.
- **Every destination is a `dev-null` stand-in** for the system in its name, so
  the demo runs with no customer credentials.

## Same capabilities, native mechanisms

| Capability | Mechanism here |
|---|---|
| Object identity | Terraform **state** (in S3) |
| Self-heal (deleted in UI) | `terraform apply` recreates drifted/missing resources |
| Prune | remove the resource block → `apply` destroys it |
| Plan on PR / apply on merge | `terraform plan` / `terraform apply` workflows |
| On-demand plan (drift check) | Actions → **terraform-plan** → Run workflow (on `main`) |
| Secrets / sensitive values | `TF_VAR_*` from GitHub secrets; connector `secrets` are write-only — never in state ([details](#secrets-write-only)) |

Apply writes state to S3, not back to the repo, so nothing in CI pushes to
`main` and no bypass actor is needed.

## Secrets (write-only)

The only connector secret is the API key the intake's three HTTP outputs present
to the per-type HTTP inputs. It is a real credential, so it is **referenced by
id** (`var.http_input_api_key_secret_id`), not managed here. Its value never
touches this repo, the Actions secrets or Terraform state.

- **`config.secrets` is write-only** on `monad_input`, `monad_output` and
  `monad_enrichment` (as is `monad_secret.value`). The value is sent to the
  Monad API and never persisted to state. Write-only arguments are a
  Terraform 1.11 feature, which is why `versions.tf` requires **>= 1.11**.
- **Each entry is an object**: a reference `{ id = "..." }`, or a new inline
  secret `{ name, description, value }`. Nested secret fields nest the same way
  (see `local.http_fanout_secrets` in `outputs.tf`).
- **Rotation is detected via `config.secrets_hash`**, a fingerprint the
  provider keeps. The value is never read back, so the hash is all a plan can
  compare.
- **First apply after an import updates the three HTTP outputs in place.**
  Import cannot read write-only secrets back, so the first apply re-sends the
  same `x-api-key` reference and records its hash. Settings do not change.
  Later plans show no diff.

## Layout

```
versions.tf     provider requirement (monad-inc/monad ~> 0.5.2, tf >= 1.11)
backend.tf      S3 remote state (partial config; filled at `terraform init`)
provider.tf     monad provider (base_url / api_token / organization_id vars)
variables.tf    provider inputs + the HTTP-input API key secret id
inputs.tf       Syslog TLS :6514 + 3 per-type HTTP inputs
transforms.tf   8 transforms: intake parse/classify + hygiene, then parse and
                context/risk/tier for each of firewall, linux auth and CEF
enrichments.tf  Geolocus src + dest
outputs.tf      3 intake fan-out HTTP outputs + 5 dev-null destinations
pipelines.tf    Intake + Firewall + Linux Auth + CEF pipelines
imports.tf      import blocks adopting the live syslog-9001 components
jq/             transform bodies, kept in files so PR diffs are reviewable
.github/workflows/{plan,apply}.yml   (Terraform CLI pinned — bump both together)
bootstrap/      AWS OIDC role + state bucket policy (applied once, by hand)
```

## Setup

1. **S3 backend + AWS access** (already in place): a private, encrypted,
   versioned state bucket, and an IAM role trusting this repo through GitHub
   OIDC (`bootstrap/`). The role trusts `main` and pull requests only.
2. **Secrets** (Settings → Secrets and variables → Actions):
   - `MONAD_SYSLOG_API_TOKEN` — a Monad API key that can reach syslog-9001.
     Mint it in that team. The previous `MONAD_API_TOKEN` is scoped to the
     Terraform team and gets a 403 here. A missing secret expands to an empty
     string, so `variables.tf` fails the plan with a pointer back here.
   - `TF_STATE_BUCKET` — the S3 state bucket name.
   - `AWS_ROLE_ARN` — the OIDC role to assume.

   Pass `--repo` explicitly to `gh secret set`; setting a secret on the wrong
   repo succeeds silently.
3. **Merge gate:** the `protect-main` ruleset requires a PR approved by someone
   other than the author. With a single collaborator, add a second account or
   keep enforcement off while demoing alone.

## Try it

- **Plan on demand:** Actions → **terraform-plan** → Run workflow → `main`.
  The plan appears on the run's summary page. Use it to show drift after a
  change in the Monad UI.
- **Change a transform:** edit a file in `jq/`, open a PR → the plan shows the
  diff; merge → apply updates it in place.
- **Self-heal:** delete a pipeline in the Monad UI, run **terraform-apply**
  (Actions → Run workflow) → Terraform recreates it.
- **Prune:** delete a resource block → the plan shows `- destroy` → merge
  removes it from Monad.

## Two constraints worth knowing before you edit

**The fan-out endpoints are pipeline ids.** Each intake HTTP output posts to
`https://<per-type pipeline id>.data.monad.com`. Recreating a per-type pipeline
gives it a new id; Terraform follows the reference and updates the output. The
intake input's sender address changes the same way if the intake pipeline is
recreated.

**Replacing a component a pipeline references is a two-phase change.** Terraform
destroys the old component in parallel with the pipeline update, and the API
rejects deleting anything still wired into a pipeline. A clean plan is not
evidence it will apply. Either split it across two PRs, or rewire first with
`terraform apply -target=monad_pipeline.<name>` and then run a normal apply.

## Moving to another team

Each target org gets its own state file, so a move never touches the old org.

1. **Change the target in both workflows**: `TF_VAR_monad_organization_id` and
   `TF_STATE_KEY` (keep it under `gitops-terraform-demo/`, the prefix the AWS
   role may write).
2. **Set the API key secret** for the new org, and update the secret name in
   both workflows if you add a new one.
3. **Create the HTTP-input API key secret** in the new org and set
   `http_input_api_key_secret_id` to its id.
4. **Delete `imports.tf`** (the ids belong to syslog-9001), or replace them with
   the new org's ids to adopt an existing build.
5. Open a PR. A fresh org plans 26 to add; merge to apply. Senders then need
   the new intake pipeline id.

The previous target, the Terraform team (`terraform-0eca`), keeps its CloudTrail
demo and its state at `gitops-terraform-demo/terraform.tfstate`. Nothing here
manages it any more.
