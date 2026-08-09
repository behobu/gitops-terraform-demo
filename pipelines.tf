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
# EDGE CONDITIONS ARE PRESENCE TESTS, NOT EQUALITY TESTS. The provider
# serializes every leaf as {key, value: [...], rate}, so `value` is always an
# array; the API's `equals` rule compares that array's raw JSON text against the
# record's scalar and never matches, and `equals_any` reads `values` (plural),
# which the provider never sends. Neither errors — the edge just silently routes
# nothing. `key_exists` reads only `key`, so it round-trips correctly, and
# "Route Flags" exists to turn every routing decision into a key that is either
# present or absent. See jq/route-flags.jq.
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
    component_id   = monad_output.cold_archive.id
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
    description             = "hot — failures, authentication, mutations and root activity go to the SIEM"
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
    description             = "warm — everything that is neither high-value nor pure service chatter"
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
    description             = "cold — AWS-service read chatter, the highest-volume lowest-value traffic"
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
