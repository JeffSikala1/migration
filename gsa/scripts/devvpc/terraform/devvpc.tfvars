# See provider.tf and variable.tf

region = "us-east-1"
vpc_name = "fcs-conexus-dev-D"
dnsdomain = "dev.cnxs.vpcaas.fcs.gsa.gov"
#EKS #ami-01a45c98b6c69536b #ISE-AMZ-LINUX-EKS-v1.30-GSA-HARDENED-24-09-07_07-40 
#EC2 #ami-01854fb2a5e1318b2 #ISE-AMAZON-LINUX-2023-GSA-HARDENED-24-09-07_04-47

# ISE-AMAZON-LINUX-2-GSA-HARDENED-2024-07-13_08-25
#amiid = "ami-01c1e22f7519bc7ab"
# DevEC2s
# ISE-AMAZON-LINUX-2023-GSA-HARDENED-24-12-28_03-33
#amiid = "ami-0577643dc542a74fc"
amiid = "ami-0d85b461809f7f3ef"

#"ImageId": "ami-0d85b461809f7f3ef",
#"ImageLocation": "752281881774/ISE-AMAZON-LINUX-2023-GSA-HARDENED-25-05-10_04-22",

dbadminamiid = "ami-0d85b461809f7f3ef"


#"ImageLocation": "752281881774/ISE-AMAZON-LINUX-2023-EKS-v1.32-GSA-HARDENED-25-06-21_07-55"
eksamiid = "ami-00f4f731076a7c8b2"

# ISE-AMZ-LINUX-EKS-v1.30-GSA-HARDENED-24-09-04_12-20
eksamiid2 = "ami-084944fbb73983a07"
# amazon/amazon-eks-node-1.30-v20240904
eksamiidal2 = "ami-03413b57906e5c8b2"

#ISE-AMZ-LINUX-EKS-v1.29-IPV6-GSA-HARDENED-24-08-01_10-19 
#eksamiid = "ami-02a84dccec7ea586d"
# AWS linux 2023
eksamiid1 = "ami-0182f373e66f89c85"

#Dev vpc
createdevec2s = false
awsaccountid = "471112718870"
adminuser = {
  one = "madhav.kundala"
  two = "tyler.goll"
  three = "jeff.sikala"
}
adminrole = "AWS-075-GD-FullAdmin"
#sshpubkeyname = "APKAW3MEBTILN3EPHWHC"
sshpubkeyname = "cloudshellkey"
eksclusterversion = "1.32"
eksinstancetype = ["r6a.xlarge"] # 4 32
ec2instancetype = "r6a.xlarge"
#ec2smalltype = ["m7a.medium"]  # 1 4
karpenterpodinstancetype = ["r6a.large"]
#Change in helminstall.sh too
eksclustername = "cnxsdev-selfmanaged"
ciliuminstalled = true
tags = {
  Environment = "dev"
  Terraform   = "true"
  Name = "selfmanaged-node-group-1"
}  
sectoolregenv = "DEV"
karpenterchartversion = "v1.3.2"
aws_efs_csi_driver_version = "v2.1.9-eksbuild.1"
databaseaz2mtid = "fsmt-0318dced79d72eaaf"
dnszone = {
  ext = "Z00469081L8WP3FVPM748"
  int = "Z0302955A48RKPB320IR"
}
dnszoneinuse = "Z0302955A48RKPB320IR"

#services_ec2_cidr_blocks = [ "10.56.128.0/24", "10.56.129.0/24", "10.56.130.0/24" ]
#intnlb_cidr_blocks = [ "10.56.135.0/28", "10.56.135.16/28", "10.56.135.32/28" ]
#extnlb_cidr_blocks = [ "10.56.57.0/24", "10.56.59.0/24", "10.56.61.0/24" ]
services_ec2_cidr_blocks = [ "10.56.128.0/24" ]
# Old intnlb_cidr_blocks = [ "10.56.135.32/28" ]
intnlb_cidr_blocks = [ "10.56.131.0/24" ]
extnlb_cidr_blocks = [ "10.56.61.0/24" ]

