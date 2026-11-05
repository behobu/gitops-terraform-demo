resource "monad_enrichment" "geolocus_src" {
  name        = "Geolocus – src"
  description = "Geolocates the source IP (src) into enrichment.geo.src."
  type        = "geolocus"
  config {
    settings = {
      ip_address_path  = "src"
      destination_path = "enrichment.geo.src"
    }
  }
}

resource "monad_enrichment" "geolocus_dest" {
  name        = "Geolocus – dest"
  description = "Geolocates the destination IP (dest) into enrichment.geo.dest."
  type        = "geolocus"
  config {
    settings = {
      ip_address_path  = "dest"
      destination_path = "enrichment.geo.dest"
    }
  }
}
