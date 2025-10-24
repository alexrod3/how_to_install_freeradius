#!/bin/bash
# ============================================================
# 🛠️ Projeto: Hotspot Surfix - Instalação Automática
# 📅 Versão: 1.0
# 🧑 Autor: Seu Nome ou Empresa
# 📧 Contato: seuemail@dominio.com
# 🐧 Compatível com: Ubuntu Server 24.04 LTS
# 📦 Serviços instalados:
#   - FreeRADIUS (Autenticação)
#   - CoovaChilli (Captive Portal)
#   - MariaDB (Banco de dados)
#   - Apache2 + PHP (Servidor Web)
#   - Utilitários: whois, net-tools, git
# ============================================================

echo "🔧 Atualizando sistema..."
sudo apt update && sudo apt upgrade -y

echo "📦 Instalando pacotes essenciais..."
sudo apt install -y freeradius freeradius-utils freeradius-mysql mariadb-server apache2 php php-mysql coovachilli net-tools whois unzip git

echo "🚀 Iniciando e habilitando serviços..."
sudo systemctl enable --now freeradius
sudo systemctl enable --now mysql
sudo systemctl enable --now apache2
sudo systemctl enable --now chilli

echo "🔍 Detectando interfaces de rede..."
WAN_IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
LAN_IFACE=$(ip link | grep -E 'wlan|wl|ap' | awk -F: '{print $2}' | head -n1 | xargs)

echo "🌐 Interface WAN detectada: $WAN_IFACE"
echo "📡 Interface LAN detectada: $LAN_IFACE"

echo "🔐 Configurando banco de dados MariaDB..."
sudo mysql -e "CREATE DATABASE radius;"
sudo mysql -e "CREATE USER 'radius'@'localhost' IDENTIFIED BY 'radius';"
sudo mysql -e "GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "👤 Adicionando usuário de teste ao FreeRADIUS..."
USER_CONF="/etc/freeradius/3.0/mods-config/files/authorize"
sudo cp $USER_CONF ${USER_CONF}.bak
echo -e "\nradius Cleartext-Password := \"radius\"" | sudo tee -a $USER_CONF

echo "🔧 Configurando CoovaChilli com interfaces detectadas..."
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
HS_RADIUS=127.0.0.1
HS_RADIUS2=127.0.0.1
HS_RADSECRET=testing123
HS_NASID=nas01
HS_NASIP=192.168.182.1
HS_LOC_NAME="Hotspot Surfix"
HS_LOC_ID=surfix01
HS_ADMIN_EMAIL=admin@localhost
EOF

echo "🔄 Reiniciando serviços..."
sudo systemctl restart freeradius
sudo systemctl restart chilli
sudo systemctl restart apache2

echo "📡 Detectando IP local..."
IP_LOCAL=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

echo "🔍 WHOIS do IP local:"
whois $IP_LOCAL | grep -E 'OrgName|netname|descr|country'

echo "✅ Testando autenticação com radtest..."
radtest radius radius localhost 0 testing123

echo -e "\n🎉 Instalação concluída com sucesso!"
echo "🔐 Credenciais de acesso:"
echo "➡️ IP do servidor: $IP_LOCAL"
echo "➡️ Porta RADIUS: 1812"
echo "➡️ Usuário RADIUS: radius"
echo "➡️ Senha RADIUS: radius"
echo "➡️ Shared Secret: testing123"
echo "➡️ MySQL User: radius"
echo "➡️ MySQL Password: radius"
echo "➡️ Banco de dados: radius"
echo "➡️ Portal de cadastro: http://$IP_LOCAL"
