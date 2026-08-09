# Build a content-derived, order-insensitive fingerprint of the whole record.
#
# `canon` recursively sorts every object's keys, so two records with identical
# content but different key order serialize identically. The result goes into a
# staging field which the NEXT operation (a deterministic mask) replaces in
# place with an HMAC-SHA256 digest, and which is stripped again before egress —
# so the record that ships is byte-identical to the record that arrived.
#
# Why not hash directly: there is no hash primitive in the transform catalogue.
# `add_identifier` only makes UUIDs, and jq has no hash builtin. Pointing `mask`
# at "." computes the right whole-record digest and then silently discards it
# (sjson cannot write to @this), so the value must be staged in a real field
# first. Feature request: ENG-9543.
def canon:
  if type == "object" then
    to_entries | sort_by(.key) | map({key: .key, value: (.value | canon)}) | from_entries
  elif type == "array" then
    map(canon)
  else
    .
  end;

. + {_dedup_key: (canon | tostring)}
