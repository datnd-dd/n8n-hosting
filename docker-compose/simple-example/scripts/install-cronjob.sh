#!/bin/bash

# Install cronjob for SSL renewal
# Run this script once after setup

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}📅 Installing SSL Renewal Cronjob${NC}"
echo "Project directory: $PROJECT_DIR"
echo

# Check if renew-ssl.sh exists
if [ ! -f "$PROJECT_DIR/scripts/renew-ssl.sh" ]; then
    echo -e "${RED}❌ renew-ssl.sh not found in scripts directory${NC}"
    exit 1
fi

# Make sure renew-ssl.sh is executable
chmod +x "$PROJECT_DIR/scripts/renew-ssl.sh"

# Create log directory
sudo mkdir -p /var/log
sudo touch /var/log/ssl-renewal.log
sudo chmod 644 /var/log/ssl-renewal.log

echo -e "${YELLOW}📅 Installing SSL renewal cronjob...${NC}"

# Create crontab entry - runs at 2:30 AM daily
CRON_JOB="30 2 * * * cd $PROJECT_DIR && ./scripts/renew-ssl.sh >> /var/log/ssl-renewal.log 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -F "renew-ssl.sh" > /dev/null; then
    echo -e "${YELLOW}⚠️ SSL renewal cronjob already exists. Updating...${NC}"
    # Remove existing and add new one
    (crontab -l 2>/dev/null | grep -v "renew-ssl.sh"; echo "$CRON_JOB") | crontab -
else
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
fi

echo -e "${GREEN}✅ Cronjob installed successfully!${NC}"

# Verify cron service is running
if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
    echo -e "${GREEN}✅ Cron service is running${NC}"
else
    echo -e "${YELLOW}⚠️ Cron service might not be running. Starting it...${NC}"
    if sudo systemctl start cron 2>/dev/null || sudo systemctl start crond 2>/dev/null; then
        echo -e "${GREEN}✅ Cron service started${NC}"
    else
        echo -e "${RED}❌ Failed to start cron service. Please start it manually.${NC}"
    fi
fi

echo
echo -e "${BLUE}📋 Cronjob Details:${NC}"
echo "• Schedule: Daily at 2:30 AM"
echo "• Command: cd $PROJECT_DIR && ./scripts/renew-ssl.sh"
echo "• Log file: /var/log/ssl-renewal.log"
echo "• SSL certificates will be automatically renewed before expiration"

echo
echo -e "${YELLOW}Current crontab:${NC}"
crontab -l | grep -E "(renew-ssl|#)" || crontab -l

echo
echo -e "${BLUE}📝 Useful Commands:${NC}"
echo "• View renewal logs: tail -f /var/log/ssl-renewal.log"
echo "• Test renewal: ./scripts/renew-ssl.sh"
echo "• List crontab: crontab -l"
echo "• Edit crontab: crontab -e"
echo "• Remove cronjob: crontab -e (then delete the line)"

echo
echo -e "${GREEN}🎉 SSL auto-renewal setup completed!${NC}"
