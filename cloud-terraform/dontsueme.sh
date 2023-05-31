#!/bin/bash

###
# Common variables
###
# curl -H Metadata-Flavor:Google http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
export EXTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
export IMAGE=kazhem/dontsueme:v1.0.0

###
# docker
###
# Wait for apt lock
DEBIAN_FRONTEND=noninteractive sudo apt-get -o DPkg::Lock::Timeout=60 update
# install docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# verify docker installation
sudo docker run hello-world

###
# Run DontSueMe
###
# Create data directiory for sqlite db
mkdir -p /var/db/dontsueme

# Generate config
mkdir -p /etc/dontsueme
cat <<EOF > /etc/dontsueme/dontsueme.env
DB_DIR=/data
DEFAULT_SUPERUSER_NAME=dontsueme
DEFAULT_SUPERUSER_EMAIL=dont@sue.me
DEFAULT_SUPERUSER_PASSWORD=dontsueme
EOF

# Create systemd unit file to run dontsueme docker container
cat <<EOF > /etc/systemd/system/dontsueme.service
[Unit]
Description=DontSueMe Service
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=/usr/bin/docker pull ${IMAGE}
ExecStart=/usr/bin/docker run --rm --name %n \
    --env-file /etc/dontsueme/dontsueme.env \
    -v /var/db/dontsueme:/data \
    -p 127.0.0.1:8081:8000 \
    ${IMAGE}
ExecStop=/usr/bin/docker stop %n

[Install]
WantedBy=default.target
EOF

# Start dontsueme via systemd
systemctl daemon-reload
systemctl restart dontsueme.service || systemctl start dontsueme.service
systemctl enable dontsueme.service

# SSL
apt install -y nginx certbot python3-certbot-nginx
cat <<EOF > /etc/nginx/sites-available/dontsueme.conf
server {
    server_name dontsueme.$EXTERNAL_IP.sslip.io;

    location / {
      proxy_pass http://localhost:8081/;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header Host \$host;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection upgrade;
      proxy_set_header Accept-Encoding gzip;
      proxy_set_header   X-Real-IP         \$remote_addr;
      proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
      proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EOF

###
# certbot
###
sudo ln -s ../sites-available/dontsueme.conf /etc/nginx/sites-enabled/dontsueme.conf
sudo certbot --non-interactive --redirect --agree-tos --nginx -d dontsueme.$EXTERNAL_IP.sslip.io -m admin@gmail.com
systemctl restart nginx
