#!/bin/bash

apt-get update
sleep 3
apt install unzip openjdk-11-jre-headless -y
curl -LO https://github.com/keycloak/keycloak/releases/download/20.0.2/keycloak-20.0.2.zip
unzip -q keycloak-20.0.2.zip
mkdir -p /opt/keycloak
cp -R keycloak-20.0.2/* /opt/keycloak

export PATH=$PATH:/opt/keycloak/bin
export KC_ADM_USER=admin
export KC_ADM_PASS=myadminpass
export EXTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

kc.sh build

# Prepare systemd things
groupadd keycloak
useradd -r -g keycloak -d /opt/keycloak -s /sbin/nologin keycloak
chown -R keycloak:keycloak /opt/keycloak
chmod o+x /opt/keycloak/bin/

cat <<EOF > /lib/systemd/system/keycloak.service
[Unit]
Description=Keycloak Service
After=network.target
[Service]
User=keycloak
Group=keycloak
PIDFile=/var/run/keycloak/keycloak.pid
WorkingDirectory=/opt/keycloak
Environment="KEYCLOAK_ADMIN=$KC_ADM_USER"
Environment="KEYCLOAK_ADMIN_PASSWORD=$KC_ADM_PASS"
ExecStart=/opt/keycloak/bin/kc.sh start \\
  --hostname-strict=false \\
  --hostname-strict-https=false \\
  --proxy=edge \\
  --log-level=INFO
[Install]
WantedBy=multi-user.target
EOF

# Start Keycloak via systemd
systemctl daemon-reload
systemctl start keycloak
systemctl enable keycloak

# SSL
apt install -y nginx certbot python3-certbot-nginx
cat <<EOF > /etc/nginx/sites-available/keycloak-server
server {
    server_name keycloak.$EXTERNAL_IP.sslip.io;

    location / {
      add_header 'Access-Control-Allow-Origin' '*';
      add_header 'Access-Control-Allow-Credentials' 'true';
      add_header 'Access-Control-Allow-Headers' 'Authorization,Accept,Origin,DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Content-Range,Range';
      add_header 'Access-Control-Allow-Methods' 'GET,POST,OPTIONS,PUT,DELETE,PATCH';

      proxy_pass http://localhost:8080/;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header Host \$host;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection upgrade;
      proxy_set_header Accept-Encoding gzip;
      proxy_set_header   X-Real-IP         \$remote_addr;
      proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;

      proxy_buffer_size 64k;
      proxy_buffers 4 64k;
      proxy_busy_buffers_size 64k;
    }
}
EOF

sudo ln -s ../sites-available/keycloak-server /etc/nginx/sites-enabled/keycloak-server
sudo certbot --non-interactive --redirect --agree-tos --nginx -d keycloak.$EXTERNAL_IP.sslip.io -m admin@gmail.com
systemctl restart nginx
