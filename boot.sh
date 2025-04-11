#!/bin/bash

# VPS Bootstrap
# Uso: curl -s https://raw.githubusercontent.com/alancriaxyz/myvps/main/boot.sh | sudo bash

set -euo pipefail

########################################################
# Funções de log
########################################################
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

########################################################
# Verificar root
########################################################
if [ "$EUID" -ne 0 ]; then 
    log_error "Execute como root"
    exit 1
fi

########################################################
# Atualizar sistema
########################################################
log_info "Atualizando sistema..."
apt-get update
apt-get upgrade -y

########################################################
# Instalar Git
########################################################
log_info "Instalando Git..."
apt-get install -y git

if ! command -v git &> /dev/null; then
    log_error "Falha na instalação do Git"
    exit 1
fi

log_info "Git instalado com sucesso!"
log_info "Versão: $(git --version)"

########################################################
# Instalar Docker
########################################################
log_info "Instalando Docker..."

apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl start docker
systemctl enable docker

if ! command -v docker &> /dev/null; then
    log_error "Falha na instalação do Docker"
    exit 1
fi

log_info "Docker instalado com sucesso!"
log_info "Versão: $(docker --version)"
log_info "Compose: $(docker compose version)"

########################################################
# Instalar Python e FastAPI
########################################################
log_info "Instalando Python e FastAPI..."

apt-get install -y python3 python3-pip python3-venv

python3 -m venv /opt/app
source /opt/app/bin/activate

pip install fastapi uvicorn python-dotenv

if ! command -v uvicorn &> /dev/null; then
    log_error "Falha na instalação do FastAPI"
    exit 1
fi

log_info "FastAPI instalado com sucesso!"
log_info "Versão: $(pip show fastapi | grep Version)"

########################################################
# Finalização
########################################################
log_info "Instalação concluída!"
log_warn "Reinicie o sistema para aplicar todas as alterações"