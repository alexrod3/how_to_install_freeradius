#!/bin/bash
# ============================================================
# 🛠️ Projeto: Hotspot Surfix - Instalação Automática
# 📅 Versão: 1.4 (corrigida)
# 🧑 Autor: alexrod3 (modificado para corrigir ExecStart)
# 📧 Contato: github.com/alexrod3
# 🐧 Compatível com: Ubuntu Server 24.04 LTS
# ============================================================

echo "🔍 Verificando versão do Ubuntu..."
OS_VERSION=$(lsb_release -rs)
if [[ "$OS_VERSION" != "24.04" ]]; then
  echo "❌ Este script foi projetado para Ubuntu 24.04. Você está usando: $OS_VERSION"
  exit 1
fi

echo "🧼 Removendo pacotes antigos para evitar conflitos..."
sudo apt purge -y freeradius* mariadb* apache2* php* net-tools whois unzip git
sudo apt autoremove -y
sudo apt update

echo "📦 Instalando pacotes essenciais..."
sudo apt install -y build-essential libssl-dev libcurl4-openssl-dev libnl-3-dev libnl-genl-3-dev pkg-config git autoconf automake libtool \
freeradius freeradius-utils freeradius-mysql mariadb-server apache2 php php-mysql net-tools whois unzip

echo "🐙 Instalando CoovaChilli v1.7 manualmente..."
cd /usr/src
sudo rm -rf coova-chilli
sudo git clone https://github.com/coova/coova-chilli.git
cd coova-chilli
sudo autoreconf -fi
sudo ./configure --prefix=/usr --sysconfdir=/etc
sudo make
sudo make install

# ✅ Correção: garantir que o binário esteja disponível em /usr/sbin
if [[ -f /usr/src/coova-chilli/src/chilli ]]; then
  echo "📁 Copiando binário chilli para /usr/sbin..."
  sudo cp /usr/src/coova-chilli/src/chilli /usr/sbin/chilli
  sudo chmod +x /usr/sbin/chilli
else
  echo "❌ Erro: binário chilli não encontrado após compilação!"
  exit 1
fi

echo "🔧 Criando serviço systemd para CoovaChilli..."
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

echo "✅ Ativando serviços principais..."
for svc in freeradius mariadb apache2 coovachilli; do
  if systemctl list-unit-files | grep -q "${svc}.service"; then
    echo "🔧 Iniciando serviço: $svc"
    sudo systemctl enable --now "$svc"
  else
    echo "❌ Serviço não encontrado: $svc"
    exit 1
  fi
done

echo "🔍 Detectando interfaces de rede..."
WAN_IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
LAN_IFACE=$(ip link | grep -E 'wlan|wl|ap' | awk -F: '{print $2}' | head -n1 | xargs)

echo "🌐 Interface WAN: $WAN_IFACE"
echo "📡 Interface LAN: $LAN_IFACE"

echo "🔐 Configurando banco de dados MariaDB..."
sudo mysql -e "CREATE DATABASE radius;"
sudo mysql -e "CREATE USER 'radius'@'localhost' IDENTIFIED BY 'radius';"
sudo mysql -e "GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "👤 Adicionando usuário de teste ao FreeRADIUS..."
USER_CONF="/etc/freeradius/3.0/mods-config/files/authorize"
sudo cp $USER_CONF ${USER_CONF}.bak
echo -e "\nradius Cleartext-Password := \"radius\"" | sudo tee -a $USER_CONF

echo "🔧 Configurando CoovaChilli..."
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
sudo systemctl restart mariadb
sudo systemctl restart apache2
sudo systemctl restart coovachilli

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
