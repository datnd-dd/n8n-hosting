#!/bin/bash

# Comprehensive Test Script for N8N SSL Setup Scripts
# Tests all scripts for syntax, dependencies, and functionality
# Usage: ./test-scripts.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC} - $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    elif [ "$result" = "FAIL" ]; then
        echo -e "${RED}❌ FAIL${NC} - $test_name"
        if [ -n "$details" ]; then
            echo -e "   ${YELLOW}Details: $details${NC}"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    elif [ "$result" = "WARN" ]; then
        echo -e "${YELLOW}⚠️ WARN${NC} - $test_name"
        if [ -n "$details" ]; then
            echo -e "   ${YELLOW}Details: $details${NC}"
        fi
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${BLUE}ℹ️ INFO${NC} - $test_name"
        if [ -n "$details" ]; then
            echo -e "   ${CYAN}$details${NC}"
        fi
    fi
}

echo -e "${BLUE}🧪 N8N SSL Setup Scripts Test Suite${NC}"
echo -e "${BLUE}======================================${NC}"
echo

# Test 1: Check if we're in the right directory
echo -e "${CYAN}📁 Testing Project Structure...${NC}"

if [ -f "docker-compose.yml" ] && [ -f ".env" ]; then
    print_test_result "Project structure" "PASS" "docker-compose.yml and .env found"
else
    print_test_result "Project structure" "FAIL" "Missing docker-compose.yml or .env file"
fi

# Test 2: Check scripts directory and files
EXPECTED_SCRIPTS=(
    "scripts/backup.sh"
    "scripts/deploy.sh"
    "scripts/install-cronjob.sh"
    "scripts/renew-ssl.sh"
    "scripts/setup-ssl.sh"
)

echo -e "${CYAN}📜 Testing Script Files...${NC}"

for script in "${EXPECTED_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        print_test_result "File exists: $script" "PASS"
    else
        print_test_result "File exists: $script" "FAIL" "Script file not found"
    fi
done

# Test 3: Check script permissions
echo -e "${CYAN}🔐 Testing Script Permissions...${NC}"

for script in "${EXPECTED_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if [ -x "$script" ]; then
            print_test_result "Executable: $script" "PASS"
        else
            print_test_result "Executable: $script" "FAIL" "Script is not executable (run: chmod +x $script)"
        fi
    fi
done

# Test 4: Syntax validation
echo -e "${CYAN}🔍 Testing Script Syntax...${NC}"

for script in "${EXPECTED_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            print_test_result "Syntax check: $script" "PASS"
        else
            SYNTAX_ERROR=$(bash -n "$script" 2>&1 | head -1)
            print_test_result "Syntax check: $script" "FAIL" "$SYNTAX_ERROR"
        fi
    fi
done

# Test 5: Environment file validation
echo -e "${CYAN}⚙️ Testing Environment Configuration...${NC}"

if [ -f ".env" ]; then
    source .env
    
    # Check required variables
    if [ -n "$DOMAIN" ]; then
        print_test_result "DOMAIN variable set" "PASS" "Domain: $DOMAIN"
    else
        print_test_result "DOMAIN variable set" "FAIL" "DOMAIN not set in .env"
    fi
    
    if [ -n "$EMAIL" ]; then
        print_test_result "EMAIL variable set" "PASS" "Email: $EMAIL"
    else
        print_test_result "EMAIL variable set" "FAIL" "EMAIL not set in .env"
    fi
    
    # Validate email format
    if [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        print_test_result "EMAIL format valid" "PASS"
    else
        print_test_result "EMAIL format valid" "FAIL" "Invalid email format"
    fi
    
    # Check if N8N_PROTOCOL is https
    if [ "$N8N_PROTOCOL" = "https" ]; then
        print_test_result "N8N_PROTOCOL set to https" "PASS"
    else
        print_test_result "N8N_PROTOCOL set to https" "WARN" "Current: $N8N_PROTOCOL (should be https for SSL)"
    fi
    
    # Check WEBHOOK_URL
    if [[ "$WEBHOOK_URL" == https://* ]]; then
        print_test_result "WEBHOOK_URL uses https" "PASS"
    else
        print_test_result "WEBHOOK_URL uses https" "WARN" "Current: $WEBHOOK_URL (should use https for SSL)"
    fi
    
else
    print_test_result "Environment file exists" "FAIL" ".env file not found"
fi

# Test 6: System dependencies
echo -e "${CYAN}🛠️ Testing System Dependencies...${NC}"

REQUIRED_TOOLS=("docker" "curl" "openssl" "crontab" "nslookup")

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        VERSION_INFO=""
        case $tool in
            "docker")
                VERSION_INFO="$(docker --version 2>/dev/null | head -1)"
                ;;
            "curl")
                VERSION_INFO="$(curl --version 2>/dev/null | head -1)"
                ;;
            "openssl")
                VERSION_INFO="$(openssl version 2>/dev/null)"
                ;;
        esac
        print_test_result "$tool installed" "PASS" "$VERSION_INFO"
    else
        print_test_result "$tool installed" "FAIL" "$tool command not found"
    fi
