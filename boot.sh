#!/bin/bash

# VPS Bootstrap
# Uso: 
#   Instalação: curl -s https://raw.githubusercontent.com/alanalvestech/newvps/main/boot.sh | sudo bash
#   Desinstalação: sudo bash boot.sh uninstall

set -euo pipefail

# Variáveis SSL
DOMAIN=""
EMAIL=""

# Obtém IP da VPS
SERVER_IP=$(curl -s http://ipinfo.io/ip)

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
        if [ -f docker-compose-waha.yaml ]; then
            docker compose -f docker-compose-waha.yaml down || true
            rm -f docker-compose-waha.yaml
        fi
    fi
    rm -f .env
    rm -rf tokens
    rm -rf files

    # Remove Docker and containers
    log_info "Removendo Docker e todos os containers..."
    if systemctl list-unit-files | grep -q docker.service; then
        systemctl stop docker || true
    fi
    if command -v docker &> /dev/null; then
        docker system prune -af || true
    fi
    
    # Remove Docker packages if they exist
    for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            apt-get remove --purge -y "$pkg" || true
        fi
    done

    # Remove Docker directories and files
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

    log_info "Desinstalação concluída com sucesso!"
    exit 0
}

########################################################
# Verificar argumentos
########################################################
if [ "${1:-}" = "uninstall" ]; then
    uninstall "${@}"
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

    log_info "Configurando proxy reverso..."
    log_info "Baixando template do Nginx..."
    NGINX_TEMPLATE_URL="https://raw.githubusercontent.com/alanalvestech/newvps/main/configs/nginx/app.conf.template"
    curl -s "$NGINX_TEMPLATE_URL" | sed "s/{{DOMAIN}}/${DOMAIN}/g" > /etc/nginx/sites-available/app

    # Testa configuração
    nginx -t || {
        log_error "Configuração do Nginx inválida"
        exit 1
    }

    ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Testar configuração
    nginx -t || {
        log_error "Configuração do Nginx inválida"
        exit 1
    }

    systemctl restart nginx
    systemctl enable nginx

    log_info "Nginx instalado e configurado com sucesso!"
    log_info "Acesse: http://$SERVER_IP"
    log_info "WAHA disponível em: http://$SERVER_IP/waha/"
}

########################################################
# Instalar WAHA
########################################################
{
    log_info "Instalando WAHA..."

    # Verificar espaço em disco
    AVAILABLE_SPACE=$(df -m / | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1000 ]; then
        log_warn "Pouco espaço em disco disponível (${AVAILABLE_SPACE}MB). Limpando..."
        apt-get clean
        docker system prune -af --volumes || true
    fi

    # Verificar se o Docker está rodando
    if ! systemctl is-active --quiet docker; then
        log_info "Reiniciando serviço Docker..."
        systemctl restart docker
        sleep 5
    fi

    # Testar conexão do Docker
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker não está respondendo. Tentando reiniciar..."
        systemctl restart docker
        sleep 5
        if ! docker info > /dev/null 2>&1; then
            log_error "Falha ao conectar com Docker"
            exit 1
        fi
    fi

    # Limpar cache do Docker
    log_info "Limpando cache do Docker..."
    systemctl stop docker
    rm -rf /var/lib/docker/tmp/*
    systemctl start docker
    sleep 5

    # Pull da imagem WAHA antes de configurar
    log_info "Baixando imagem do WAHA..."
    for i in {1..3}; do
        if docker pull devlikeapro/waha; then
            break
        fi
        log_warn "Tentativa $i falhou. Tentando novamente..."
        sleep 5
    done

    if ! docker images | grep -q devlikeapro/waha; then
        log_error "Falha ao baixar imagem do WAHA após 3 tentativas"
        exit 1
    fi

    wget -O .env https://raw.githubusercontent.com/devlikeapro/waha/refs/heads/core/.env.example

    cat > docker-compose-waha.yaml << 'EOF'
services:
  waha:
    container_name: waha
    image: devlikeapro/waha
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./tokens:/app/tokens
      - ./files:/app/files
    env_file:
      - .env
EOF

    API_KEY=$(openssl rand -hex 32)
    ADMIN_PASS=$(openssl rand -base64 12)
    SWAGGER_PASS=$(openssl rand -base64 12)

    log_info "Configurando credenciais..."
    cat > .env << EOF
WHATSAPP_API_KEY=${API_KEY}
WAHA_DASHBOARD_USERNAME=admin
WAHA_DASHBOARD_PASSWORD=${ADMIN_PASS}
WHATSAPP_SWAGGER_USERNAME=admin
WHATSAPP_SWAGGER_PASSWORD=${SWAGGER_PASS}
EOF

    mkdir -p tokens files

    log_info "Iniciando WAHA..."
    docker compose -f docker-compose-waha.yaml up -d

    log_info "Aguardando serviço iniciar..."
    sleep 10

    if ! curl -s http://localhost:3000/health > /dev/null; then
        log_error "Falha na instalação do WAHA"
        exit 1
    fi

    log_info "WAHA instalado com sucesso!"
}

########################################################
# Função para configurar SSL
########################################################
configurar_ssl() {
    log_info "Configurando SSL..."
    
    # Solicita domínio e email se não fornecidos
    if [ -z "$DOMAIN" ]; then
        read -p "Digite seu domínio (ex: exemplo.com.br): " DOMAIN
    fi
    
    if [ -z "$EMAIL" ]; then
        read -p "Digite seu email para o certificado SSL: " EMAIL
    fi
    
    # Instala Certbot
    apt-get install -y certbot python3-certbot-nginx
    
    # Gera parâmetros DH fortes
    log_info "Gerando parâmetros DH..."
    mkdir -p /etc/nginx/ssl
    openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048
    
    # Configura Nginx para o domínio
    log_info "Baixando template do Nginx..."
    NGINX_TEMPLATE_URL="https://raw.githubusercontent.com/alanalvestech/newvps/main/configs/nginx/app.conf.template"
    curl -s "$NGINX_TEMPLATE_URL" | sed "s/{{DOMAIN}}/${DOMAIN}/g" > /etc/nginx/sites-available/app

    # Testa configuração
    nginx -t || {
        log_error "Configuração do Nginx inválida"
        exit 1
    }
    
    # Configura renovação automática
    log_info "Configurando renovação automática..."
    echo "0 0,12 * * * root python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew -q" > /etc/cron.d/certbot
    
    # Backup diretório SSL
    log_info "Configurando backup dos certificados..."
    echo "0 0 1 * * root tar -czf /root/letsencrypt-backup-\$(date +\%Y\%m).tar.gz /etc/letsencrypt/" > /etc/cron.d/ssl-backup
    
    # Obtém certificado SSL
    log_info "Obtendo certificados..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
    
    # Testa configuração Nginx
    nginx -t || {
        log_error "Configuração SSL inválida"
        exit 1
    }
    
    # Reinicia Nginx
    systemctl restart nginx

    log_info "SSL configurado com sucesso!"
    log_info "Certificados em: /etc/letsencrypt/live/$DOMAIN/"
    log_info "Backups mensais em: /root/letsencrypt-backup-*.tar.gz"
    log_info "Acesse: https://$DOMAIN"
    log_info "WAHA disponível em: https://$DOMAIN/waha/"
}

########################################################
# Finalização
########################################################
log_info "Configurando SSL..."
configurar_ssl

log_info "Instalação concluída!"