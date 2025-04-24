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

###############################################################################
# Funções de log
###############################################################################
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

###############################################################################
# Coletar informações necessárias
###############################################################################
{
    log_info "Configuração inicial..."
    
    read -p "Digite seu domínio: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        log_error "Domínio é obrigatório"
        exit 1
    fi
    
    DOMAIN=$(echo "$DOMAIN" | sed -e 's#^http[s]*://##' -e 's#/$##')
    
    read -p "Digite seu email: " EMAIL
    if [ -z "$EMAIL" ]; then
        log_error "Email é obrigatório"
        exit 1
    fi
    
    if ! echo "$EMAIL" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        log_error "Email inválido. Use o formato: usuario@dominio.com"
        exit 1
    fi

    log_info "✓ Domínio: $DOMAIN"
    log_info "✓ Email: $EMAIL"
    echo ""
}

###############################################################################
# Atualizar sistema
###############################################################################
{
    log_info "Verificando atualizações..."
    apt-get update
    
    if apt list --upgradable 2>/dev/null | grep -q "^[a-zA-Z]"; then
        log_info "Atualizando pacotes..."
        apt-get upgrade -y
        log_info "Sistema atualizado com sucesso!"
    else
        log_info "Sistema já está atualizado"
    fi
}

###############################################################################
# Instalar Git
###############################################################################
{
    if ! command -v git &> /dev/null; then
        log_info "Instalando Git..."
        
        apt-get install -y git

        if ! command -v git &> /dev/null; then
            log_error "Falha na instalação do Git"
            exit 1
        fi
        log_info "Git instalado com sucesso!"
    else
        log_info "Git já está instalado"
    fi
    
    log_info "Versão: $(git --version)"
}

###############################################################################
# Instalar Nginx
###############################################################################
{
    mkdir -p /opt/newvps/templates

    if ! command -v nginx &> /dev/null; then
        log_info "Instalando Nginx..."
        
        apt-get install -y nginx
        log_info "Nginx instalado com sucesso!"
    else
        log_info "Nginx já está instalado"
    fi
    
    log_info "Versão: $(nginx -v 2>&1)"
}

###############################################################################
# Instalar e Configurar SSL
############################################################################### 
{
    if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" ]; then
        log_info "Certificado Let's Encrypt já existe"
        SSL_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
        
        if certbot certificates | grep -q "${DOMAIN}.*VALID: 30 days or less"; then
            log_info "Renovando certificado Let's Encrypt..."
            certbot renew --quiet
        fi
    else
        log_info "Tentando configurar Let's Encrypt..."
        if apt-get install -y certbot python3-certbot-nginx &>/dev/null; then
            log_info "Gerando certificado Let's Encrypt..."
            if certbot certonly --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}" &>/dev/null; then
                log_info "✓ Let's Encrypt configurado com sucesso"
                
                log_info "Configurando renovação automática..."
                echo "0 0,12 * * * root python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew -q" > /etc/cron.d/certbot
                
                log_info "Configurando backup dos certificados..."
                echo "0 0 1 * * root tar -czf /root/letsencrypt-backup-\$(date +\%Y\%m).tar.gz /etc/letsencrypt/" > /etc/cron.d/ssl-backup
                
                SSL_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
                SSL_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
            else
                log_warn "Não foi possível obter certificado Let's Encrypt"
                USE_SELF_SIGNED=true
            fi
        else
            log_warn "Let's Encrypt não disponível"
            USE_SELF_SIGNED=true
        fi
    fi

    if [ "${USE_SELF_SIGNED}" = "true" ]; then
        if [ -f "/etc/nginx/ssl/nginx.crt" ] && [ -f "/etc/nginx/ssl/nginx.key" ]; then
            log_info "Certificado auto-assinado já existe"
            SSL_CERT="/etc/nginx/ssl/nginx.crt"
            SSL_KEY="/etc/nginx/ssl/nginx.key"
        else
            log_info "Gerando certificado auto-assinado..."
            mkdir -p /etc/nginx/ssl
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/nginx/ssl/nginx.key \
                -out /etc/nginx/ssl/nginx.crt \
                -subj "/CN=${DOMAIN}" &>/dev/null
                
            SSL_CERT="/etc/nginx/ssl/nginx.crt"
            SSL_KEY="/etc/nginx/ssl/nginx.key"
            log_info "✓ Certificado auto-assinado gerado"
        fi
    fi

    log_info "✓ SSL configurado ($([ "${USE_SELF_SIGNED}" = "true" ] && echo "auto-assinado" || echo "Let's Encrypt"))"
}

