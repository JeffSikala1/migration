# GSA Hardened AMI Terraform Module 
This repository contains multiple Terraform modules to retrieve the latest GSA hardened AMIs for various operating systems, such as Amazon Linux 2, Ubuntu 20.04, etc. Each module is organized in its respective folder.

## Requirements
* GSA Hardened AMI is owned by ISE. Ensure the GSA Hardened AMI has been shared to the AWS account.
* Terraform 0.12 or later
* AWS provider 3.x or later
## Usage
To use a specific AMI module, include the appropriate source in your Terraform configuration.

> **_NOTE:_** Below are examples for Amazon Linux 2 and Ubuntu 20.04.

#### Amazon Linux 2 Example
```hcl
module "amazon_linux_2_gsa_hardened" {
  source = "github.com/GSA/odp-tf-modules//modules/aws-gsa-hardened-amis/Amazon-Linux-2023?ref=v1.0.0"
}

output "ami_id" {
  value = module.amazon_linux_2_gsa_hardened.ami_id
}

```
#### Ubuntu 20.04 Example
```hcl
module "ubuntu_20_04_gsa_hardened" {
  source = "github.com/GSA/odp-tf-modules//modules/aws-gsa-hardened-amis/Ubuntu-20-04?ref=v1.0.0"
}

output "ami_id" {
  value = module.ubuntu_20_04_gsa_hardened.ami_id
}

```

## Inputs
Each module retrieves AMIs based on specific filters. The modules do not require any additional inputs.
## Outputs

| Name                              | Description                                              |
|-----------------------------------|----------------------------------------------------------|
| `ami_id`                          | The ID of the most recent GSA Hardened AMI for the specified operating system. |


## Resources
These modules do not create any resources. They only query AWS for the AMI ID.

## Contributing
Contributions are welcome! Please reach out to your friendly neighborhood ISE-ODP DevSecOps team.

## License

This project is intended for internal use within the U.S. General Services Administration (GSA) only. Unauthorized use, distribution, or modification outside of GSA is prohibited.

For access or usage inquiries, please contact the GSA [relevant department or contact person].

## Authors
This repository is maintained by the U.S. General Services Administration (GSA). For any questions or issues related to this project, please contact GSA Office of the Chief Information Security Officer (OCISO)
