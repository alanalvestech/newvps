# NewVPS Bootstrap

Projeto para automatizar a configuração de VPS com Docker, FastAPI e WAHA (WhatsApp HTTP API) para automação de mensagens.

## 🚀 Funcionalidades

- Atualização automática do sistema
- Instalação do Git
- Instalação do Docker e Docker Compose
- Instalação do Python e FastAPI
- Instalação do WAHA (WhatsApp HTTP API)
- Configuração de ambiente virtual
- Scripts modulares e reutilizáveis
- Dashboard para WhatsApp
- API REST para automação de mensagens

## 📋 Pré-requisitos

- Sistema Operacional: Debian/Ubuntu
- Acesso root ou sudo
- Conexão com internet
- Mínimo 2CPU e 2GB RAM

## 🛠️ Instalação

Execute os seguintes comandos para instalar:

```bash
# Download do script de instalação
curl -s https://raw.githubusercontent.com/alanalvestech/newvps/main/boot.sh | sudo bash
```

## 📱 Acessando

Após a instalação, acesse:

FastAPI:
- API: http://localhost:8000
- Documentação: http://localhost:8000/docs
- Health Check: http://localhost:8000/health

WAHA:
- Dashboard: http://localhost:3000/dashboard
- API: http://localhost:3000/api
- Documentação: http://localhost:3000/swagger