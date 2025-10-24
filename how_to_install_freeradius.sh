#!/bin/bash
# ============================================================
# 🛠️ Instalação Oficial do CoovaChilli + FreeRADIUS + Apache
# 📅 Compatível com: Ubuntu Server 24.04 LTS
# ============================================================

set -e

# Funções de mensagens
info()  { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERRO]\033[0m $1"; exit 1; }

info "Atualizando sistema..."
sudo apt update && sudo apt upgrade -y

info "Instalando dependências..."
sudo apt install -y build-essential libssl-dev libcurl4-openssl-dev libnl-3-dev \
libnl-genl-3-dev libtool-bin libjson-c-dev pkg-config git autoconf automake \
libtool gengetopt net-tools iptables apache2 php php-mysql mariadb-server \
freeradius freeradius-utils freeradius-mysql unzip whois

info "Clonando CoovaChilli..."
cd /usr/src
sudo git clone https://github.com/coova/coova-chilli.git
cd coova-chilli

info "Compilando CoovaChilli..."
sudo autoreconf -fi
sudo ./configure --prefix=/usr --sysconfdir=/etc
sudo make clean
sudo make
sudo make install

info "Criando serviço systemd..."
sudo tee /etc/systemd/system/coovachilli.service > /dev/null <<EOF
[Unit]
Description=CoovaChilli Captive Portal
After=network.target

[Service]
ExecStart=/usr/sbin/chilli -c /etc/chilli/config
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now coovachilli

info "Configurando IP forwarding..."
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

info "Criando configuração do CoovaChilli..."
sudo mkdir -p /etc/chilli
sudo tee /etc/chilli/config > /dev/null <<EOF
HS_WANIF=eth0
HS_LANIF=wlan0
HS_NETWORK=192.168.182.0
HS_NETMASK=255.255.255.0
HS_UAMLISTEN=192.168.182.1
HS_UAMPORT=3990
HS_UAMUIP=192.168.182.1
HS_UAMSERVER=192.168.182.1
HS_UAMSECRET=secret
HS_RADIUS=127.0.0.1
HS_RADIUS2=127.0.0.1
HS_RADSECRET=testing123
HS_NASID=nas01
HS_NASIP=192.168.182.1
HS_LOC_NAME="Hotspot Oficial"
HS_LOC_ID=hotspot01
HS_ADMIN_EMAIL=admin@localhost
EOF

info "Configurando firewall (UFW)..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 3990/tcp
sudo ufw allow 1812/udp
sudo ufw allow 1813/udp
sudo ufw --force enable

info "Configurando banco de dados..."
sudo mysql -e "CREATE DATABASE radius;"
sudo mysql -e "CREATE USER 'radius'@'localhost' IDENTIFIED BY 'radius';"
sudo mysql -e "GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

info "Adicionando usuário de teste ao FreeRADIUS..."
echo 'testuser Cleartext-Password := "testpass"' | sudo tee -a /etc/freeradius/3.0/mods-config/files/authorize

info "Reiniciando serviços..."
sudo systemctl restart freeradius
sudo systemctl restart apache2
sudo systemctl restart coovachilli

ok "Instalação concluída com sucesso!"
echo "➡️ Acesse o portal captive em: http://192.168.182.1:3990"
