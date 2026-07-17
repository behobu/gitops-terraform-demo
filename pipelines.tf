resource "monad_pipeline" "cloudtrail" {
  name        = "Cloudtrail"
  description = "CloudTrail control-plane events, field-trimmed, to a demo sink."
  enabled     = true

  nodes {
    slug           = "cloudtrail-input"
    component_type = "input"
    component_id   = monad_input.org_cloudtrail_logs.id
  }
  nodes {
    slug           = "drop-low-value-fields"
    component_type = "transform"
    component_id   = monad_transform.drop_low_value_fields.id
  }
  nodes {
    slug           = "drop-duplicated-data"
    component_type = "transform"
    component_id   = monad_transform.drop_cloudtrail_duplicated_data.id
  }
  nodes {
    slug           = "sink"
    component_type = "output"
    component_id   = monad_output.sink.id
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
    to_node_instance_slug   = "drop-duplicated-data"
    condition {
      operator = "always"
    }
  }
  edges {
    from_node_instance_slug = "drop-duplicated-data"
    to_node_instance_slug   = "sink"
    condition {
      operator = "always"
    }
  }
}
