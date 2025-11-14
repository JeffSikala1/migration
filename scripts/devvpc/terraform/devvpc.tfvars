# See provider.tf and variable.tf

region    = "us-east-1"
vpc_name  = "sandbox-vpc"
vpc_id    = "vpc-0e46233ef13219829"
dnsdomain = "conexus-dev-sandbox.org"
#EKS #ami-01a45c98b6c69536b #ISE-AMZ-LINUX-EKS-v1.30-GSA-HARDENED-24-09-07_07-40 
#EC2 #ami-01854fb2a5e1318b2 #ISE-AMAZON-LINUX-2023-GSA-HARDENED-24-09-07_04-47

# ISE-AMAZON-LINUX-2-GSA-HARDENED-2024-07-13_08-25
#amiid = "ami-01c1e22f7519bc7ab"
# DevEC2s
# ISE-AMAZON-LINUX-2023-GSA-HARDENED-24-12-28_03-33
amiid = "ami-0ebfd941bbafe70c6" # AMZ-LINUX


# ISE-AMZ-LINUX-EKS-v1.30-GSA-HARDENED-24-09-07_07-40 
eksamiid = "ami-0ebfd941bbafe70c6" # AMZ-LINUX
# ISE-AMZ-LINUX-EKS-v1.30-GSA-HARDENED-24-09-04_12-20
eksamiid2 = "ami-0ebfd941bbafe70c6" # AMZ-LINUX
# amazon/amazon-eks-node-1.30-v20240904
eksamiidal2 = "ami-0ebfd941bbafe70c6" # AMZ-LINUX

#ISE-AMZ-LINUX-EKS-v1.29-IPV6-GSA-HARDENED-24-08-01_10-19 
#eksamiid = "ami-02a84dccec7ea586d"
# AWS linux 2023
eksamiid1 = "ami-0ebfd941bbafe70c6" # AMZ-LINUX

#Dev vpc
awsaccountid = "200008295591"
adminuser = {
  one   = "madhavdkundala"
  two   = "tylerlgoll"
  three = "shahbazqureshi"
  four  = "jeffsikala"
}
adminrole = "AWS-075-GD-FullAdmin"

eksclusterversion        = "1.30"
eksinstancetype          = ["t3a.xlarge"]
karpenterpodinstancetype = ["t3a.medium"]
#Change in helminstall.sh too
eksclustername = "cnxsdev-karpenter"
tags = {
  Environment = "dev"
  Terraform   = "true"
}

#karpenterchartversion = "0.37.3" #stable version
karpenterchartversion = "1.0.0"
dnszone = {
  ext = "Z03201631KQBE9RN4411F"
  int = "Z03201631KQBE9RN4411F"
}
services_ec2_cidr_blocks = ["10.20.30.0/24", "10.20.50.0/24", "10.20.130.0/24"]
intnlb_cidr_blocks       = ["10.20.150.0/28", "10.20.150.16/28", "10.20.150.32/28"]
extnlb_cidr_blocks       = ["10.20.40.0/24", "10.20.140.0/24", "10.20.140.32/28"]
intnlbipaddress = { //Gap of 8
  az1 = "10.20.150.8"
  az4 = "10.20.150.24"
  az6 = "10.20.150.40"
}
extnlbipaddress = {
  az1 = "10.20.40.8"
  az4 = "10.20.140.8"
  az6 = "10.20.140.8"
}
dbjumpipaddress = {
  az1 = ["10.20.130.8"]
  //az4 = "10.20.130.24"
  //az6 = "10.20.130.40"
}
svcjumpipaddress = {
  az1 = ["10.20.30.8"]
  //az4 = "10.20.50.8"
  //az6 = "10.20.130.8"
}
ec2devaipaddress = {
  az1 = ["10.20.30.81"]
}
intnlbsubnetids = {
  az1 = "subnet-029741639e14ffdbe"
  az4 = "subnet-0b56bfc5090c78bd1"
  az6 = "subnet-0c460d7233f516c86"
}


#Modification requires modifying bash env vars in devvpc.bashenv
extnlbsubnetids = {
  az1 = "subnet-029741639e14ffdbe"
  az4 = "subnet-0b56bfc5090c78bd1"
  az6 = "subnet-0c460d7233f516c86"
}
dbsubnetids = {
  az1 = "subnet-0f9d9b1f43309d25d"
  az4 = "subnet-044dcf38bd5d7d3a7"
  az6 = "subnet-0923ff508c17e242f"
}
svcsubnetids = {
  az1 = "subnet-0f9d9b1f43309d25d"
  az4 = "subnet-044dcf38bd5d7d3a7"
  az6 = "subnet-0923ff508c17e242f"
}

bastion_s3 = "sandbox-bastion-data"

#uinlbdnsname = "a55e22f29daa2484b85a1530ab1273b0-43ce170191245f12.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "fcs-conexus-dev-D-intnlb-f0e3b5064c8bb734.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "ad9c4a666c5074462be703e870c99689-72fe2fab7cf5cb0a.elb.us-east-1.amazonaws.com"
uinlbdnsname = "bastion-lt-lb-40ef98755a5ec4d7.elb.us-east-1.amazonaws.com"
#acmerecord = ["wjCNYJgICIow3GSvh8oXHpBFDsihpWM2GmDv7za6-N8"]
acm_certificate_arn = "arn:aws:acm:us-east-1:200008295591:certificate/dc3010c3-a814-4717-93df-ae0261f4d234"

sftpusers = ["ATT", "BTFederal", "Lumen", "CoreTech", "GraniteTelcom", "HarrisCorp", "ManhattanTelco", "MicroTech", "Verizon", "DOD_DISA_1", "NHC", "s_conexus_testsftp"]

db_cluster_name = "dev-aurora-cluster"
master_username = "postgres"
secret_name     = "dev-db-credential"
master_password = "Aurora_Postgres"

bamboo_admin_username = "admin"
bamboo_admin_password = "changeme123"
bamboo_admin_email    = "jeff.sikala@usda.gov"