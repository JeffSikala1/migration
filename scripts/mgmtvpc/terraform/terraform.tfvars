#ISE-AMAZON-LINUX-2023-GSA-HARDENED-24-12-07_03-30                                                              
bastionami = "ami-048dc48362c45610b"
bastion_s3 = "mgmt-cnxs-bastion-s3"
intnlbsubnetids = {
  az4 = "subnet-01b5aa20b85bb2876"
  az6 = "subnet-013df1d8815ef772b"
}
svcsubnetids = {
  az4 = "subnet-03dfb5138b5df60b6"
  az6 = "subnet-0253945b1e7a23642"
}                                                                                                               
dnsdomain = "mgmt.cnxs.vpcaas.fcs.gsa.gov"
dnszone = {
  ext = "Z02311902CPT7WD0A25OG"
  int = "Z0280533GOHHH3O7QRN6"
}
awsaccountid = "339713019047" 
region = "us-east-1"
