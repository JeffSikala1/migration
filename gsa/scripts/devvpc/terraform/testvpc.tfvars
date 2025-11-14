# See provider.tf and variable.tf

region = "us-east-1"
vpc_name = "fcs-conexus-test-T"
dnsdomain = "test.cnxs.vpcaas.fcs.gsa.gov"
#EKS #ami-01a45c98b6c69536b #ISE-AMZ-LINUX-EKS-v1.30-GSA-HARDENED-24-09-07_07-40 
#EC2 #ami-01854fb2a5e1318b2 #ISE-AMAZON-LINUX-2023-GSA-HARDENED-24-09-07_04-47

# ISE-AMAZON-LINUX-2-GSA-HARDENED-2024-07-13_08-25

#"ImageId": "ami-06b501b61aa9bdd40",
#"ImageLocation": "752281881774/ISE-AMAZON-LINUX-2023-GSA-HARDENED-25-04-05_05-23",

amiid = "ami-0d85b461809f7f3ef"
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


#Test vpc
createdevec2s = false
awsaccountid = "533267417102"
adminuser = {
  one = "madhav.kundala"
  two = "tyler.goll"
  three = "jeff.sikala"
}
adminrole = "AWS-075-GT-FullAdmin"
sshpubkeyname = "cloudshellkey"
eksclusterversion = "1.32"
eksinstancetype = ["r6a.xlarge"]
ec2instancetype = "r6a.xlarge"
ec2dbinstancetype = "r6a.xlarge"
karpenterpodinstancetype = ["t3a.medium"]
#Change in helminstall.sh too
eksclustername = "cnxstest-selfmanaged"
ciliuminstalled = true
tags = {                                                                                                                                   
  Environment = "test"                                                                                                                      
  Terraform   = "true" 
  Name = "selfmanaged-node-group-1"                                                                                                                    
}
sectoolregenv = "TEST"  
karpenterchartversion = "v1.3.2"
aws_efs_csi_driver_version = "v2.1.9-eksbuild.1"
dnszone = {
  ext = "Z00505773HV3PT787A0I4"
  int = "Z020947530VXZYDARJ220"
}
dnszoneinuse = "Z020947530VXZYDARJ220"

#services_ec2_cidr_blocks = [ "10.56.136.0/24", "10.56.137.0/24" ]
#intnlb_cidr_blocks = [ "10.56.143.0/28", "10.56.143.16/28" ]
#extnlb_cidr_blocks = [ "10.56.122.64/26", "10.56.122.192/26" ]

services_ec2_cidr_blocks = [ "10.56.137.0/24" ]
intnlb_cidr_blocks = [ "10.56.139.0/24" ]
extnlb_cidr_blocks = [ "10.56.122.192/26" ]

intnlbipaddress = { //Gap of 8
  #az1 = "10.56.143.8"
  az2 = "10.56.139.8"
}
extnlbipaddress = {
  #az1 = "10.56.122.72"
  az2 = "10.56.122.200"
}
dbadminipaddress = {
  #az1 = [ "10.56.142.8" ]
  az2 = [ "10.56.137.222" ]
}
svcjumpipaddress = {
  #az1 = [ "10.56.136.8" ]
  az2 = [ "10.56.137.8" ]
}
ec2devaipaddress = {
  #az1 = [ "10.56.128.81" ]
  az2 = [ "10.56.137.91" ]
}
ec2devbipaddress = {
  # az1 = [ "10.56.128.82" ]
  az2 = [ "10.56.137.92" ]
}

intnlbsubnetids = {
  # old az1 = "subnet-07c6ede3d1e6b556c"
  # old az2 = "subnet-0f3f50f2a76b02abd"
  # new az1 = "subnet-01f47e54e3d8932b9"
  az2 = "subnet-05f750c2367427e07"
}

nlbsubnetids = {
  az1 = "subnet-01f47e54e3d8932b9"
  az2 = "subnet-05f750c2367427e07"
}
  
#Modification requires modifying bash env vars in testvpc.bashenv
extnlbsubnetids = {
  #az1 = "subnet-074e820cdc70204e6"
  az2 = "subnet-078bbd47f22db0943"
}
dbsubnetids = {
  #az1 = "subnet-002feb5a26bb5f4a4"
  az2 = "subnet-0cf57c9a6f818dc45"
}
svcsubnetids = {
  az1 = "subnet-0a06aac14fc607a1a"
  az2 = "subnet-0819655e07d44db07"
}

ekslaunchtemplatezone = "us-east-1b"                                                                                    
bastion_s3 = "test-cnxs-bastion-s3"                                                                                      
truststore_s3 = "test-cnxs-ts-s3"

#uinlbdnsname = "a55e22f29daa2484b85a1530ab1273b0-43ce170191245f12.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "fcs-conexus-dev-D-intnlb-f0e3b5064c8bb734.elb.us-east-1.amazonaws.com"
#uinlbdnsname = "ad9c4a666c5074462be703e870c99689-72fe2fab7cf5cb0a.elb.us-east-1.amazonaws.com"
uinlbdnsname = "a3db85d403aac43e780a6ce28ec47169-aab2b4aa772285de.elb.us-east-1.amazonaws.com"
acmerecord = ["kj6haBaLVxs-lGJNPCl8QhsLG8tww-VivxrGAixnw7Q"]

sftpusers = ["ATT", "BTFederal", "Lumen", "CoreTech", "GraniteTelcom", "HarrisCorp", "ManhattanTelco", "MicroTech", "Verizon", "DOD_DISA_1", "NHC", "s_conexus_testsftp"]

db_cluster_name     = "test-aurora-cluster"
master_username     = "postgres"
secret_name         = "test-db-credential1"
master_password     = "Aurora_Postgres"