###############################################################################
# Configurar Nginx (site)
###############################################################################
{
    log_info "Configurando diretório do site..."
    mkdir -p /var/www/site
    chown -R www-data:www-data /var/www/site
    chmod -R 755 /var/www/site

    if [ ! -r "/var/www/site" ] || [ ! -x "/var/www/site" ]; then
        log_error "Erro: diretório /var/www/site não tem permissões corretas"
        exit 1
    fi

    log_info "Configurando Nginx..."
    
    log_info "Baixando template do Nginx..."
    NGINX_TEMPLATE_URL="https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/configs/nginx/site.conf.template"
    if ! wget -q "$NGINX_TEMPLATE_URL" -O /opt/newvps/templates/nginx.conf.template; then
        log_error "Erro ao baixar template do Nginx"
        exit 1
    fi
    
    log_info "Aplicando configuração..."
    sed -e "s/{{DOMAIN}}/${DOMAIN}/g" \
        -e "s|{{SSL_CERT}}|${SSL_CERT}|g" \
        -e "s|{{SSL_KEY}}|${SSL_KEY}|g" \
        /opt/newvps/templates/nginx.conf.template > /etc/nginx/sites-available/app

    log_info "Configurando links..."
    ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    log_info "Testando configuração do Nginx..."
    nginx -t || {
        log_error "Erro na configuração do Nginx"
        log_error "Verifique os logs acima"
        exit 1
    }

    log_info "Reiniciando Nginx..."
    systemctl restart nginx

    log_info "✓ Nginx configurado e rodando"
}

###############################################################################
# Instalar Python e FastAPI
###############################################################################
# {
#     # Verifica se Python já está instalado
#     if ! command -v python3 &> /dev/null; then
#         log_info "Instalando Python..."
#         
#         apt-get install -y python3 python3-pip python3-venv || {
#             log_error "Falha ao instalar Python"
#             exit 1
#         }
#         log_info "Python instalado com sucesso!"
#     else
#         log_info "Python já está instalado"
#         log_info "Versão: $(python3 --version)"
#     fi

#     # # Verifica se FastAPI já está instalado
#     # if ! pip show fastapi &> /dev/null; then
#     #     log_info "Instalando FastAPI..."
#     #     pip install fastapi uvicorn python-dotenv || {
#     #         log_error "Falha ao instalar FastAPI"
#     #         exit 1
#     #     }
#     #     log_info "FastAPI instalado com sucesso!"
#     # else
#     #     log_info "FastAPI já está instalado"
#     # fi

#     # log_info "Versão FastAPI: $(pip show fastapi | grep Version)"
#     # log_info "Versão Uvicorn: $(pip show uvicorn | grep Version)"
# }

###############################################################################
# Instalar Docker
###############################################################################
# {
#     # Verifica se Docker já está instalado
#     if ! command -v docker &> /dev/null; then
#         log_info "Instalando Docker..."

#         log_info "Instalando dependências..."
#         apt-get install -y ca-certificates curl gnupg || {
#             log_error "Falha ao instalar dependências"
#             exit 1
#         }

#         log_info "Configurando diretório..."
#         install -m 0755 -d /etc/apt/keyrings || {
#             log_error "Falha ao criar diretório keyrings"
#             exit 1
#         }

