#!/bin/bash

# VPS Bootstrap - Uninstaller Script
# WARNING: This script removes Docker, Git, Python/FastAPI and all project files

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

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
echo "  - Todos os arquivos do projeto"
echo ""
read -p "Tem certeza que deseja continuar? (digite 'sim' para confirmar): " confirmation

if [ "$confirmation" != "sim" ]; then
    log_info "Operação cancelada pelo usuário"
    exit 0
fi

# Remove Docker and containers using specific script
log_info "Removendo Docker e todos os containers..."
bash services/docker/uninstall.sh

# Remove Git using specific script
log_info "Removendo Git..."
bash services/git/uninstall.sh

# Remove Python and FastAPI
log_info "Removendo Python e FastAPI..."
deactivate 2>/dev/null || true
rm -rf /opt/app
apt-get remove -y python3 python3-pip python3-venv
apt-get autoremove -y

# Remove project directory
log_info "Removendo diretório do projeto..."
cd ..
rm -rf /Users/414n/workspace/newvps

# Clean unused packages
log_info "Limpando pacotes não utilizados..."
apt-get autoremove -y
apt-get clean

log_info "Desinstalação concluída com sucesso!"
log_warn "Recomenda-se reiniciar o sistema para aplicar todas as alterações." 