# Adopt the syslog demo that already runs in syslog-9001 instead of creating a
# second copy. On the first apply against a fresh state these import every
# component by id; once they are in state, Terraform treats them as no-ops.
#
# Retargeting to a different org: delete this file (Terraform then creates
# everything from scratch) or replace the ids with that org's. See the README.

import {
  to = monad_secret.http_input_api_key
  id = "7135f091-8fe7-4145-b98f-b105b1fda887"
}

import {
  to = monad_input.syslog_tls
  id = "c906030f-c73c-4aa1-ab4f-fe590d73c52e"
}

import {
  to = monad_input.http_in_firewall
  id = "48318eab-606c-401b-8c7a-e65f04e3b045"
}

import {
  to = monad_input.http_in_linux_auth
  id = "9482d844-0055-408f-ba55-428b9692259e"
}

import {
  to = monad_input.http_in_cef
  id = "f07e3145-9ae8-4d52-affe-e00f65f2bbd6"
}

import {
  to = monad_output.http_out_firewall
  id = "dec2fdae-c766-44a8-87e2-7d437e9fde04"
}

import {
  to = monad_output.http_out_linux_auth
  id = "a4cb627a-4d8a-495a-b2d6-e2a44a76d50c"
}

import {
  to = monad_output.http_out_cef
  id = "8718d627-5f7f-4b09-8f89-f8c99aa144ea"
}

import {
  to = monad_output.splunk_netfw
  id = "97c36d26-d6d6-4b68-aca5-f975d1041587"
}

import {
  to = monad_output.splunk_os_auth
  id = "5d81f1ab-a2c0-4071-a67f-d472a9fbcb48"
}

import {
  to = monad_output.splunk_ids
  id = "4e2fd906-11e5-4a73-8e0f-bff73f0b1282"
}

import {
  to = monad_output.warm_databricks
  id = "84fbc9a1-067c-4b9a-ac4b-6fc7292205f0"
}

import {
  to = monad_output.cold_s3_archive
  id = "5d10c38c-c24e-42a4-a6ea-dd57e43d2310"
}

import {
  to = monad_enrichment.geolocus_src
  id = "d2e180e5-89d9-4f36-a03b-ae0d00985dc2"
}

import {
  to = monad_enrichment.geolocus_dest
  id = "ab135e00-6591-4ad6-abe5-08d94ce180b7"
}

import {
  to = monad_transform.intake_parse_classify
  id = "b3d9a1bf-844c-4c06-8a7a-9d971a3b3a30"
}

import {
  to = monad_transform.intake_hygiene
  id = "fe5ec7f8-0516-4fb3-97b9-d5fe85f01785"
}

import {
  to = monad_transform.firewall_parse
  id = "82ce0326-cc9a-4816-be4d-5fc22df47c13"
}

import {
  to = monad_transform.firewall_risk_tier
  id = "f2e56d2f-dc09-46c2-a49a-9fa963707780"
}

import {
  to = monad_transform.linux_auth_parse
  id = "d5e03b7f-3394-4744-883c-94a525df907a"
}

import {
  to = monad_transform.linux_auth_risk_tier
  id = "30f79f08-79e6-4c75-b5b2-f64ef7a0a258"
}

import {
  to = monad_transform.cef_parse
  id = "f793100c-4f93-443b-9ff0-1140ce996261"
}

import {
  to = monad_transform.cef_risk_tier
  id = "154f5897-8dff-4e3a-9b11-3babb19d17e7"
}

import {
  to = monad_pipeline.intake
  id = "e58b1c96-5054-4986-8f3d-a1cecf2ecf18"
}

import {
  to = monad_pipeline.firewall
  id = "ab959965-576c-427d-baa4-9cba0b6012ea"
}

import {
  to = monad_pipeline.linux_auth
  id = "6618868b-77a7-41d2-82f6-7b4524f030e2"
}

import {
  to = monad_pipeline.cef
  id = "68eb8867-e9d5-4806-87ac-dd68f9bce101"
}
