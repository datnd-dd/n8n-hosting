#!/bin/bash

# Setup SSL for n8n with Docker Compose
# Enhanced version with better error handling and debugging

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 SSL Setup for n8n${NC}"
echo

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}Error: .env file not found!${NC}"
    exit 1
fi

echo "Domain: $DOMAIN"
echo "Email: $EMAIL"

# Check if domain is set
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo -e "${RED}Error: DOMAIN and EMAIL must be set in .env file${NC}"
    exit 1
fi

# Detect Docker Compose version
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}Error: Docker Compose not found${NC}"
    exit 1
fi

echo "Using: $COMPOSE_CMD"

# Check if certificates already exist
if [ -d "./certbot/conf/live/$DOMAIN" ]; then
    echo -e "${YELLOW}⚠️ SSL certificates already exist for $DOMAIN${NC}"
    
    # Show current certificate info
    if [ -f "./certbot/conf/live/$DOMAIN/cert.pem" ]; then
        EXPIRY_DATE=$(openssl x509 -in "./certbot/conf/live/$DOMAIN/cert.pem" -noout -enddate | cut -d= -f2)
        echo "Current certificate expires: $EXPIRY_DATE"
    fi
    
    read -p "Do you want to renew them? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping SSL certificate generation."
        exit 0
    fi
fi

# Pre-flight checks
echo -e "${YELLOW}🔍 Running pre-flight checks...${NC}"

# Check DNS resolution
echo -e "${YELLOW}Checking DNS resolution...${NC}"
if ! nslookup $DOMAIN > /dev/null 2>&1; then
    echo -e "${RED}❌ DNS resolution failed for $DOMAIN${NC}"
    echo -e "${YELLOW}Please ensure your domain points to this server${NC}"
    exit 1
fi

SERVER_IP=$(curl -s ipinfo.io/ip 2>/dev/null || echo "Unable to detect")
DOMAIN_IP=$(nslookup $DOMAIN | awk '/^Address: / { print $2 }' | tail -1)

if [ "$DOMAIN_IP" != "$SERVER_IP" ] && [ "$SERVER_IP" != "Unable to detect" ]; then
    echo -e "${YELLOW}⚠️ DNS mismatch: Domain points to $DOMAIN_IP, server IP is $SERVER_IP${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✅ DNS resolution OK${NC}"
fi

# Create directories with correct permissions
echo -e "${YELLOW}📁 Creating required directories...${NC}"
mkdir -p nginx/conf.d nginx/ssl certbot/conf certbot/www/.well-known/acme-challenge
chmod 755 certbot/www certbot/www/.well-known certbot/www/.well-known/acme-challenge

# Create/update HTTP-only nginx config for certificate generation
echo -e "${YELLOW}📝 Creating HTTP-only nginx config for SSL setup...${NC}"

# Backup existing config if it exists
if [ -f "nginx/conf.d/default.conf" ]; then
    cp nginx/conf.d/default.conf "nginx/conf.d/default.conf.backup.$(date +%s)"
fi

cat > nginx/conf.d/default.conf << EOF
# HTTP-only configuration for SSL certificate generation
server {
    listen 80;
    server_name $DOMAIN;

    # Certbot ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files \$uri \$uri/ =404;
        allow all;
        access_log off;
        log_not_found off;
    }

    # Health check
    location /health {
        return 200 "SSL setup in progress for $DOMAIN";
        add_header Content-Type text/plain;
    }

    # Default response for other requests
    location / {
        return 200 "SSL certificate generation in progress for $DOMAIN. Please wait...";
        add_header Content-Type text/plain;
    }
}
EOF

# Start nginx with HTTP-only config
echo -e "${YELLOW}🌐 Starting nginx with HTTP-only config...${NC}"
$COMPOSE_CMD up -d nginx

# Wait for nginx to start
echo -e "${YELLOW}⏳ Waiting for nginx to start...${NC}"
sleep 10

# Test nginx is responding
echo -e "${YELLOW}🧪 Testing nginx response...${NC}"
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f -s "http://$DOMAIN/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Nginx is responding${NC}"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo -e "${YELLOW}⏳ Retry $RETRY_COUNT/$MAX_RETRIES - waiting for nginx...${NC}"
        sleep 5
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}❌ Nginx is not responding after $MAX_RETRIES attempts${NC}"
    echo -e "${YELLOW}Checking nginx logs:${NC}"
    $COMPOSE_CMD logs nginx | tail -10
    exit 1
fi

# Test webroot accessibility
echo -e "${YELLOW}🔍 Testing webroot accessibility...${NC}"
TEST_FILE="test-$(date +%s).txt"
echo "Test file for SSL setup" > "./certbot/www/.well-known/acme-challenge/$TEST_FILE"

sleep 3
if curl -f -s "http://$DOMAIN/.well-known/acme-challenge/$TEST_FILE" | grep -q "Test file"; then
    echo -e "${GREEN}✅ Webroot is accessible${NC}"
    rm -f "./certbot/www/.well-known/acme-challenge/$TEST_FILE"
