resource "aws_instance" "cnxsmgmtbuildagents" {
 //ami = "ami-07caf09b362be10b8"
 ami = "ami-034fab89e22e42287"
 instance_type = "t3.2xlarge"
 key_name = aws_key_pair.deployer.key_name

  root_block_device {
    volume_size = 500 # in GB
    volume_type = "gp3"
    encrypted   = true
    delete_on_termination = false
  }

 network_interface {
 network_interface_id = aws_network_interface.cnxsmgmtbuildagentsinterfaceaz4.id
 device_index = 0
 }

 credit_specification {
 cpu_credits = "unlimited"
 }

 //vpc_security_group_ids = [
 // aws_security_group.nginxbitbucket.id,
 //]

 //Not used when network_interface is in use
 //subnet_id = aws_subnet.privateservicesaz4.id

 //iam_instance_profile ="SSMInstanceProfile"
 //aws_iam_instance_profile.ssminstanceprofile.name
 iam_instance_profile = aws_iam_instance_profile.mgmt-resources-iam-profile.name
 user_data = base64encode(templatefile("./userdata_buildagents.sh", {}))
 tags = {
 Name = "cnxsmgmtbuildagents"
 }

}
