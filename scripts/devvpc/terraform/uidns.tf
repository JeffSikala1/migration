resource "aws_route53_record" "uicnamerecord" {
  zone_id = var.dnszone.int       # Replace with your zone ID
  name    = "ui.${var.dnsdomain}" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "CNAME"
  ttl     = "300"
  records = ["${var.uinlbdnsname}"]
}

resource "aws_route53_record" "micnamerecord" {
  zone_id = var.dnszone.int       # Replace with your zone ID
  name    = "mi.${var.dnsdomain}" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "CNAME"
  ttl     = "300"
  records = ["${var.uinlbdnsname}"]
}

