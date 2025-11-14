#!/bin/bash -x
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
#exec > >(tee /var/log/cloud-init-output.log|logger -t user-data -s 2>/dev/console) 2>&1
#echo "Executinr userdata.sh............ "
date
#echo "Developer..1"|pa.... ec2-user --stdin
#usermod -U ec2-user
cd /tmp
yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
yum install -y docker certbot python3-certbot-nginx
systemctl enable docker 
systemctl start docker
chown $USER /var/run/docker.sock
docker run -v nginxVolume:/etc/nginx -h "nginx" --name="nginx" -p 80:80 -p 443:443 -d nginx:stable
#stty rows 50 cols 132
#
mkdir /var/lib/docker/volumes/nginxVolume/_data/ssl
curl https://ssl-config.mozilla.org/ffdhe2048.txt > /var/lib/docker/volumes/nginxVolume/_data/ssl/diffie-hellman.pem

useradd -c "Rajesh Vaswani" vaswr01
useradd -c "Tyler G" pgollt01
useradd -c "Doug Nelson" nelsd01
useradd -c "Shilpika P" pamas01
useradd -c "Eli T" tatre01
useradd -c "Doug N" nelsd01
useradd -c "Rohit J" jangr01
useradd -c "Rupak B" barur01
useradd -c "Thai P" philt01
useradd -c "Phil T" thaip01
useradd -c "Abhita B" bakta01
useradd -c "Sasikant D" dales01
useradd -c "Bob W" wernb01


    
echo "Done userdata.sh............"

