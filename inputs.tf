resource "monad_input" "org_cloudtrail_logs" {
  name        = "Org CloudTrail Logs"
  description = "AWS CloudTrail control-plane events, read from the org CloudTrail S3 bucket via cross-account assume-role."
  type        = "cloudtrail"
  config {
    # jsondecode(jsonencode(...)) reproduces the decoded-object shape the
    # provider expects while letting bucket/role_arn come from variables.
    settings = jsondecode(jsonencode({
      backfill_start_time = ""
      bucket              = var.ct_bucket
      prefix              = ""
      region              = var.ct_region
      role_arn            = var.ct_role_arn
      use_synthetic_data  = false
    }))
  }
}
