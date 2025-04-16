#!/bin/bash

# VPS Bootstrap
# Uso: 
#
#   Instalação: 
#       wget https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/boot.sh -O /tmp/boot.sh && sudo bash /tmp/boot.sh
#
#   Desinstalação: 
#       sudo bash boot.sh uninstall

set -euo pipefail

########################################################
# Funções de log
########################################################
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

########################################################
# Função para esperar lock do apt
########################################################
wait_for_apt() {
    local max_attempts=3  # 15 segundos (5s * 3)
    local attempt=1

    # Tenta matar qualquer processo apt/dpkg existente
    pkill -9 -f "apt-get|dpkg" || true
    
    # Remove todos os locks imediatamente
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/apt/lists/lock
    rm -f /var/lib/dpkg/lock-frontend
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock*
    
    # Repara o dpkg
    dpkg --configure -a || true
    
    # Pequena pausa para o sistema se recuperar
    sleep 2
}

########################################################
# Função de desinstalação
########################################################
uninstall() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        log_error "Execute como root"
        exit 1
    fi

    # Remove Nginx
    log_info "Removendo Nginx..."
    if systemctl list-unit-files | grep -q nginx.service; then
        systemctl stop nginx || true
        systemctl disable nginx || true
    fi
    if dpkg -l | grep -q "^ii.*nginx"; then
        apt-get remove --purge -y nginx nginx-common || true
    fi
    rm -f /etc/nginx/sites-enabled/app
    rm -f /etc/nginx/sites-available/app

    # Remove WAHA
    log_info "Removendo WAHA..."
    if command -v docker &> /dev/null; then
        if [ -f docker/waha/docker-compose.yaml ]; then
            docker compose -f docker/waha/docker-compose.yaml down || true
        fi
    fi
    rm -rf docker/waha
    rm -rf tokens
    rm -rf files

    # Remove Docker and containers
    log_info "Removendo Docker e todos os containers..."
    
    # Para todos os containers
    if command -v docker &> /dev/null; then
        docker stop $(docker ps -aq) 2>/dev/null || true
        docker rm $(docker ps -aq) 2>/dev/null || true
        docker network prune -f 2>/dev/null || true
        docker volume prune -f 2>/dev/null || true
    fi

    # Para o serviço Docker
    if systemctl list-unit-files | grep -q docker.service; then
        systemctl stop docker || true
        systemctl disable docker || true
    fi

    # Espera um pouco para garantir que tudo foi parado
    sleep 5

    # Remove pacotes Docker
    for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            apt-get remove --purge -y "$pkg" || true
        fi
    done

    # Força kill de processos Docker remanescentes
    pkill -9 -f docker || true
    
    # Espera novamente
    sleep 2

    # Remove diretórios e arquivos
    rm -rf /var/lib/docker
    rm -rf /etc/docker
    rm -rf /etc/apt/keyrings/docker.gpg
    rm -f /etc/apt/sources.list.d/docker.list

    log_info "Docker removido com sucesso!"

    # Remove Git if installed
    log_info "Removendo Git..."
    if dpkg -l | grep -q "^ii.*git"; then
        apt-get remove --purge -y git || true
    fi

    # Remove Python and FastAPI
    log_info "Removendo Python e FastAPI..."
    if [ -d "/opt/app" ]; then
        rm -rf /opt/app
    fi
    
    # Remove Python packages if they exist
    for pkg in python3-pip python3-venv python3; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            apt-get remove --purge -y "$pkg" || true
        fi
    done

    # Clean unused packages
    log_info "Limpando pacotes não utilizados..."
    apt-get autoremove --purge -y || true
    apt-get clean

    log_info "Desinstalação concluída com sucesso!"
    exit 0
}

########################################################
# Verificar argumentos
########################################################
{
    if [ "${1:-}" = "uninstall" ]; then
        uninstall "${@}"
    fi
}

########################################################
# Verificar root
########################################################
{
    if [ "$EUID" -ne 0 ]; then 
        log_error "Execute como root"
        exit 1
    fi
}

########################################################
# Coletar informações necessárias
########################################################
{
    log_info "Configuração inicial..."

    # Verifica se está em modo desinstalação
    if [ "${1:-}" = "uninstall" ]; then
        uninstall "${@}"
    fi
    
    # Lê domínio
    read -p "Digite seu domínio: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        log_error "Domínio é obrigatório"
        exit 1
    fi
    
    # Remove http:// ou https:// e barra final
    DOMAIN=$(echo "$DOMAIN" | sed -e 's#^http[s]*://##' -e 's#/$##')
    
    # Lê email
    read -p "Digite seu email: " EMAIL
    if [ -z "$EMAIL" ]; then
        log_error "Email é obrigatório"
        exit 1
    fi
    
    # Valida formato do email
    if ! echo "$EMAIL" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        log_error "Email inválido. Use o formato: usuario@dominio.com"
        exit 1
    fi

    log_info "✓ Domínio: $DOMAIN"
    log_info "✓ Email: $EMAIL"
    echo ""
}

########################################################
# Atualizar sistema
########################################################
{
    log_info "Atualizando sistema..."
    wait_for_apt
    apt-get update
    wait_for_apt
    apt-get upgrade -y
}