#az2 is fcs az1; az1 is az6 https://conexus-confluence.edc.ds1.usda.gov/spaces/NSFS/pages/220299302/FCS+AZs
intnlbipaddress = { //Gap of 8
  #  az1 = "10.56.135.8"
  az2 = "10.56.131.8"
  #  az4 = "10.56.135.24"
  #  az6 = "10.56.135.40"
}
extnlbipaddress = {
  #  az1 = "10.56.57.8"
  az2 = "10.56.57.8"
  #  az4 = "10.56.59.8"
  #  az6 = "10.56.61.8"
}
dbadminipaddress = {
  # az1 = [ "10.56.134.8" ]
  az2 = [ "10.56.128.222" ]
  //az4 = "10.56.134.24"
  //az6 = "10.56.134.40"
}
svcjumpipaddress = {
  # az1 = [ "10.56.128.8" ]
  az2 = [ "10.56.128.8" ]
  //az4 = "10.56.129.8"
  //az6 = "10.56.130.8"
}
ec2devaipaddress = {
  #az1 = [ "10.56.128.81" ]
  az2 = [ "10.56.128.81" ]
}
ec2devbipaddress = {
  # az1 = [ "10.56.128.82" ]
  az2 = [ "10.56.128.82" ]
}
intnlbsubnetids = {
  #  az1 = "subnet-0e93a80868c3e7a21"
  # old az2 = "subnet-0e93a80868c3e7a21"
  az2 = "subnet-0826111a038991700"
  #  az4 = "subnet-0f5cabc8b2a6cacb8"
  # az6 = "subnet-03501970d42d8387f"
}
nlbsubnetids = {
  az1 = "subnet-0fa28a398cb662a71"
  az2 = "subnet-0826111a038991700"
}
#Modification requires modifying bash env vars in devvpc.bashenv
extnlbsubnetids = {
  #  az1 = "subnet-0f267fd68c465319d"
  az2 = "subnet-0f267fd68c465319d"
  #  az4 = "subnet-072236a93f4d27452"
  #  az6 = "subnet-099e6c52fefcea1d9"
}
dbsubnetids = {
  #  az1 = "subnet-062971903a7d3b4d9"
  az2 = "subnet-062971903a7d3b4d9"
  #  az4 = "subnet-0ce78d8c595576a23"
  #  az6 = "subnet-0b8bf5be1df252c20"
}
#Used for eks cluster, enable all azs and then enable single az in node group
svcsubnetids = {
  #az1 = "subnet-03b2ad70c865c117e"
  #az6 = "subnet-035e85a81435edac3"
  
  az1 = "subnet-035e85a81435edac3"
  az2 = "subnet-03b2ad70c865c117e"
  az4 = "subnet-0fddbea72555116f0"

}
truststore_s3 = "dev-cnxs-ts-s3"
ekslaunchtemplatezone = "us-east-1b"
bastion_s3 = "dev-cnxs-bastion-s3"

#uinlbdnsname = "a55e22f29daa2484b85a1530ab1273b0-43ce170191245f12.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "fcs-conexus-dev-D-intnlb-f0e3b5064c8bb734.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "ad9c4a666c5074462be703e870c99689-72fe2fab7cf5cb0a.elb.us-east-1.amazonaws.com"
uinlbdnsname = "affc69d94979e4b2cbfe2fa4c072d083-581a7ced210421a2.elb.us-east-1.amazonaws.com"
acmerecord = ["wjCNYJgICIow3GSvh8oXHpBFDsihpWM2GmDv7za6-N8"]

sftpusers = ["ATT", "BTFederal", "Lumen", "CoreTech", "GraniteTelcom", "HarrisCorp", "ManhattanTelco", "MicroTech", "Verizon","DOD_DISA_1","NHC","s_conexus_testsftp"]

db_cluster_name     = "dev-aurora-cluster"
master_username     = "postgres"
secret_name         = "dev-db-credential"
master_password     = "Aurora_Postgres"