#         log_info "Removendo GPG antigo..."
#         rm -f /etc/apt/keyrings/docker.gpg

#         log_info "Baixando chave GPG..."
#         curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || {
#             log_error "Falha ao baixar/configurar chave GPG"
#             exit 1
#         }
#         chmod a+r /etc/apt/keyrings/docker.gpg

#         log_info "Detectando distribuição..."
#         if [ -f /etc/os-release ]; then
#             . /etc/os-release
#             OS=$ID
#             VERSION_CODENAME=$VERSION_CODENAME
#         else
#             OS="ubuntu"
#             VERSION_CODENAME="jammy"
#         fi
#         log_info "Sistema detectado: $OS $VERSION_CODENAME"

#         log_info "Configurando repositório..."
#         echo \
#           "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
#           $VERSION_CODENAME stable" | \
#           tee /etc/apt/sources.list.d/docker.list > /dev/null

#         log_info "Atualizando repositórios..."
#         apt-get update || {
#             log_error "Falha ao atualizar repositórios"
#             exit 1
#         }

#         log_info "Instalando pacotes Docker..."
#         apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
#             log_error "Falha ao instalar pacotes Docker"
#             exit 1
#         }

#         log_info "Iniciando serviço Docker..."
#         systemctl start docker || {
#             log_error "Falha ao iniciar Docker"
#             exit 1
#         }
#         systemctl enable docker

#         if ! command -v docker &> /dev/null; then
#             log_error "Falha na instalação do Docker"
#             exit 1
#         fi

#         log_info "Docker instalado com sucesso!"
#     else
#         log_info "Docker já está instalado"
#     fi

#     log_info "Versão: $(docker --version)"
#     log_info "Compose: $(docker compose version)"
# }



###############################################################################
# Instalar WAHA
###############################################################################
# {
#     log_info "Instalando WAHA..."

#     # Cria estrutura de diretórios
#     mkdir -p docker/waha/tokens docker/waha/files

#     # Gera credenciais
#     API_KEY=$(openssl rand -hex 32)
#     ADMIN_PASS=$(openssl rand -base64 12)
#     SWAGGER_PASS=$(openssl rand -base64 12)

#     # Baixa e configura docker-compose
#     log_info "Configurando Docker Compose..."
#     WAHA_COMPOSE_URL="https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/configs/waha/docker-compose.yml.template"
#     wget -q "$WAHA_COMPOSE_URL" -O docker/waha/docker-compose.yaml

#     # Baixa e configura env
#     log_info "Configurando variáveis de ambiente..."
#     WAHA_ENV_URL="https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/configs/waha/env.template"
#     wget -q "$WAHA_ENV_URL" -O docker/waha/.env.template

#     # Substitui variáveis no arquivo .env
#     sed "s|{{API_KEY}}|$API_KEY|g" docker/waha/.env.template > docker/waha/.env.tmp
#     sed "s|{{ADMIN_PASSWORD}}|$ADMIN_PASS|g" docker/waha/.env.tmp > docker/waha/.env.tmp2
#     sed "s|{{SWAGGER_PASSWORD}}|$SWAGGER_PASS|g" docker/waha/.env.tmp2 > docker/waha/.env
#     rm docker/waha/.env.tmp docker/waha/.env.tmp2

#     log_info "Iniciando WAHA..."
#     cd docker/waha
#     docker compose up -d

#     log_info "Aguardando serviço iniciar..."
#     sleep 10

#     if ! curl -s http://localhost:3000/health > /dev/null; then
#         log_error "Falha na instalação do WAHA"
#         exit 1
#     fi

#     cd ../..
#     log_info "WAHA instalado com sucesso!"
# }

###############################################################################
# Finalização
###############################################################################
{
    # Remove script de instalação
    rm -f boot.sh

    log_info "Instalação concluída!"
}
