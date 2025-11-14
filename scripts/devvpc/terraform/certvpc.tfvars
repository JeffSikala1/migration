# See provider.tf and variable.tf

region    = "us-east-1"
vpc_name  = "fcs-conexus-preprod-PP"
dnsdomain = "preprod.cnxs.vpcaas.fcs.gsa.gov"
#EKS #ami-01a45c98b6c69536b #ISE-AMZ-LINUX-EKS-v1.30-GSA-HARDENED-24-09-07_07-40 
#EC2 #ami-01854fb2a5e1318b2 #ISE-AMAZON-LINUX-2023-GSA-HARDENED-24-09-07_04-47

# ISE-AMAZON-LINUX-2-GSA-HARDENED-2024-07-13_08-25
amiid = "ami-01c1e22f7519bc7ab"

# ISE-AMZ-LINUX-EKS-v1.30-GSA-HARDENED-24-09-07_07-40
eksamiid = "ami-01a45c98b6c69536b"
# ISE-AMZ-LINUX-EKS-v1.30-GSA-HARDENED-24-09-04_12-20
eksamiid2 = "ami-084944fbb73983a07"
# amazon/amazon-eks-node-1.30-v20240904
eksamiidal2 = "ami-03413b57906e5c8b2"

#ISE-AMZ-LINUX-EKS-v1.29-IPV6-GSA-HARDENED-24-08-01_10-19 
#eksamiid = "ami-02a84dccec7ea586d"
# AWS linux 2023
eksamiid1 = "ami-0182f373e66f89c85"
# ISE-Amazon-linux-2023-gsa-hardened-2410-31_11-09
bastionami = "ami-01e7127d7972bcda9"

#Cert vpc
awsaccountid = "339712815045"
#Federated ID - AWS-075-GPP-FullAdmin/<gsauserid>
adminuser = {
  one   = "madhavdkundala"
  two   = "tylerlgoll"
  three = "shahbazqureshi"
}
adminrole = "AWS-075-GPP-FullAdmin"

eksclusterversion        = "1.30"
eksinstancetype          = ["t3a.xlarge"]
karpenterpodinstancetype = ["t3a.medium"]
#Change in helminstall.sh too
eksclustername = "cnxscert-karpenter"
tags = {
  Environment = "cert"
  Terraform   = "true"
}

#karpenterchartversion = "0.37.3" #stable version
karpenterchartversion = "1.0.0"
dnszone = {
  ext = "Z1017540J5K8HLEN9PD0"
  int = "Z01980402HOSN5R5O9YK6"
}

services_ec2_cidr_blocks = ["10.56.160.0/24", "10.56.161.0/24"]
intnlb_cidr_blocks       = ["10.56.167.0/28", "10.56.167.16/28"]
extnlb_cidr_blocks       = ["10.56.127.64/26", "10.56.127.192/26"]

intnlbipaddress = { //Gap of 8
  az4 = "10.56.167.8"
  az6 = "10.56.167.24"
}
extnlbipaddress = {
  az4 = "10.56.127.72"
  az6 = "10.56.127.200"
}
dbjumpipaddress = {
  az4 = ["10.56.166.8"]
  az6 = ["10.56.166.24"]
}
svcjumpipaddress = {
  az4 = ["10.56.160.8"]
  az6 = ["10.56.161.8"]
}
intnlbsubnetids = {
  az4 = "subnet-039433d58741a773a"
  az6 = "subnet-0d5a533767c82386f"
}


#Modification requires modifying bash env vars in certvpc.bashenv
extnlbsubnetids = {
  az4 = "subnet-0381a1b4e9306df33"
  az6 = "subnet-05226597e8eec8dc1"
}
dbsubnetids = {
  az4 = "subnet-0579d2dfe39f259d3"
  az6 = "subnet-0851ef176e424db8a"
}
svcsubnetids = {
  az4 = "subnet-00f248ed45c61b767"
  az6 = "subnet-08d45a526a4b931c8"
}

bastion_s3 = "cert-cnxs-bastion-s3"
#uinlbdnsname = "a55e22f29daa2484b85a1530ab1273b0-43ce170191245f12.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "fcs-conexus-dev-D-intnlb-f0e3b5064c8bb734.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "ad9c4a666c5074462be703e870c99689-72fe2fab7cf5cb0a.elb.us-east-1.amazonaws.com"
uinlbdnsname = "a0067c8020e1f49029c1fd0b62da150d-e6fb256d05b0d84a.elb.us-east-1.amazonaws.com"
acmerecord   = ["oMmbNvLHY0Tkt5_uupNruW-_6wxQBmqTTo9-U5XH0Jo"]

sftpusers = ["ATT", "BTFederal", "Lumen", "CoreTech", "GraniteTelcom", "HarrisCorp", "ManhattanTelco", "MicroTech", "Verizon"]

db_cluster_name = "cert-aurora-cluster"
master_username = "postgres"
secret_name     = "cert-db-credential"
master_password = "Aurora_Postgres"

