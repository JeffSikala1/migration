CONTROL_PLANE_SG=sg-022389b783983d3b1
BASTION_SG=$(aws ec2 describe-instances \
              --instance-id i-0004b98bfaaff7d9e \
              --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

aws ec2 authorize-security-group-ingress \
     --group-id  $CONTROL_PLANE_SG \
     --protocol  tcp \
     --port      443 \
     --source-group $BASTION_SG 