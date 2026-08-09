# Turn the dedup lookup result and the record's security value into ROUTING FLAGS.
#
# ---------------------------------------------------------------------------
# Why flags and not values
#
# Edges here can only test KEY PRESENCE, not equality. The Terraform provider
# serializes every condition leaf as {key, value: [...], rate}, i.e. `value` is
# always a JSON array. The API's `equals` rule stores an array-typed value via
# its raw JSON text, so a configured `["hot"]` is compared against the record's
# "hot" and never matches — the edge silently routes nothing rather than
# erroring. `equals_any` reads `values` (plural), which the provider never
# sends. `key_exists` reads only `key`, so it is the one leaf that survives the
# round trip.
#
# So: this transform sets exactly one `monad.route.*` key per record and the
# edges test for its presence. `monad.retention_tier` carries the same decision
# as a readable string for humans sampling the node — it is display only.
# Delete the flags and route on retention_tier once the provider can express
# equality.
# ---------------------------------------------------------------------------
#
# Tiering policy — the cost story.
#
# Normalization makes each record BIGGER, so the saving cannot come from record
# size. It comes from how little of the volume reaches the expensive tier.
#
#   hot   what you would page someone about: failed calls, root activity, and
#         interactive sign-ins. Goes to the SIEM.
#   warm  everything that CHANGED something — the mutation history you keep for
#         a year and query occasionally.
#   cold  read-only calls. In a real trail this is the overwhelming majority
#         (98 of 101 records in the capture this demo was modelled on) and it is
#         almost never queried. Cheap archive.
#
# The important subtlety: `sts:AssumeRole` is categorized as authentication, and
# in a real account it is enormous — every pod, every service, every CI job
# assumes a role constantly. Sending all authentication to the hot tier would
# put the single highest-volume event type in the most expensive place and
# invert the whole argument. So "sign-in" here means an INTERACTIVE sign-in
# (console or Identity Center), explicitly not STS.

def is_failure: (.event.outcome? // "") == "failure";
def is_root:    ((.aws.cloudtrail.user_identity.type? // "") == "Root");
def is_signin:
  (((.event.category? // []) | index("authentication")) != null)
  and ((.event.provider? // "") != "sts.amazonaws.com");
# Only an EXPLICIT read_only:true is archived. A record that somehow lacks the
# field lands warm rather than cold — never silently archive something we could
# not classify.
def is_read:    (.aws.cloudtrail.read_only? == true);

(if is_failure or is_root or is_signin then "hot"
 elif is_read then "cold"
 else "warm" end) as $tier
| .monad.retention_tier = $tier
| .monad.route[$tier] = true
# A KV hit means this exact record has been seen before. omit_metadata is false
# on the enrichment, so a hit is code "success" and a miss is "no_match" — an
# unambiguous test. Presence of monad.duplicate is what the edges suppress on.
| if (._dedup_seen.code? // "") == "success" then .monad.duplicate = true else . end
