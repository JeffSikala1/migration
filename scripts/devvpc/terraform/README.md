- In order to run this tf file you need to update the following:
    - the backend (i.e. DEV.tfbackend)
    - tfvars file (i.e. devvpc.tfvars)
    - assumes the vpc already exists. For example (dev vpc) needs to already exist

aws dynamodb create-table \
  --table-name conexux-devvpctflockid \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

  