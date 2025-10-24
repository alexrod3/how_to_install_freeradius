#!/bin/bash
# ============================================================
# 🛠️ Instalação do CoovaChilli + FreeRADIUS + Apache
# 📦 Compatível com: Ubuntu Server 24.04 LTS
# 🔄 Portátil: IP e interfaces detectados automaticamente
# ============================================================

set -e

info()  { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m $1"; }

info "🔄 Removendo instalações anteriores..."
sudo systemctl stop coovachilli || true
sudo systemctl disable coovachilli || true
sudo rm -f /etc/systemd/system/coovachilli.service
sudo rm -rf /etc/chilli /usr/src/coova-chilli /usr/sbin/chilli
sudo apt purge -y freeradius* mariadb* apache2* php* net-tools whois unzip git || true
sudo apt autoremove -y
sudo ufw --force disable || true

info "🔄 Atualizando sistema..."
sudo apt update -y && sudo apt upgrade -y

info "📦 Instalando dependências..."
sudo apt install -y build-essential libssl-dev libcurl4-openssl-dev libnl-3-dev \
libnl-genl-3-dev libtool-bin libjson-c-dev pkg-config git autoconf automake \
libtool gengetopt net-tools iptables apache2 php php-mysql mariadb-server \
freeradius freeradius-utils freeradius-mysql unzip whois ufw

info "🐙 Clonando e compilando CoovaChilli..."
cd /usr/src
sudo git clone https://github.com/coova/coova-chilli.git
cd coova-chilli
sudo autoreconf -fi
sudo ./configure --prefix=/usr --sysconfdir=/etc
sudo make clean
sudo make || { echo "❌ Erro na compilação do CoovaChilli"; exit 1; }

# ✅ Correção: garantir que o binário seja instalado
if [[ -f src/chilli ]]; then
  sudo make install
  sudo cp src/chilli /usr/sbin/chilli
  sudo chmod +x /usr/sbin/chilli
  ok "Binário chilli instalado em /usr/sbin/chilli"
else
  echo "❌ Erro: binário chilli não encontrado após compilação"
  exit 1
fi

info "🛠️ Criando serviço systemd..."
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

info "🌐 Ativando IP forwarding..."
sudo sed -i 's/#\?net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

info "📡 Detectando interface WAN e IP local..."
WAN_IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
IP_LOCAL=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
info "🌐 Interface WAN: $WAN_IFACE"
info "📍 IP local detectado: $IP_LOCAL"

info "🔍 Procurando interface LAN..."
LAN_IFACE=$(ip link | grep -E 'wlan|wl|ap|br' | awk -F: '{print $2}' | head -n1 | xargs)

if [ -z "$LAN_IFACE" ]; then
  info "Nenhuma interface LAN detectada. Criando lan0 virtual..."
  LAN_IFACE="lan0"
  sudo ip link add name $LAN_IFACE type dummy || true
  sudo ip link set $LAN_IFACE up
fi

info "Atribuindo IP à interface LAN: $LAN_IFACE"
sudo ip addr flush dev $LAN_IFACE || true
sudo ip addr add 192.168.182.1/24 dev $LAN_IFACE

info "📁 Criando configuração do CoovaChilli..."
sudo mkdir -p /etc/chilli
sudo tee /etc/chilli/config > /dev/null <<EOF
HS_WANIF=$WAN_IFACE
HS_LANIF=$LAN_IFACE
HS_NETWORK=192.168.182.0
HS_NETMASK=255.255.255.0
HS_UAMLISTEN=192.168.182.1
HS_UAMPORT=3990
HS_UAMUIP=192.168.182.1
HS_UAMSERVER=192.168.182.1
HS_UAMSECRET=secret
HS_RADIUS=$IP_LOCAL
HS_RADIUS2=$IP_LOCAL
HS_RADSECRET=testing123
HS_NASID=nas01
HS_NASIP=192.168.182.1
HS_LOC_NAME="Hotspot Surfix"
HS_LOC_ID=surfix01
HS_ADMIN_EMAIL=admin@localhost
EOF

info "🔓 Liberando portas no firewall (UFW)..."
sudo ufw --force enable
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 3990/tcp
sudo ufw allow 1812/udp
sudo ufw allow 1813/udp

info "🗄️ Configurando banco de dados..."
sudo mysql -e "CREATE DATABASE IF NOT EXISTS radius;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'radius'@'localhost' IDENTIFIED BY 'radius';"
sudo mysql -e "GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

info "👤 Adicionando usuário de teste ao FreeRADIUS..."
echo 'testuser Cleartext-Password := "testpass"' | sudo tee -a /etc/freeradius/3.0/mods-config/files/authorize > /dev/null

info "🔄 Reiniciando serviços..."
sudo systemctl restart freeradius
sudo systemctl restart apache2
sudo systemctl restart coovachilli

ok "🎉 Instalação concluída com sucesso!"
echo "----------------------------------------------"
echo "➡️ Portal captive: http://192.168.182.1:3990"
echo "➡️ Teste RADIUS: radtest testuser testpass $IP_LOCAL 0 testing123"
echo "➡️ MySQL user: radius | senha: radius"
echo "----------------------------------------------"
