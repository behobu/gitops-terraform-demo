# One-time state adoption.
#
# "CloudTrail to ECS v8.11.0" was created directly against the API on
# 2026-08-07 while the ECS normalization was being built and validated, so it
# exists in the org but not in Terraform state. Without this block the next
# apply would drop the ecs-normalize node from the pipeline and silently revert
# that work.
#
# Declarative import (Terraform >= 1.5) rather than a manual `terraform import`
# so the adoption is visible in the plan a reviewer reads, and happens in CI
# with no out-of-band state surgery.
#
# REMOVE THIS BLOCK in a follow-up PR once the apply on main has succeeded and
# the resource is in state.
import {
  to = monad_transform.cloudtrail_to_ecs
  id = "b717b594-189c-449e-a50e-a847409a93e5"
}
