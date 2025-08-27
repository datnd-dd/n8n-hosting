#!/bin/bash

# Backup script for n8n data and configurations
# Usage: ./backup.sh [backup_name]

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BACKUP_DIR="$HOME/n8n-backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${1:-n8n_backup_$DATE}"
FULL_BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

echo -e "${GREEN}📦 Starting n8n backup process${NC}"
echo "Backup will be saved to: $FULL_BACKUP_PATH"

# Create backup directory
mkdir -p "$FULL_BACKUP_PATH"

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}Error: .env file not found!${NC}"
    exit 1
fi

# Detect Docker Compose command
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}Error: Docker Compose not found${NC}"
    exit 1
fi

# Backup n8n data
echo -e "${YELLOW}📂 Backing up n8n data...${NC}"
if docker volume ls | grep -q "n8n_storage"; then
    docker run --rm \
        -v n8n_storage:/data \
        -v "$FULL_BACKUP_PATH":/backup \
        busybox tar czf /backup/n8n_data.tar.gz -C /data .
    echo "✅ n8n data backed up"
else
    echo -e "${RED}❌ n8n_storage volume not found${NC}"
fi

# Backup configuration files
echo -e "${YELLOW}📋 Backing up configuration files...${NC}"
cp -r nginx "$FULL_BACKUP_PATH/"
cp .env "$FULL_BACKUP_PATH/"
cp docker-compose.yml "$FULL_BACKUP_PATH/"
if [ -d "scripts" ]; then
    cp -r scripts "$FULL_BACKUP_PATH/"
fi
echo "✅ Configuration files backed up"

# Backup SSL certificates
echo -e "${YELLOW}🔒 Backing up SSL certificates...${NC}"
if [ -d "./certbot/conf" ]; then
    cp -r certbot "$FULL_BACKUP_PATH/"
    echo "✅ SSL certificates backed up"
else
    echo "⚠️ No SSL certificates found"
fi

# Create info file
echo -e "${YELLOW}📝 Creating backup info...${NC}"
cat > "$FULL_BACKUP_PATH/backup_info.txt" << EOF
Backup Created: $(date)
Domain: $DOMAIN
N8N Version: $(docker image ls --format "table {{.Repository}}\t{{.Tag}}" | grep n8n | head -1)
Docker Version: $(docker --version)
Docker Compose: $(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "Not found")
System: $(uname -a)
Docker Volume: n8n_storage
Services Status:
$($COMPOSE_CMD ps 2>/dev/null || echo "Services not running")
EOF

# Calculate backup size
BACKUP_SIZE=$(du -sh "$FULL_BACKUP_PATH" | cut -f1)

echo -e "${GREEN}🎉 Backup completed successfully!${NC}"
echo "Backup location: $FULL_BACKUP_PATH"
echo "Backup size: $BACKUP_SIZE"

# Optional: Create compressed archive
read -p "Create compressed archive? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🗜️ Creating compressed archive...${NC}"
    tar -czf "$BACKUP_DIR/$BACKUP_NAME.tar.gz" -C "$BACKUP_DIR" "$BACKUP_NAME"
    
    ARCHIVE_SIZE=$(du -sh "$BACKUP_DIR/$BACKUP_NAME.tar.gz" | cut -f1)
    echo -e "${GREEN}✅ Compressed archive created: $BACKUP_DIR/$BACKUP_NAME.tar.gz ($ARCHIVE_SIZE)${NC}"
    
    read -p "Remove uncompressed backup folder? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$FULL_BACKUP_PATH"
        echo "🗑️ Uncompressed backup folder removed"
    fi
fi

echo -e "${GREEN}📦 Backup process completed!${NC}"
echo
echo -e "${BLUE}📋 To restore backup:${NC}"
echo "1. Copy backup to new server"
echo "2. Extract: tar -xzf $BACKUP_NAME.tar.gz"
echo "3. Copy files to project directory"
echo "4. Run: $COMPOSE_CMD up -d"
