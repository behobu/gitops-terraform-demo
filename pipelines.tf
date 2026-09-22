# CloudTrail pipeline.
#
#   cloudtrail-input
#     → drop-low-value-fields → ecs-normalize → drop-duplicated-data
#     → add-dedup-key → dedup-lookup → route-flags
#         ├─(not a duplicate)→ dedup-store          remember this fingerprint
#         └─(not a duplicate)→ strip-dedup-staging
#               ├─(hot) → sink           expensive SIEM
#               ├─(warm)→ warm-archive   general-purpose storage
#               └─(cold)→ cold-archive   cheap archive
#
# Duplicates are dropped at route-flags: they simply match no outgoing edge.
#
# EDGE CONDITIONS ARE PRESENCE TESTS BY DESIGN, NOT BY NECESSITY. Under
# provider 0.3.x they had to be: every leaf was serialized as {key, value: [...],
# rate}, so `equals` compared an array's JSON text against a scalar and
# `equals_any` never received its `values` field — 9 of the 11 rules silently
# routed nothing (ENG-9546). Provider 0.4.0 fixed that: `value` is a scalar,
# `equals_any` takes `values`, the full rule vocabulary is exposed, and a leaf
# missing a field its rule needs fails at `plan` instead of dropping records.
# The routing below still uses `key_exists` because "Route Flags" already turns
# every decision into a present-or-absent key, which is the cheapest test the
# engine has and keeps the routing logic in one reviewable jq file. Routing on
# values (`equals` on monad.retention_tier) is now a legitimate alternative,
# not a trap. See jq/route-flags.jq.
resource "monad_pipeline" "cloudtrail" {
  name        = "Cloudtrail"
  description = "CloudTrail control-plane events, field-trimmed, normalized to ECS v8.11.0, deduplicated on a whole-record fingerprint, and split across retention tiers by security value."
  enabled     = true

  nodes {
    slug           = "cloudtrail-input"
    component_type = "input"
    component_id   = monad_input.cloudtrail.id
  }
  nodes {
    slug           = "drop-low-value-fields"
    component_type = "transform"
    component_id   = monad_transform.drop_low_value_fields.id
  }
  nodes {
    slug           = "ecs-normalize"
    component_type = "transform"
    component_id   = monad_transform.cloudtrail_to_ecs.id
  }
  nodes {
    slug           = "drop-duplicated-data"
    component_type = "transform"
    component_id   = monad_transform.drop_cloudtrail_duplicated_data.id
  }
  nodes {
    slug           = "add-dedup-key"
    component_type = "transform"
    component_id   = monad_transform.add_dedup_key.id
  }
  nodes {
    slug           = "dedup-lookup"
    component_type = "enrichment"
    component_id   = monad_enrichment.dedup_lookup.id
  }
  nodes {
    slug           = "route-flags"
    component_type = "transform"
    component_id   = monad_transform.route_flags.id
  }
  nodes {
    slug           = "dedup-store"
    component_type = "output"
    component_id   = monad_output.dedup_store.id
  }
  nodes {
    slug           = "strip-dedup-staging"
    component_type = "transform"
    component_id   = monad_transform.strip_dedup_staging.id
  }
  nodes {
    slug           = "sink"
    component_type = "output"
    component_id   = monad_output.sink.id
  }
  nodes {
    slug           = "warm-archive"
    component_type = "output"
    component_id   = monad_output.warm_archive.id
  }
  nodes {
    slug           = "cold-archive"
    component_type = "output"
    component_id   = monad_output.cold_s3.id
  }

  edges {
    from_node_instance_slug = "cloudtrail-input"
    to_node_instance_slug   = "drop-low-value-fields"
    condition {
      operator = "always"
    }
  }
  edges {
    from_node_instance_slug = "drop-low-value-fields"
    to_node_instance_slug   = "ecs-normalize"
    condition {
      operator = "always"
    }
  }
  edges {
    from_node_instance_slug = "ecs-normalize"
    to_node_instance_slug   = "drop-duplicated-data"
    condition {
      operator = "always"
    }
  }
  edges {
    from_node_instance_slug = "drop-duplicated-data"
    to_node_instance_slug   = "add-dedup-key"
    condition {
      operator = "always"
    }
  }
  edges {
    from_node_instance_slug = "add-dedup-key"
    to_node_instance_slug   = "dedup-lookup"
    condition {
      operator = "always"
    }
  }
  edges {
    from_node_instance_slug = "dedup-lookup"
    to_node_instance_slug   = "route-flags"
    condition {
      operator = "always"
    }
  }

  # Remember the fingerprint — first sighting only. Writing on a duplicate would
  # be harmless but pointless; not writing keeps the KV table's contents exactly
  # "what we have shipped".
  edges {
    description             = "first sighting only — record the fingerprint so the next copy is suppressed"
    from_node_instance_slug = "route-flags"
    to_node_instance_slug   = "dedup-store"
    condition {
      operator = "nor"
      conditions {
        type_id = "key_exists"
        config {
          key = "monad.duplicate"
        }
      }
    }
  }

  # The shipping path. A duplicate matches neither this edge nor the one above,
  # so it is dropped here.
  edges {
    description             = "first sighting only — duplicates are dropped at this fork"
    from_node_instance_slug = "route-flags"
    to_node_instance_slug   = "strip-dedup-staging"
    condition {
      operator = "nor"
      conditions {
        type_id = "key_exists"
        config {
          key = "monad.duplicate"
        }
      }
    }
  }

  edges {
    description             = "hot — failures, root activity and interactive sign-ins go to the SIEM"
    from_node_instance_slug = "strip-dedup-staging"
    to_node_instance_slug   = "sink"
    condition {
      operator = "and"
      conditions {
        type_id = "key_exists"
        config {
          key = "monad.route.hot"
        }
      }
    }
  }
  edges {
    description             = "warm — anything that changed state; the mutation history"
    from_node_instance_slug = "strip-dedup-staging"
    to_node_instance_slug   = "warm-archive"
    condition {
      operator = "and"
      conditions {
        type_id = "key_exists"
        config {
          key = "monad.route.warm"
        }
      }
    }
  }
  edges {
    description             = "cold — read-only calls, the overwhelming majority of any real trail"
    from_node_instance_slug = "strip-dedup-staging"
    to_node_instance_slug   = "cold-archive"
    condition {
      operator = "and"
      conditions {
        type_id = "key_exists"
        config {
          key = "monad.route.cold"
        }
      }
    }
  }
}
