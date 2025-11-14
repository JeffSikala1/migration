# GSA ISE EC2 Instance Module for AWS

This Terraform module creates and configures EC2 instances with automated Sectools registration. It supports both Linux and Windows operating systems and ensures that the appropriate Sectools registration script is executed during instance startup. The module is designed to be used with [GSA Hardened AMI Module](https://github.com/GSA/odp-tf-gsa-hardened-ami) to ensure compliance and security. It is also 

## Features
- Automatically deploy EC2 instances with the specified AMI and instance type.
- Configures and runs Sectools registration scripts for both Linux and Windows.
- Supports GSA Hardened Images from the GSA Hardened AMI Repository.
- Automatically applies instance-specific configurations for Sectools registration (IAM role, external ID, environment, etc.).
- Flexible tagging for compliance and organizational tracking.

## Prerequisites

- AWS IAM Role with appropriate permissions for creating EC2 instances and associating IAM instance profiles.
- Terraform >= 1.0
- AWS provider version ~> 4.0
- Must be used with [GSA Hardened AMI Module](https://github.com/GSA/odp-tf-gsa-hardened-ami)

## Usage

### Example for Linux Instance (Amazon Linux 2023)

```hcl
#############################################
# Must be used with GSA Hardened AMI module #
#############################################

module "amazon_linux_2023_gsa_hardened" {
  source = "github.com/GSA/odp-tf-modules//modules/aws-gsa-hardened-amis/Amazon-Linux-2023?ref=v1.0.0"
}

##################################################
# Recommended to use SSM Instance Profile Module # (Optional but highly recommended)
##################################################

module "ssm_instance_profile" {
  source = source = "github.com/GSA/odp-tf-modules//modules/aws-ssm-instance-profile?ref=v1.0.0"

  assume_role_arn       = "arn:aws:iam::<aws_account_id>:role/ise-sectool-credentials-reader"
  role_name             = "SSMRole" # <-- Replace with your role name of your choice
  instance_profile_name = "SSMInstanceProfile" # <-- Replace with your instance profile name
  external_id           = "xxx-ddd-gggg-fff" # <-- Replace with your external ID

  # Tags are optional, but highly recommended. Add any additional tags that you want to apply to your instance profile.
  tags = {
    Name        = "SSMInstanceProfile"
    Environment = "DEV"
    Project     = "SECOPS"
  }
}

###############################
# GSA ISE EC2 Instance Module #
###############################

module "ec2_instance" {
  source                  = "github.com/GSA/odp-tf-modules//modules/aws-ec2-instance?ref=v1.0.0"
  ami                     = module.amazon_linux_2023_gsa_hardened.ami_id  # Linux AMI from GSA Hardened Images
  instance_type           = "t3.micro"
  subnet_id               = "subnet-abc123"
  vpc_security_group_ids  = ["sg-abc123"]
  key_name                = "my-key"
  iam_instance_profile    = "my-instance-profile"

  # Sectools configuration
  sec_tools_iam_role_arn  = "arn:aws:iam::<aws_account_id>:role/ise-sectool-credentials-reader"
  external_id             = "xxx-ddd-gggg-fff" # <-- Replace with your external ID
  fisma_id                = "I-SecTools" # <-- Replace with your FISMA ID
  organization            = "GSACloud" # <-- Replace with your organization name
  tenant_name             = "SECOPS" # <-- Replace with your tenant name
  environment             = "DEV" # <-- Replace with your environment
  patch_group             = "#DONOTPATCH"

  # Operating system type (linux or windows)
  os_type = "linux"
}

```

### Example for Windows Instance

```hcl
#############################################
# Must be used with GSA Hardened AMI module #
#############################################

module "windows_server_2022_gsa_hardened" {
  source = "github.com/GSA/odp-tf-modules//modules/aws-gsa-hardened-amis/windows-server-2022?ref=v1.0.0"
}

##################################################
# Recommended to use SSM Instance Profile Module # (Optional but highly recommended)
##################################################

module "ssm_instance_profile" {
  source = "github.com/GSA/odp-tf-modules//modules/aws-ssm-instance-profile?ref=v1.0.0"

  assume_role_arn       = "arn:aws:iam::<aws_account_id>:role/ise-sectool-credentials-reader"
  role_name             = "SSMRole" # <-- Replace with your role name of your choice
  instance_profile_name = "SSMInstanceProfile" # <-- Replace with your instance profile name
  external_id           = "xxx-ddd-gggg-fff" # <-- Replace with your external ID

  # Tags are optional, but highly recommended. Add any additional tags that you want to apply to your instance profile.
  tags = {
    Name        = "SSMInstanceProfile"
    Environment = "DEV"
    Project     = "SECOPS"
  }
}

###############################
# GSA ISE EC2 Instance Module #
###############################

module "ec2_instance" {
  source                  = "github.com/GSA/odp-tf-modules//modules/aws-ec2-instance?ref=v1.0.0"
  ami                     = module.windows_server_2022_gsa_hardened.ami_id  # Windows AMI from GSA Hardened Images
  instance_type           = "t3.micro"
  subnet_id               = "subnet-abc123"
  vpc_security_group_ids  = ["sg-abc123"]
  key_name                = "my-key"
  iam_instance_profile    = "my-instance-profile"

  # Sectools configuration
  sec_tools_iam_role_arn  = "arn:aws:iam::<aws_account_id>:role/ise-sectool-credentials-reader"
  external_id             = "xxx-ddd-gggg-fff" # <-- Replace with your external ID
  fisma_id                = "I-SecTools" # <-- Replace with your FISMA ID
  organization            = "GSACloud" # <-- Replace with your organization name
  tenant_name             = "SECOPS" # <-- Replace with your tenant name
  environment             = "DEV" # <-- Replace with your environment
  patch_group             = "#DONOTPATCH"

  # Operating system type (linux or windows)
  os_type = "windows"
}


```
## Inputs

| Name                      | Description                                                       | Type        | Default      | Required |
|---------------------------|-------------------------------------------------------------------|-------------|--------------|----------|
| `ami`                      | AMI ID for the EC2 instance. Use GSA Hardened Images for compliance | `string`    | N/A          | Yes      |
| `instance_type`            | Instance type (e.g., `t3.micro`)                                  | `string`    | `"t3.micro"` | No       |
| `subnet_id`                | Subnet ID to launch the instance in                               | `string`    | N/A          | Yes      |
| `vpc_security_group_ids`   | List of security group IDs to associate with the instance          | `list`      | `[]`         | Yes      |
| `key_name`                 | SSH key pair name for accessing the instance                      | `string`    | `""`         | No       |
| `iam_instance_profile`     | IAM instance profile to associate with the EC2 instance            | `string`    | N/A          | Yes      |
| `sec_tools_iam_role_arn`   | IAM Role ARN for Sectools registration                             | `string`    | N/A          | Yes      |
| `external_id`              | External ID for assuming the IAM role                             | `string`    | N/A          | Yes      |
| `fisma_id`                 | FISMA ID for compliance                                           | `string`    | N/A          | Yes      |
| `organization`             | Organization tag for tracking purposes                            | `string`    | N/A          | Yes      |
| `tenant_name`              | Tenant name for the instance                                      | `string`    | N/A          | Yes      |
| `environment`              | Environment tag (e.g., `dev`, `prod`)                             | `string`    | N/A          | Yes      |
| `patch_group`              | Optional patch group setting                                      | `string`    | `"DONOTPATCH"` | No     |
| `os_type`                  | Operating system type (`linux` or `windows`)                      | `string`    | `"linux"`    | No       |


## Outputs

| Name              | Description                              |
|-------------------|------------------------------------------|
| `instance_id`     | ID of the created EC2 instance            |
| `public_ip`       | Public IP address of the instance         |
| `private_ip`      | Private IP address of the instance        |


## Sectools Registration

The module automatically runs the appropriate Sectools registration script based on the operating system type specified by the os_type variable.

- Linux: Runs `/build-artifacts/sectools-registration.sh` with the required parameters.
- Windows: Runs `C:\build-artifacts\sectools-registration.ps1` using PowerShell with the necessary parameters.

## Contributing
Contributions are welcome! Please reach out to your friendly neighborhood ISE-ODP DevSecOps team.

## License

This project is intended for internal use within the U.S. General Services Administration (GSA) only. Unauthorized use, distribution, or modification outside of GSA is prohibited.

For access or usage inquiries, please contact the GSA [relevant department or contact person].

## Authors
This repository is maintained by the U.S. General Services Administration (GSA). For any questions or issues related to this project, please contact GSA Office of the Chief Information Security Officer (OCISO)