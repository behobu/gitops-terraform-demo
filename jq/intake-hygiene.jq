(((.message // "") | tostring) | gsub("^[[:space:]]+|[[:space:]]+$"; "")) as $m | select($m != "" and $m != "-- MARK --")
