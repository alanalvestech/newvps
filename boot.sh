#!/bin/bash

# VPS Bootstrap
# Uso: 
#   Instalação: curl -s https://raw.githubusercontent.com/alanalvestech/newvps/main/boot.sh | sudo bash
#   Desinstalação: sudo bash boot.sh uninstall

set -euo pipefail

########################################################
# Funções de log
########################################################
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

########################################################
# Função de desinstalação
########################################################
uninstall() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        log_error "Execute como root"
        exit 1
    fi

    # User confirmation
    log_warn "ATENÇÃO! Este script irá remover:"
    echo "  - Docker e todos os containers"
    echo "  - Docker Compose"
    echo "  - Git"
    echo "  - Python e FastAPI"
    echo "  - Ambiente virtual Python"
    echo "  - WAHA (WhatsApp HTTP API)"
    echo "  - Todos os arquivos do projeto"
    echo ""
    read -p "Tem certeza que deseja continuar? (digite 'sim' para confirmar): " confirmation

    if [ "$confirmation" != "sim" ]; then
        log_info "Operação cancelada pelo usuário"
        exit 0
    fi

    # Remove WAHA
    log_info "Removendo WAHA..."
    docker compose down || true
    rm -f .env docker-compose.yaml

    # Remove Docker and containers
    log_info "Removendo Docker e todos os containers..."
    systemctl stop docker || true
    apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    rm -rf /var/lib/docker
    rm -rf /etc/docker
    rm -rf /etc/apt/keyrings/docker.gpg
    rm -f /etc/apt/sources.list.d/docker.list

    # Remove Git
    log_info "Removendo Git..."
    apt-get remove -y git

    # Remove Python and FastAPI
    log_info "Removendo Python e FastAPI..."
    deactivate 2>/dev/null || true
    rm -rf /opt/app
    apt-get remove -y python3 python3-pip python3-venv
    apt-get autoremove -y

    # Clean unused packages
    log_info "Limpando pacotes não utilizados..."
    apt-get autoremove -y
    apt-get clean

    log_info "Desinstalação concluída com sucesso!"
    log_warn "Recomenda-se reiniciar o sistema para aplicar todas as alterações."
    exit 0
}

########################################################
# Verificar argumentos
########################################################
if [ "${1:-}" = "uninstall" ]; then
    uninstall
fi

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
# Remove arquivo GPG existente se houver
rm -f /etc/apt/keyrings/docker.gpg
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

# Criar arquivo main.py básico
mkdir -p /opt/app/src
cat > /opt/app/src/main.py << EOF
from fastapi import FastAPI

app = FastAPI(
    title="VPS API",
    description="API REST para gerenciamento da VPS",
    version="1.0.0"
)

@app.get("/")
def read_root():
    return {"status": "online"}

@app.get("/health")
def health_check():
    return {"status": "healthy"}
EOF

# Iniciar FastAPI em background
nohup uvicorn src.main:app --host 0.0.0.0 --port 8000 &

# Verificar se está rodando
sleep 2
if ! curl -s http://localhost:8000/health > /dev/null; then
    log_error "Falha ao iniciar o FastAPI"
    exit 1
fi

log_info "FastAPI rodando em: http://localhost:8000"
log_info "Documentação em: http://localhost:8000/docs"

########################################################
# Instalar WAHA
########################################################
log_info "Instalando WAHA..."

# Baixar arquivos de configuração
wget -O .env https://raw.githubusercontent.com/devlikeapro/waha/refs/heads/core/.env.example
wget -O docker-compose.yaml https://raw.githubusercontent.com/devlikeapro/waha/refs/heads/core/docker-compose.yaml

# Configurar variáveis de ambiente
sed -i "s/WHATSAPP_API_KEY=.*/WHATSAPP_API_KEY=$(openssl rand -hex 32)/" .env
sed -i "s/WAHA_DASHBOARD_USERNAME=.*/WAHA_DASHBOARD_USERNAME=admin/" .env
sed -i "s/WAHA_DASHBOARD_PASSWORD=.*/WAHA_DASHBOARD_PASSWORD=$(openssl rand -base64 12)/" .env
sed -i "s/WHATSAPP_SWAGGER_USERNAME=.*/WHATSAPP_SWAGGER_USERNAME=admin/" .env
sed -i "s/WHATSAPP_SWAGGER_PASSWORD=.*/WHATSAPP_SWAGGER_PASSWORD=$(openssl rand -base64 12)/" .env

# Iniciar serviço
docker compose up -d

if ! curl -s http://localhost:3000/health > /dev/null; then
    log_error "Falha na instalação do WAHA"
    exit 1
fi

log_info "WAHA instalado com sucesso!"
log_info "Dashboard disponível em: http://localhost:3000/dashboard"
log_info "API disponível em: http://localhost:3000/api"

########################################################
# Finalização
########################################################
log_info "Instalação concluída!"