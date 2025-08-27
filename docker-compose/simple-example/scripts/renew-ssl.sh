#!/bin/bash

# Renew SSL certificates for n8n
# This script should be run via crontab

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Log file
LOG_FILE="/var/log/ssl-renewal.log"

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

log_message "Starting SSL certificate renewal process"

# Change to script directory
cd "$(dirname "$0")/.."

# Load environment variables
if [ -f .env ]; then
    source .env
    log_message "Loaded environment variables for domain: $DOMAIN"
else
    log_message "ERROR: .env file not found!"
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    log_message "ERROR: DOMAIN not set in .env file"
    exit 1
fi

# Detect Docker Compose command
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    log_message "ERROR: Docker Compose not found"
    exit 1
fi

log_message "Using Docker Compose command: $COMPOSE_CMD"

# Check if certificates exist
if [ ! -d "./certbot/conf/live/$DOMAIN" ]; then
    log_message "ERROR: No certificates found for $DOMAIN"
    exit 1
fi

# Check certificate expiry (renew if expires within 30 days)
log_message "Checking certificate expiry for $DOMAIN"

# Get certificate expiry date
CERT_FILE="./certbot/conf/live/$DOMAIN/cert.pem"
if [ -f "$CERT_FILE" ]; then
    EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
    CURRENT_EPOCH=$(date +%s)
    DAYS_TO_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
    
    log_message "Certificate expires in $DAYS_TO_EXPIRY days ($EXPIRY_DATE)"
    
    if [ $DAYS_TO_EXPIRY -le 30 ]; then
        log_message "Certificate needs renewal (expires in $DAYS_TO_EXPIRY days)"
        NEEDS_RENEWAL=true
    else
        log_message "Certificate is still valid for $DAYS_TO_EXPIRY days, no renewal needed"
        NEEDS_RENEWAL=false
    fi
else
    log_message "WARNING: Certificate file not found, attempting renewal"
    NEEDS_RENEWAL=true
fi

if [ "$NEEDS_RENEWAL" = "true" ]; then
    log_message "Starting certificate renewal process"
    
    # Attempt renewal
    if $COMPOSE_CMD run --rm certbot renew --quiet --no-self-upgrade; then
        log_message "✅ Certificate renewal successful"
        
        # Check if nginx is running
        if $COMPOSE_CMD ps nginx | grep -q "Up"; then
            # Reload nginx configuration
            if $COMPOSE_CMD exec nginx nginx -s reload 2>/dev/null; then
                log_message "✅ Nginx configuration reloaded successfully"
            else
                log_message "⚠️ Failed to reload nginx configuration, restarting container"
                if $COMPOSE_CMD restart nginx; then
                    log_message "✅ Nginx container restarted successfully"
                else
                    log_message "❌ Failed to restart nginx container"
                    exit 1
                fi
            fi
        else
            log_message "⚠️ Nginx container is not running, starting services"
            if $COMPOSE_CMD up -d; then
                log_message "✅ Services started successfully"
            else
                log_message "❌ Failed to start services"
                exit 1
            fi
        fi
        
        # Test the renewed certificate
        sleep 10
        if curl -I "https://$DOMAIN" > /dev/null 2>&1; then
            log_message "✅ SSL certificate test passed"
            
            # Log new expiry date
            NEW_EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
            log_message "New certificate expires: $NEW_EXPIRY_DATE"
            
        else
            log_message "⚠️ SSL certificate test failed, but renewal was successful"
            log_message "This might be temporary - services may still be starting"
        fi
        
    else
        log_message "❌ Certificate renewal failed"
        
        # Log more details about the failure
        log_message "Checking certbot logs for more details..."
        $COMPOSE_CMD run --rm certbot renew --dry-run 2>&1 | tail -20 | while read line; do
            log_message "CERTBOT: $line"
        done
        
        exit 1
    fi
else
    log_message "No renewal needed - certificate is still valid"
fi

log_message "SSL certificate renewal process completed"

# Optional: Clean up old certificates (keep last 5 renewals)
if [ -d "./certbot/conf/archive/$DOMAIN" ]; then
    CERT_COUNT=$(ls -1 "./certbot/conf/archive/$DOMAIN"/cert*.pem 2>/dev/null | wc -l)
    if [ $CERT_COUNT -gt 5 ]; then
        log_message "Cleaning up old certificates (keeping last 5)"
        # Let certbot handle cleanup automatically
        $COMPOSE_CMD run --rm certbot delete --cert-name "$DOMAIN" --keep-last 5 2>/dev/null || true
    fi
fi

log_message "SSL renewal script finished successfully"
