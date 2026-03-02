resource "aws_route53_record" "acmetxtrecord" {
  zone_id = var.dnszone.ext # Replace with your zone ID
  name    = "_acme-challenge" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "TXT"
  ttl     = "300"
  records = var.acmerecord
  allow_overwrite = true

  lifecycle {
    ignore_changes = all
  }

}