done

# Test 7: Docker Compose version detection
echo -e "${CYAN}🐳 Testing Docker Compose...${NC}"

if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version)
    print_test_result "Docker Compose V2" "PASS" "$COMPOSE_VERSION"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version)
    print_test_result "Docker Compose V1" "WARN" "$COMPOSE_VERSION (consider upgrading to V2)"
else
    print_test_result "Docker Compose" "FAIL" "Neither 'docker compose' nor 'docker-compose' found"
fi

# Test 8: Docker permissions
if docker ps &> /dev/null; then
    print_test_result "Docker permissions" "PASS" "Can run Docker without sudo"
else
    print_test_result "Docker permissions" "FAIL" "Cannot run Docker (may need: sudo usermod -aG docker \$USER)"
fi

# Test 9: Network connectivity
echo -e "${CYAN}🌐 Testing Network Connectivity...${NC}"

if curl -s --max-time 5 https://api.ipify.org &> /dev/null; then
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org)
    print_test_result "Internet connectivity" "PASS" "Server IP: $SERVER_IP"
else
    print_test_result "Internet connectivity" "FAIL" "Cannot reach external services"
fi

# Test 10: DNS resolution (if DOMAIN is set)
if [ -n "$DOMAIN" ]; then
    if nslookup "$DOMAIN" &> /dev/null; then
        DOMAIN_IP=$(nslookup "$DOMAIN" | awk '/^Address: / { print $2 }' | tail -1)
        print_test_result "Domain DNS resolution" "PASS" "$DOMAIN resolves to $DOMAIN_IP"
        
        # Check if domain points to this server
        if [ -n "$SERVER_IP" ] && [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
            print_test_result "Domain points to this server" "PASS"
        elif [ -n "$SERVER_IP" ]; then
            print_test_result "Domain points to this server" "WARN" "Domain IP: $DOMAIN_IP, Server IP: $SERVER_IP"
        fi
    else
        print_test_result "Domain DNS resolution" "FAIL" "Cannot resolve $DOMAIN"
    fi
fi

# Test 11: Port availability
echo -e "${CYAN}🔌 Testing Port Availability...${NC}"

REQUIRED_PORTS=(80 443)

for port in "${REQUIRED_PORTS[@]}"; do
    if ! netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        print_test_result "Port $port available" "PASS"
    else
        PROCESS=$(netstat -tlnp 2>/dev/null | grep ":$port " | head -1)
        print_test_result "Port $port available" "WARN" "Port in use: $PROCESS"
    fi
done

# Test 12: Nginx configuration validation
echo -e "${CYAN}📝 Testing Nginx Configuration...${NC}"

if [ -f "nginx/conf.d/default.conf" ]; then
    print_test_result "Nginx config exists" "PASS"
    
    # Check for basic SSL configuration
    if grep -q "ssl_certificate" "nginx/conf.d/default.conf"; then
        print_test_result "SSL config in nginx" "PASS" "SSL configuration found"
    else
        print_test_result "SSL config in nginx" "WARN" "No SSL configuration found (will be created during setup)"
    fi
    
    # Check for security headers
    if grep -q "add_header" "nginx/conf.d/default.conf"; then
        HEADERS_COUNT=$(grep -c "add_header" "nginx/conf.d/default.conf")
        print_test_result "Security headers in nginx" "PASS" "$HEADERS_COUNT headers configured"
    else
        print_test_result "Security headers in nginx" "WARN" "No security headers found"
    fi
else
    print_test_result "Nginx config exists" "WARN" "Will be created during setup"
fi

# Test 13: Directory structure
echo -e "${CYAN}📂 Testing Directory Structure...${NC}"

REQUIRED_DIRS=("nginx/conf.d" "certbot/conf" "certbot/www")

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        print_test_result "Directory exists: $dir" "PASS"
    else
        print_test_result "Directory exists: $dir" "WARN" "Will be created during setup"
    fi
done

# Test 14: Script functionality tests (dry run where possible)
echo -e "${CYAN}🔧 Testing Script Functionality...${NC}"

# Test backup script help/usage
if [ -f "scripts/backup.sh" ]; then
    if grep -q "Usage:" "scripts/backup.sh"; then
        print_test_result "Backup script has usage info" "PASS"
    else
        print_test_result "Backup script has usage info" "WARN" "No usage information found"
    fi
fi

# Test if scripts have error handling (set -e)
for script in "${EXPECTED_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if grep -q "set -e" "$script"; then
            print_test_result "Error handling in $script" "PASS"
        else
            print_test_result "Error handling in $script" "WARN" "No 'set -e' found"
        fi
    fi
done

# Test 15: Security checks
echo -e "${CYAN}🔒 Testing Security Configuration...${NC}"

# Check if scripts are not world-writable
for script in "${EXPECTED_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        PERMS=$(ls -l "$script" | cut -d' ' -f1)
        if [[ ! "$PERMS" =~ w..$ ]]; then
            print_test_result "Security: $script not world-writable" "PASS"
        else
            print_test_result "Security: $script not world-writable" "FAIL" "Script is world-writable"
        fi
    fi
done

# Test 16: Log file accessibility
LOG_PATHS=("/var/log" "$HOME")

for log_path in "${LOG_PATHS[@]}"; do
    if [ -w "$log_path" ]; then
        print_test_result "Can write to $log_path" "PASS"
        break
    else
        print_test_result "Can write to $log_path" "WARN" "No write permission"
    fi
done

# Test 17: Cron service availability
if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
    print_test_result "Cron service running" "PASS"
elif command -v crontab &> /dev/null; then
    print_test_result "Cron service running" "WARN" "crontab available but service status unclear"
else
    print_test_result "Cron service running" "FAIL" "Cron not available"
fi

# Test 18: SSL Certificate directory check
if [ -d "certbot/conf/live" ] && [ "$(ls -A certbot/conf/live 2>/dev/null)" ]; then
    CERT_DOMAINS=$(ls certbot/conf/live 2>/dev/null | head -5)
    print_test_result "Existing SSL certificates" "INFO" "Found certs for: $CERT_DOMAINS"
else
    print_test_result "Existing SSL certificates" "INFO" "No existing certificates (will be created during setup)"
fi

# Test 19: Mock run test (if safe)
echo -e "${CYAN}🧪 Testing Script Mock Runs...${NC}"

# Test debug-ssl.sh if it exists
if [ -f "scripts/debug-ssl.sh" ]; then
    # We can't really run this without potentially affecting the system
    print_test_result "Debug script available" "INFO" "Use './scripts/debug-ssl.sh' for SSL debugging"
fi

# Test 20: Resource usage estimation
echo -e "${CYAN}💾 Testing System Resources...${NC}"

# Check available disk space
AVAILABLE_SPACE=$(df . | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_SPACE" -gt 1048576 ]; then  # 1GB in KB
    SPACE_GB=$((AVAILABLE_SPACE / 1048576))
    print_test_result "Sufficient disk space" "PASS" "${SPACE_GB}GB available"
else
    SPACE_MB=$((AVAILABLE_SPACE / 1024))
    print_test_result "Sufficient disk space" "WARN" "Only ${SPACE_MB}MB available"
fi

# Check memory
TOTAL_RAM=$(free -m | awk 'NR==2{printf "%.0f", $2/1024}')
if [ "$TOTAL_RAM" -gt 0 ]; then
    if [ "$TOTAL_RAM" -ge 2 ]; then
        print_test_result "Sufficient RAM" "PASS" "${TOTAL_RAM}GB RAM"
    else
        print_test_result "Sufficient RAM" "WARN" "${TOTAL_RAM}GB RAM (recommended: 2GB+)"
    fi
fi

# Summary
echo
echo -e "${BLUE}📊 Test Results Summary${NC}"
echo -e "${BLUE}=====================${NC}"
echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo
    echo -e "${GREEN}🎉 All tests passed! Your scripts are ready to use.${NC}"
    echo
    echo -e "${BLUE}🚀 Quick Start Commands:${NC}"
    echo "• Full deployment: ./scripts/deploy.sh"
    echo "• SSL only: ./scripts/setup-ssl.sh"
    echo "• Create backup: ./scripts/backup.sh"
    echo "• Install cronjob: ./scripts/install-cronjob.sh"
    
    RETURN_CODE=0
else
    echo
    echo -e "${YELLOW}⚠️ Some tests failed. Please fix the issues above before proceeding.${NC}"
    echo
    echo -e "${BLUE}🔧 Common Fixes:${NC}"
    echo "• Install missing tools: sudo apt update && sudo apt install docker.io docker-compose-plugin curl openssl"
    echo "• Fix permissions: sudo usermod -aG docker \$USER && newgrp docker"
    echo "• Make scripts executable: chmod +x scripts/*.sh"
    echo "• Update .env file with correct DOMAIN and EMAIL"
    
    RETURN_CODE=1
fi

echo
echo -e "${CYAN}📝 For detailed debugging, run:${NC}"
echo "• ./scripts/debug-ssl.sh (if SSL issues occur)"
echo "• docker compose logs (to check service logs)"
echo "• curl -I http://\$DOMAIN (to test HTTP connectivity)"

exit $RETURN_CODE
