resource "monad_output" "sink" {
  name        = "Elasticsearch"
  description = "Demonstration sink. dev-null discards all records — intentional for this demo. Swap type/settings for a real destination when needed."
  type        = "dev-null"
}
