# GSA ISE SSM Instance Profile Terraform Module
This Terraform module, hosted in the [GSA GitHub repository](https://github.com/GSA/odp-tf-module-aws-ssm-instance-profile), creates an IAM role, attaches the required AmazonSSMManagedInstanceCore policy, and you can use the role with an instance profile for use with AWS EC2 instances. The created instance profile allows EC2 instances to be managed by AWS Systems Manager (SSM). To use this in conjunction with the GSA ISE EC2 Instance Module goto https://github.com/GSA/odp-tf-module-aws-ec2-instance 

## Requirements
* Terraform 1.0 or later
* AWS Provider 3.0 or later

## Usage
#### Basic Example
```hcl
module "ssm_instance_profile" {
  source = "github.com/GSA/odp-tf-modules//modules/aws-ssm-instance-profile?ref=v1.0.0"

  # REQUIRED
  assume_role_arn       = "arn:aws:iam::SECRETS_ACCOUNT_ID:role/ise-sectool-credentials-reader" # Pass as a variable provided by ISE Team
  external_id           = "123456789012"                 # Pass as a variable provided by ISE Team
  secrets_account_id    = "SECRETS_ACCOUNT_ID"           # Pass as a variable provided by ISE Team

  # OPTIONAL (Recommended)
  role_name             = "MyCustomSSMRole"              # Defaults to "GSA_ISE_SSM_Instance_Profile_Role"
  instance_profile_name = "MyCustomSSMInstanceProfile"   # Defaults to "GSA_ISE_SSM_Instance_Profile"
  tags                  = {
    Name        = "MyProjectSSMInstanceProfile"
    Environment = "Production"
    Project     = "MyProject"
  }
}
```
## Inputs
| Name                             | Description                                             | Type          | Default                               | Required |
| :------------------------------- | :-----------------------------------------------------: | ------------: | :------------------------------------ | :------: |
| `assume_role_arn`                | The ARN of the role that the EC2 instance should assume | string        | n/a                                   |   Yes    |
| `external_id`                    | The External ID to use when assuming the role	         | string        | n/a                                   |   Yes    |
| `role_name`                      | The name of the IAM Role for SSM                        | string        | `GSA_ISE_SSM_Instance_Profile_Role`   |   No     | 
| `instance_profile_name`          | The name of the IAM Instance Profile for SSM            | string        | `GSA_ISE_SSM_Instance_Profile`        |   No     |
| `tags`                           | A map of tags to add to all resources                   | map(string)   | {}                                    |   No     |

## Outputs

| Name                        | Description                                     |
| :-------------------------- | :---------------------------------------------: |
| `ssm_instance_profile_name` |   The name of the created SSM Instance Profile  |
| `ssm_instance_profile_arn`  |   The ARN of the created SSM Instance Profile   |

## Resources
This module creates the following resources:

* `aws_iam_role` - The IAM Role that EC2 instances assume for SSM. This role also includes a policy that allows the EC2 instance to assume the ise-sectool-credentials-reader role via sts:AssumeRole.
* `aws_iam_role_policy_attachment` - Attaches the AmazonSSMManagedInstanceCore policy to the IAM Role.
* `aws_iam_instance_profile` - The IAM Instance Profile that is attached to EC2 instances.

## Contributing
Contributions are welcome! Please reach out to your friendly neighborhood ISE-ODP DevSecOps team.

## License

This project is intended for internal use within the U.S. General Services Administration (GSA) only. Unauthorized use, distribution, or modification outside of GSA is prohibited.

For access or usage inquiries, please contact the GSA [relevant department or contact person].

## Authors
This repository is maintained by the U.S. General Services Administration (GSA). For any questions or issues related to this project, please contact GSA Office of the Chief Information Security Officer (OCISO)
