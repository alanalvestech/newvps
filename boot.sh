#!/bin/bash

# VPS Bootstrap
# Uso: 
#
#   Instalação: 
#       wget https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/boot.sh && sudo bash boot.sh
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
    
    # Para todos os processos do Nginx
    pkill -9 nginx || true
    
    # Para e desabilita o serviço
    systemctl stop nginx || true
    systemctl disable nginx || true
    
    # Remove todos os pacotes relacionados ao Nginx
    apt-get purge -y nginx nginx-common nginx-full nginx-core || true
    apt-get autoremove -y --purge nginx* || true
    
    # Remove todos os arquivos de configuração
    rm -rf /etc/nginx
    rm -rf /var/log/nginx
    rm -rf /var/www/html
    rm -rf /usr/share/nginx
    rm -rf /usr/lib/nginx
    rm -rf /usr/sbin/nginx
    rm -rf /etc/init.d/nginx
    rm -rf /etc/logrotate.d/nginx
    rm -rf /var/lib/nginx
    rm -rf /etc/default/nginx
    rm -rf /etc/letsencrypt
    
    # Remove o serviço do systemd
    rm -rf /lib/systemd/system/nginx.service
    rm -rf /etc/systemd/system/nginx.service
    systemctl daemon-reload

    # Para o serviço Docker
    log_info "Parando serviço Docker..."
    if systemctl list-unit-files | grep -q docker.service; then
        systemctl stop docker || true
        systemctl disable docker || true
    fi

    # Remove WAHA
    log_info "Removendo WAHA..."
    if command -v docker &> /dev/null; then
        if [ -f docker/waha/docker-compose.yaml ]; then
            docker compose -f docker/waha/docker-compose.yaml down -v || true
        fi
    fi

    # Para todos os containers
    if command -v docker &> /dev/null; then
        docker stop $(docker ps -aq) 2>/dev/null || true
        docker rm $(docker ps -aq) 2>/dev/null || true
        docker network prune -f 2>/dev/null || true
        docker volume prune -f 2>/dev/null || true
        docker system prune -af 2>/dev/null || true
    fi

    # Remove diretório do projeto
    log_info "Removendo arquivos do projeto..."
    rm -rf "$(pwd)/docker"

    # Força kill de processos Docker remanescentes
    log_info "Removendo Docker..."
    pkill -9 -f docker || true
    sleep 2

    # Remove pacotes Docker
    for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            apt-get remove --purge -y "$pkg" || true
        fi
    done

    # Remove diretórios Docker com força
    systemctl stop docker.socket || true
    systemctl stop docker.service || true
    rm -rf /var/run/docker.sock
    rm -rf /var/lib/docker
    rm -rf /etc/docker
    rm -rf /etc/apt/keyrings/docker.gpg
    rm -f /etc/apt/sources.list.d/docker.list

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

    # Remove script de instalação
    rm -f boot.sh

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
# Verificar root e criar estrutura
########################################################
{
    if [ "$EUID" -ne 0 ]; then 
        log_error "Execute como root"
        exit 1
    fi

    # Cria estrutura de diretórios
    mkdir -p /opt/newvps/templates
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
    apt-get install -y nginx
    
    # Cria diretórios necessários
    log_info "Criando diretórios..."
    mkdir -p /etc/nginx/ssl
    mkdir -p /var/www/html
    chown -R www-data:www-data /var/www/html
    
    # Gera parâmetros DH fortes
    log_info "Gerando parâmetros DH..."
    openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048

    # Baixa templates do Nginx
    log_info "Baixando templates do Nginx..."
    NGINX_TEMPLATE_URL="https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/configs/nginx/app.conf.template"
    NGINX_INITIAL_URL="https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/configs/nginx/initial.conf.template"
    
    wget -q "$NGINX_TEMPLATE_URL" -O /opt/newvps/templates/nginx.conf.template
    wget -q "$NGINX_INITIAL_URL" -O /opt/newvps/templates/nginx.initial.template
    
    # Configura Nginx apenas com HTTP inicialmente
    log_info "Configurando Nginx..."
    sed "s/{{DOMAIN}}/${DOMAIN}/g" /opt/newvps/templates/nginx.initial.template > /etc/nginx/sites-available/app

    ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Testa e reinicia Nginx
    log_info "Testando configuração do Nginx..."
    nginx -t && systemctl restart nginx
}

########################################################
# Instalar e Configurar SSL
########################################################
{
    log_info "Instalando Certbot..."
    wait_for_apt
    apt-get install -y certbot python3-certbot-nginx

    # Configura renovação automática
    log_info "Configurando renovação automática..."
    echo "0 0,12 * * * root python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew -q" > /etc/cron.d/certbot
    
    # Backup diretório SSL
    log_info "Configurando backup dos certificados..."
    echo "0 0 1 * * root tar -czf /root/letsencrypt-backup-\$(date +\%Y\%m).tar.gz /etc/letsencrypt/" > /etc/cron.d/ssl-backup
    
    # Obtém certificado SSL
    log_info "Obtendo certificados..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"

    # Aplica configuração completa do Nginx com SSL
    log_info "Aplicando configuração SSL..."
    sed "s/{{DOMAIN}}/${DOMAIN}/g" /opt/newvps/templates/nginx.conf.template > /etc/nginx/sites-available/app
    
    # Cria página de teste
    echo "<h1>Servidor configurado com sucesso!</h1>" > /var/www/html/index.html
    chown www-data:www-data /var/www/html/index.html
    
    # Reinicia Nginx com nova configuração
    nginx -t && systemctl restart nginx
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
    wget -q "$WAHA_COMPOSE_URL" -O docker/waha/docker-compose.yaml

    # Baixa e configura env
    log_info "Configurando variáveis de ambiente..."
    WAHA_ENV_URL="https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/configs/waha/env.template"
    wget -q "$WAHA_ENV_URL" -O docker/waha/.env.template

    # Substitui variáveis no arquivo .env
    sed "s|{{API_KEY}}|$API_KEY|g" docker/waha/.env.template > docker/waha/.env.tmp
    sed "s|{{ADMIN_PASSWORD}}|$ADMIN_PASS|g" docker/waha/.env.tmp > docker/waha/.env.tmp2
    sed "s|{{SWAGGER_PASSWORD}}|$SWAGGER_PASS|g" docker/waha/.env.tmp2 > docker/waha/.env
    rm docker/waha/.env.tmp docker/waha/.env.tmp2

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