#!/bin/bash

# Update the instance and install Docker
yum update -y
yum install -y git docker

# Start and enable Docker service
service docker start
chkconfig docker on

# Install Docker Compose dependencies
yum install -y gcc libffi-devel python3-devel openssl-devel libxcrypt-compat

# Install libcrypt package
yum install -y libcrypt

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Clone the repository
git clone https://github.com/neosizzle/cloud-1.git /home/ec2-user/cloud-1

# Create necessary directories
mkdir /home/ec2-user/cloud-1/docker/wordpress_data
mkdir /home/ec2-user/cloud-1/docker/ssl

# Generate SSL certificate
cd /home/ec2-user/cloud-1/docker/ssl
openssl req -x509 -nodes -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -subj "/C=MY/ST=Selangor/L=Kuala Lumpur"

# Start Docker Compose
cd /home/ec2-user/cloud-1/docker
docker-compose down
docker-compose up -d wordpress webserver
