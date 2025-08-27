#!/bin/bash

# Deploy script for quick setup on new server
# Usage: ./deploy.sh

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚢 n8n SSL Deployment Script${NC}"
echo "This script will set up n8n with SSL on a new server"
echo

# Check if running as root
#if [[ $EUID -eq 0 ]]; then
#   echo -e "${RED}❌ This script should not be run as root${NC}"
#   exit 1
#fi

# Check .env file
if [ ! -f .env ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    echo "Please create .env file with your configuration"
    exit 1
fi

source .env

# Validate required environment variables
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo -e "${RED}❌ DOMAIN and EMAIL must be set in .env file${NC}"
    exit 1
fi

# Detect Docker Compose command
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
    echo -e "${GREEN}✅ Using Docker Compose V2${NC}"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
    echo -e "${YELLOW}⚠️ Using Docker Compose V1 (consider upgrading)${NC}"
else
    echo -e "${RED}❌ Docker Compose not found${NC}"
    echo "Install: sudo apt install docker-compose-plugin"
    exit 1
fi

# Check for required tools
echo -e "${YELLOW}🔧 Checking system requirements...${NC}"
MISSING_TOOLS=()
for tool in docker curl wget openssl; do
    if ! command -v $tool &> /dev/null; then
        MISSING_TOOLS+=($tool)
        echo -e "${RED}❌ $tool not found${NC}"
    else
        echo -e "${GREEN}✅ $tool found${NC}"
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo -e "${RED}Please install missing tools:${NC}"
    echo "Ubuntu/Debian: sudo apt update && sudo apt install ${MISSING_TOOLS[*]}"
    echo "CentOS/RHEL: sudo yum install ${MISSING_TOOLS[*]}"
    exit 1
fi

# Check Docker permissions
if ! docker ps &> /dev/null; then
    echo -e "${RED}❌ Cannot run Docker without sudo${NC}"
    echo "Run: sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
fi

echo -e "${GREEN}📋 Configuration:${NC}"
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "Docker Compose: $COMPOSE_CMD"
echo

# Confirm deployment
read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Create directory structure
echo -e "${YELLOW}📁 Creating directory structure...${NC}"
mkdir -p nginx/conf.d nginx/ssl certbot/conf certbot/www scripts

# Make scripts executable
if [ -d "scripts" ]; then
    chmod +x scripts/*.sh
fi

# Check DNS resolution
echo -e "${YELLOW}🌐 Checking DNS resolution for $DOMAIN...${NC}"
if nslookup $DOMAIN > /dev/null 2>&1; then
    DOMAIN_IP=$(nslookup $DOMAIN | awk '/^Address: / { print $2 }' | tail -1)
    SERVER_IP=$(curl -s ipinfo.io/ip)
    
    if [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
        echo -e "${GREEN}✅ DNS resolution successful - Domain points to this server${NC}"
    else
        echo -e "${YELLOW}⚠️ DNS mismatch: Domain points to $DOMAIN_IP, server IP is $SERVER_IP${NC}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}⚠️ DNS resolution failed. Please ensure your domain points to this server.${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if ports are available
echo -e "${YELLOW}🔌 Checking if ports 80 and 443 are available...${NC}"
PORTS_BUSY=false
for port in 80 443; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        echo -e "${RED}❌ Port $port is already in use${NC}"
        netstat -tlnp 2>/dev/null | grep ":$port "
        PORTS_BUSY=true
    else
        echo -e "${GREEN}✅ Port $port is available${NC}"
    fi
done

if [ "$PORTS_BUSY" = true ]; then
    echo -e "${YELLOW}⚠️ Some required ports are in use. Please stop conflicting services.${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Pull Docker images
echo -e "${YELLOW}🐳 Pulling Docker images...${NC}"
$COMPOSE_CMD pull

# Start initial deployment
echo -e "${YELLOW}🚀 Starting initial deployment...${NC}"
$COMPOSE_CMD up -d

# Wait for services to start
echo -e "${YELLOW}⏳ Waiting for services to start...${NC}"
sleep 15

# Setup SSL if setup-ssl.sh exists
if [ -f "./scripts/setup-ssl.sh" ]; then
    echo -e "${YELLOW}🔒 Setting up SSL certificates...${NC}"
    ./scripts/setup-ssl.sh
else
    echo -e "${YELLOW}⚠️ setup-ssl.sh not found. SSL setup skipped.${NC}"
    echo "You can run SSL setup manually later."
fi

# Install cronjob if script exists
if [ -f "./scripts/install-cronjob.sh" ]; then
    echo -e "${YELLOW}⏰ Installing SSL renewal cronjob...${NC}"
    ./scripts/install-cronjob.sh
else
    echo -e "${YELLOW}⚠️ install-cronjob.sh not found. Cronjob setup skipped.${NC}"
fi

# Final checks
echo -e "${YELLOW}🧪 Performing final checks...${NC}"

# Check if services are running
if $COMPOSE_CMD ps | grep -q "Up"; then
    echo -e "${GREEN}✅ Docker services are running${NC}"
    $COMPOSE_CMD ps
else
    echo -e "${RED}❌ Some Docker services are not running${NC}"
    $COMPOSE_CMD ps
fi

# Check HTTP connectivity
echo -e "${YELLOW}🌐 Testing HTTP connectivity...${NC}"
if curl -I "http://$DOMAIN" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ HTTP is accessible${NC}"
else
    echo -e "${YELLOW}⚠️ HTTP test failed${NC}"
fi

# Check HTTPS connectivity
echo -e "${YELLOW}🔐 Testing HTTPS connectivity...${NC}"
sleep 5
if curl -I "https://$DOMAIN" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ HTTPS is working correctly${NC}"
else
    echo -e "${YELLOW}⚠️ HTTPS test failed. This might be normal if SSL setup failed or DNS hasn't propagated yet.${NC}"
fi

echo
echo -e "${GREEN}🎉 Deployment completed!${NC}"
echo
echo -e "${BLUE}📝 Next Steps:${NC}"
echo "1. Visit https://$DOMAIN to access n8n (or http://$DOMAIN if SSL failed)"
echo "2. Complete n8n initial setup"
echo "3. Configure your workflows"
echo
echo -e "${BLUE}📊 Useful Commands:${NC}"
echo "• View logs: $COMPOSE_CMD logs -f"
echo "• Restart services: $COMPOSE_CMD restart"
echo "• Create backup: ./scripts/backup.sh"
echo "• Renew SSL manually: ./scripts/renew-ssl.sh"
echo
echo -e "${GREEN}✨ Happy automating with n8n!${NC}"