else
    echo -e "${RED}❌ Webroot is not accessible${NC}"
    echo -e "${YELLOW}Testing with curl verbose:${NC}"
    curl -v "http://$DOMAIN/.well-known/acme-challenge/$TEST_FILE" || true
    rm -f "./certbot/www/.well-known/acme-challenge/$TEST_FILE"
    exit 1
fi

# Generate SSL certificate
echo -e "${YELLOW}🔒 Generating SSL certificate...${NC}"

# Try staging first to avoid rate limits
echo -e "${YELLOW}Testing with Let's Encrypt staging server first...${NC}"
if $COMPOSE_CMD run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --staging \
    --force-renewal \
    --non-interactive \
    -d "$DOMAIN"; then
    
    echo -e "${GREEN}✅ Staging certificate generated successfully!${NC}"
    
    # Now generate production certificate
    echo -e "${YELLOW}Generating production certificate...${NC}"
    if $COMPOSE_CMD run --rm certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        --non-interactive \
        -d "$DOMAIN"; then
        
        echo -e "${GREEN}🎉 Production SSL certificate generated successfully!${NC}"
        
        # Show certificate details
        echo -e "${YELLOW}📋 Certificate details:${NC}"
        $COMPOSE_CMD run --rm certbot certificates
        
    else
        echo -e "${RED}❌ Production SSL certificate generation failed!${NC}"
        echo -e "${YELLOW}Possible reasons:${NC}"
        echo "• Rate limiting (try again in 1 hour)"
        echo "• Domain verification failed"
        echo "• Network connectivity issues"
        
        echo -e "${YELLOW}But staging worked, so the setup is correct.${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Even staging SSL certificate generation failed!${NC}"
    echo -e "${YELLOW}Please check:${NC}"
    echo "• Domain DNS points to this server"
    echo "• Ports 80 and 443 are accessible from internet"
    echo "• No firewall blocking connections"
    exit 1
fi

# Create full HTTPS nginx configuration
echo -e "${YELLOW}🔄 Creating full HTTPS nginx configuration...${NC}"

cat > nginx/conf.d/default.conf << EOF
# HTTP server - redirect to HTTPS and handle ACME challenge
server {
    listen 80;
    server_name $DOMAIN;

    # Certbot ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files \$uri \$uri/ =404;
    }

    # Redirect all other HTTP traffic to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl;
    http2 on;
    server_name $DOMAIN;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Main proxy configuration to n8n
    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support for n8n
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;
        
        # Buffer settings
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    # Webhook endpoint optimization
    location /webhook {
        proxy_pass http://n8n:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Faster timeouts for webhooks
        proxy_connect_timeout 30;
        proxy_send_timeout 30;
        proxy_read_timeout 30;
    }

    # File upload limits
    client_max_body_size 50M;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF

# Restart all services with HTTPS configuration
echo -e "${YELLOW}🔄 Restarting services with HTTPS configuration...${NC}"
$COMPOSE_CMD down
$COMPOSE_CMD up -d

# Wait for services to start
echo -e "${YELLOW}⏳ Waiting for services to start...${NC}"
sleep 20

# Test HTTPS
echo -e "${YELLOW}🧪 Testing HTTPS...${NC}"
MAX_RETRIES=5
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f -s "https://$DOMAIN" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ HTTPS is working correctly!${NC}"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo -e "${YELLOW}⏳ HTTPS test $RETRY_COUNT/$MAX_RETRIES...${NC}"
        sleep 10
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${YELLOW}⚠️ HTTPS test failed, but certificate exists${NC}"
    echo -e "${YELLOW}This might be normal if services are still starting${NC}"
    echo -e "${YELLOW}Try visiting https://$DOMAIN in your browser${NC}"
fi

# Final summary
echo
echo -e "${GREEN}🎉 SSL Setup completed successfully!${NC}"
echo
echo -e "${BLUE}📋 Summary:${NC}"
echo "• Domain: $DOMAIN"
echo "• SSL Certificate: ✅ Generated"
echo "• HTTPS Redirect: ✅ Configured"
echo "• Security Headers: ✅ Applied"
echo "• n8n Proxy: ✅ Configured"

echo
echo -e "${BLUE}🌐 Access your n8n instance:${NC}"
echo "• HTTPS: https://$DOMAIN"
echo "• HTTP will redirect to HTTPS automatically"

echo
echo -e "${BLUE}📊 Next Steps:${NC}"
echo "• Complete n8n setup at https://$DOMAIN"
echo "• Install SSL auto-renewal: ./scripts/install-cronjob.sh"
echo "• Create a backup: ./scripts/backup.sh"

echo
echo -e "${BLUE}🔧 Troubleshooting:${NC}"
echo "• View logs: $COMPOSE_CMD logs nginx"
echo "• Test SSL: curl -I https://$DOMAIN"
echo "• Check certificates: $COMPOSE_CMD run --rm certbot certificates"
