# See provider.tf and variable.tf

region    = "us-east-1"
vpc_name  = "fcs-conexus-test-T"
dnsdomain = "test.cnxs.vpcaas.fcs.gsa.gov"
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

#Test vpc
awsaccountid = "533267417102"
adminuser = {
  one   = "madhavdkundala"
  two   = "tylerlgoll"
  three = "shahbazqureshi"
}
adminrole  = "AWS-075-GT-FullAdmin"
bastion_s3 = "test-cnxs-bastion-s3"

eksclusterversion        = "1.30"
eksinstancetype          = ["t3a.xlarge"]
karpenterpodinstancetype = ["t3a.medium"]
#Change in helminstall.sh too
eksclustername = "cnxstest-karpenter"
tags = {
  Environment = "test"
  Terraform   = "true"
}

#karpenterchartversion = "0.37.3" #stable version
karpenterchartversion = "1.0.0"
dnszone = {
  ext = "Z00505773HV3PT787A0I4"
  int = "Z020947530VXZYDARJ220"
}
services_ec2_cidr_blocks = ["10.56.136.0/24", "10.56.137.0/24"]
intnlb_cidr_blocks       = ["10.56.143.0/28", "10.56.143.16/28"]
extnlb_cidr_blocks       = ["10.56.122.64/26", "10.56.122.192/26"]
intnlbipaddress = { //Gap of 8
  az4 = "10.56.143.8"
  az6 = "10.56.143.24"
}
extnlbipaddress = {
  az4 = "10.56.122.72"
  az6 = "10.56.122.200"
}
dbjumpipaddress = {
  az4 = ["10.56.142.8"]
  az6 = ["10.56.142.24"]
}
svcjumpipaddress = {
  az4 = ["10.56.136.8"]
  az6 = ["10.56.137.8"]
}
intnlbsubnetids = {
  az4 = "subnet-07c6ede3d1e6b556c"
  az6 = "subnet-0f3f50f2a76b02abd"
}


#Modification requires modifying bash env vars in testvpc.bashenv
extnlbsubnetids = {
  az4 = "subnet-074e820cdc70204e6"
  az6 = "subnet-078bbd47f22db0943"
}
dbsubnetids = {
  az4 = "subnet-002feb5a26bb5f4a4"
  az6 = "subnet-0cf57c9a6f818dc45"
}
svcsubnetids = {
  az4 = "subnet-0a06aac14fc607a1a"
  az6 = "subnet-0819655e07d44db07"
}


#uinlbdnsname = "a55e22f29daa2484b85a1530ab1273b0-43ce170191245f12.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "fcs-conexus-dev-D-intnlb-f0e3b5064c8bb734.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "ad9c4a666c5074462be703e870c99689-72fe2fab7cf5cb0a.elb.us-east-1.amazonaws.com"
uinlbdnsname = "a3db85d403aac43e780a6ce28ec47169-aab2b4aa772285de.elb.us-east-1.amazonaws.com"
acmerecord   = ["oMmbNvLHY0Tkt5_uupNruW-_6wxQBmqTTo9-U5XH0Jo"]

sftpusers = ["ATT", "BTFederal", "Lumen", "CoreTech", "GraniteTelcom", "HarrisCorp", "ManhattanTelco", "MicroTech", "Verizon"]

db_cluster_name = "test-aurora-cluster"
master_username = "postgres"
secret_name     = "test-db-credential1"
master_password = "Aurora_Postgres"
