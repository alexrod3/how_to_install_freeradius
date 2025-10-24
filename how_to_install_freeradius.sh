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
  if systemctl list-unit-files | g
