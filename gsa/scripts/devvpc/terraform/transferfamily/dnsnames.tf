# Points to OutUINLB
resource "aws_route53_record" "uicnamerecord" {
  zone_id = var.dnszoneinuse # Replace with your zone ID
  name    = "ui.${var.dnsdomain}" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "CNAME"
  ttl     = "300"
  records = [aws_lb.outuinlb.dns_name]
}
# Points to OutNLB (API)
resource "aws_route53_record" "apicnamerecord" {
  zone_id = var.dnszoneinuse 
  name    = "api.${var.dnsdomain}" 
  type    = "CNAME"
  ttl     = "300"
  records = [aws_lb.outnlb.dns_name]
}
# Points to OutUINLB
resource "aws_route53_record" "sftpcnamerecord" {
  zone_id = var.dnszoneinuse 
  name    = "sftp.${var.dnsdomain}" 
  type    = "CNAME"
  ttl     = "300"
  records = [aws_lb.outuinlb.dns_name]
}