########################################################
# Instalar Git
########################################################
{
    log_info "Instalando Git..."
    wait_for_apt
    apt-get install -y git

    if ! command -v git &> /dev/null; then
        log_error "Falha na instalação do Git"
        exit 1
    fi

    log_info "Git instalado com sucesso!"
    log_info "Versão: $(git --version)"
}

########################################################
# Instalar Docker
########################################################
{
    log_info "Instalando Docker..."

    log_info "Instalando dependências..."
    apt-get install -y ca-certificates curl gnupg || {
        log_error "Falha ao instalar dependências"
        exit 1
    }

    log_info "Configurando diretório..."
    install -m 0755 -d /etc/apt/keyrings || {
        log_error "Falha ao criar diretório keyrings"
        exit 1
    }

    log_info "Removendo GPG antigo..."
    rm -f /etc/apt/keyrings/docker.gpg

    log_info "Baixando chave GPG..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || {
        log_error "Falha ao baixar/configurar chave GPG"
        exit 1
    }
    chmod a+r /etc/apt/keyrings/docker.gpg

    log_info "Detectando distribuição..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_CODENAME=$VERSION_CODENAME
    else
        OS="ubuntu"
        VERSION_CODENAME="jammy"
    fi
    log_info "Sistema detectado: $OS $VERSION_CODENAME"

    log_info "Configurando repositório..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $VERSION_CODENAME stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    log_info "Atualizando repositórios..."
    apt-get update || {
        log_error "Falha ao atualizar repositórios"
        exit 1
    }

    log_info "Instalando pacotes Docker..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        log_error "Falha ao instalar pacotes Docker"
        exit 1
    }

    log_info "Iniciando serviço Docker..."
    systemctl start docker || {
        log_error "Falha ao iniciar Docker"
        exit 1
    }
    systemctl enable docker

    if ! command -v docker &> /dev/null; then
        log_error "Falha na instalação do Docker"
        exit 1
    fi

    log_info "Docker instalado com sucesso!"
    log_info "Versão: $(docker --version)"
    log_info "Compose: $(docker compose version)"
}

########################################################
# Instalar Python e FastAPI
########################################################
{
    log_info "Instalando Python e FastAPI..."
    wait_for_apt
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
}

########################################################
# Instalar e Configurar Nginx
########################################################
{
    log_info "Instalando Nginx..."
    wait_for_apt
    apt-get install -y nginx certbot python3-certbot-nginx
    
    # Gera parâmetros DH fortes
    log_info "Gerando parâmetros DH..."
    mkdir -p /etc/nginx/ssl
    openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048

    # Configura Nginx para o domínio
    log_info "Baixando template do Nginx..."
    NGINX_TEMPLATE_URL="https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/configs/nginx/app.conf.template"
    curl -s "$NGINX_TEMPLATE_URL" | sed "s/{{DOMAIN}}/${DOMAIN}/g" > /etc/nginx/sites-available/app

    ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Configura renovação automática
    log_info "Configurando renovação automática..."
    echo "0 0,12 * * * root python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew -q" > /etc/cron.d/certbot
    
    # Backup diretório SSL
    log_info "Configurando backup dos certificados..."
    echo "0 0 1 * * root tar -czf /root/letsencrypt-backup-\$(date +\%Y\%m).tar.gz /etc/letsencrypt/" > /etc/cron.d/ssl-backup
    
    # Obtém certificado SSL
    log_info "Obtendo certificados..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
    
    # Testa configuração
    nginx -t || {
        log_error "Configuração do Nginx inválida"
        exit 1
    }

    # Reinicia Nginx
    systemctl restart nginx
    systemctl enable nginx

    log_info "Nginx instalado e SSL configurado com sucesso!"
    log_info "Acesse: https://$DOMAIN"
}

########################################################
# Instalar WAHA
########################################################
{
    log_info "Instalando WAHA..."

    # Cria estrutura de diretórios
    mkdir -p docker/waha/tokens docker/waha/files

    # Gera credenciais
    API_KEY=$(openssl rand -hex 32)
    ADMIN_PASS=$(openssl rand -base64 12)
    SWAGGER_PASS=$(openssl rand -base64 12)

    # Baixa e configura docker-compose
    log_info "Configurando Docker Compose..."
    WAHA_COMPOSE_URL="https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/configs/waha/docker-compose.yml.template"
    curl -s "$WAHA_COMPOSE_URL" > docker/waha/docker-compose.yaml

    # Baixa e configura env
    log_info "Configurando variáveis de ambiente..."
    WAHA_ENV_URL="https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/configs/waha/env.template"
    curl -s "$WAHA_ENV_URL" | \
        sed "s/{{API_KEY}}/${API_KEY}/g" | \
        sed "s/{{ADMIN_PASS}}/${ADMIN_PASS}/g" | \
        sed "s/{{SWAGGER_PASS}}/${SWAGGER_PASS}/g" > docker/waha/.env

    log_info "Iniciando WAHA..."
    cd docker/waha
    docker compose up -d

    log_info "Aguardando serviço iniciar..."
    sleep 10

    if ! curl -s http://localhost:3000/health > /dev/null; then
        log_error "Falha na instalação do WAHA"
        exit 1
    fi

    cd ../..
    log_info "WAHA instalado com sucesso!"
}

########################################################
# Finalização
########################################################
log_info "Instalação concluída!"