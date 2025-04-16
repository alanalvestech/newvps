# NewVPS Bootstrap

Projeto para automatizar a configuração de VPS com Docker, FastAPI e WAHA (WhatsApp HTTP API) para automação de mensagens.

## 🚀 Funcionalidades

- Atualização automática do sistema
- Instalação do Git
- Instalação do Docker e Docker Compose
- Instalação do Python e FastAPI
- Instalação do WAHA (WhatsApp HTTP API)
- Configuração automática de SSL/HTTPS

## 📋 Pré-requisitos

- Sistema Operacional: Debian/Ubuntu
- Acesso root ou sudo
- Conexão com internet
- Mínimo 2CPU e 2GB RAM
- Domínio apontado para o IP da VPS (para SSL)

## 🛠️ Instalação

Execute os seguintes comandos para instalar:

```bash
curl -s https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/boot.sh | sudo bash
```

Durante a instalação, você poderá optar por configurar SSL. Será necessário fornecer:
- Domínio (ex: exemplo.com.br)
- Email (para notificações do Let's Encrypt)

## 🗑️ Desinstalação

Para remover todos os componentes instalados:

```bash
curl -s https://raw.githubusercontent.com/alanalvestech/newvps/refs/heads/main/boot.sh | sudo bash -s uninstall -y
```

## 📱 Acessando

Após a instalação, acesse:

FastAPI:
- API: http(s)://seu-dominio/
- Documentação: http(s)://seu-dominio/docs
- Health Check: http(s)://seu-dominio/health

WAHA:
- Dashboard: http(s)://seu-dominio/waha/dashboard
- API: http(s)://seu-dominio/waha/api
- Documentação: http(s)://seu-dominio/waha/swagger
