#!/bin/bash
# ============================================================
# 🛠️ Projeto: Hotspot Surfix - Instalação Automática
# 📅 Versão: 1.5 (estável)
# 🧑 Autor: alexrod3
# 📧 Contato: github.com/alexrod3
# 🐧 Compatível com: Ubuntu Server 24.04 LTS
# ============================================================

set -e

# --- Função de mensagens coloridas ---
info()  { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m $1"; }
warn()  { echo -e "\033[1;33m[AVISO]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERRO]\033[0m $1"; exit 1; }

info "Verificando versão do Ubuntu..."
OS_VERSION=$(lsb_release -rs)
if [[ "$OS_VERSION" != "24.04" ]]; then
  error "Este script foi projetado para Ubuntu 24.04. Você está usando: $OS_VERSION"
fi

# --- Removendo pacotes antigos ---
info "Removendo pacotes antigos..."
sudo apt purge -y freeradius* mariadb* apache2* php* net-tools whois unzip git || true
sudo apt autoremove -y
sudo apt update -y

# --- Instalando dependências ---
info "Instalando pacotes essenciais..."
sudo apt install -y build-essential libssl-dev libcurl4-openssl-dev libnl-3-dev \
libnl-genl-3-dev libtool-bin libjson-c-dev pkg-config git autoconf automake \
libtool freeradius freeradius-utils freeradius-mysql mariadb-server apache2 \
php php-mysql net-tools whois unzip

# --- Instalando CoovaChilli ---
info "Instalando CoovaChilli v1.7..."
cd /usr/src
sudo rm -rf coova-chilli
sudo git clone https://github.com/coova/coova-chilli.git || error "Falha ao clonar repositório coova-chilli!"
cd coova-chilli

info "Compilando CoovaChilli..."
sudo autoreconf -fi
sudo ./configure --prefix=/usr --sysconfdir=/etc
sudo make clean
sudo make || error "Erro durante a compilação do CoovaChilli!"

# --- Garantindo que o binário foi criado ---
if [[ -f src/chilli ]]; then
  ok "Binário chilli compilado com sucesso!"
  sudo make install
  sudo cp src/chilli /usr/sbin/chilli
  sudo chmod +x /usr/sbin/chilli
else
  error "Binário chilli não encontrado após compilação!"
fi

# --- Criando serviço systemd ---
info "Criando serviço systemd para CoovaChilli..."
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
sudo systemctl enable --now coovachilli || warn "Falha ao iniciar coovachilli (verifique depois)."

# --- Iniciando serviços principais ---
for svc in freeradius mariadb apache2 coovachilli; do
  if systemctl list-unit-files | grep -q "${svc}.service"; then
    info "Iniciando serviço: $svc"
    sudo systemctl enable --now "$svc"
  else
    warn "Serviço não encontrado: $svc"
  fi
done

# --- Configuração de rede ---
info "Detectando interfaces de rede..."
WAN_IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
LAN_IFACE=$(ip link | grep -E 'wlan|wl|ap' | awk -F: '{print $2}' | head -n1 | xargs)

info "WAN: $WAN_IFACE | LAN: $LAN_IFACE"

# --- Banco de dados ---
info "Configurando MariaDB..."
sudo mysql -e "CREATE DATABASE IF NOT EXISTS radius;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'radius'@'localhost' IDENTIFIED BY 'radius';"
sudo mysql -e "GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# --- Usuário de teste RADIUS ---
info "Adicionando usuário de teste ao FreeRADIUS..."
USER_CONF="/etc/freeradius/3.0/mods-config/files/authorize"
sudo cp $USER_CONF ${USER_CONF}.bak
echo -e "\nradius Cleartext-Password := \"radius\"" | sudo tee -a $USER_CONF > /dev/null

# --- Configuração CoovaChilli ---
info "Configurando CoovaChilli..."
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

# --- Reiniciando tudo ---
info "Reiniciando serviços..."
sudo systemctl restart freeradius mariadb apache2 coovachilli

# --- Teste final ---
IP_LOCAL=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
ok "Servidor ativo no IP: $IP_LOCAL"

info "Testando autenticação com radtest..."
radtest radius radius localhost 0 testing123 || warn "Falha ao testar autenticação RADIUS."

echo -e "\n🎉 \033[1;32mInstalação concluída com sucesso!\033[0m"
echo "---------------------------------------------"
echo "➡️ IP do servidor: $IP_LOCAL"
echo "➡️ Porta RADIUS: 1812"
echo "➡️ Usuário RADIUS: radius"
echo "➡️ Senha RADIUS: radius"
echo "➡️ Shared Secret: testing123"
echo "➡️ MySQL User: radius"
echo "➡️ MySQL Password: radius"
echo "➡️ Banco de dados: radius"
echo "➡️ Portal de cadastro: http://$IP_LOCAL"
echo "---------------------------------------------"
