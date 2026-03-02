#!/bin/bash -x
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
#exec > >(tee /var/log/cloud-init-output.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Executing userdata.sh............ "
date
#echo "Developer..1"|passwd ec2-user --stdin
#usermod -U ec2-user
cd /tmp
yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
yum install -y docker java-17-amazon-corretto git maven
systemctl enable docker
systemctl start docker
chown $USER /var/run/docker.sock
useradd -U -m -c "Sasikant Dale" -G docker dales01
useradd -U -m -c "Bob W" -G docker wernb01
useradd -U -m -c "John Z" -G docker zehej01
#docker run -v nginxVolume:/etc/nginx -h "nginx" --name="nginx" -p 80:80 -p 443:443 -d nginx:stable-alpine3.19
#stty rows 50 cols 132
#
#mkdir /var/lib/docker/volumes/nginxVolume/_data/ssl
echo "Done userdata.sh............"
