# n8n Quick Setup

This guide will help you set up **n8n** quickly using Docker Compose.

## Quick Setup

1. **Copy Environment File**
   Create your environment file by copying the example:

   ```bash
   cp .env.example .env
   ```

2. **Configure Environment Variables**
   Open the newly created `.env` file and set the necessary values.
   At minimum, configure:

   - **`N8N_SECURE_COOKIE`** → Ensures cookies are only sent over HTTPS (for secure sessions).
   - **`WEBHOOK_URL`** → Defines the public base URL for webhooks (important when running behind proxies/Docker).

   **Example (local development):**

   ```env
   N8N_SECURE_COOKIE=false
   WEBHOOK_URL=http://localhost
   ```

   - `N8N_SECURE_COOKIE=false` → Cookies work over plain HTTP. Fine for local testing, **not secure for production**.
   - `WEBHOOK_URL=http://localhost` → Webhook URLs will look like `http://localhost/...`. Works only on the same machine. For external access, set this to your public/reverse-proxy URL.

3. **Start n8n**
   Use the `make up` command to start n8n in detached mode:

   ```bash
   make up
   ```

   n8n will be accessible at:

   ```
   <WEBHOOK_URL>:5678
   ```

## Makefile Commands

This project includes a `Makefile` for quick setup and management of the n8n Docker environment:

- **`make up`** → Start the n8n service (detached mode).
- **`make down`** → Stop and remove the n8n service.
- **`make build`** → Build or rebuild Docker images.
- **`make logs`** → Show logs of running services in real time.

**Note**: This setup uses the default **SQLite database** (PostgreSQL is not configured).

Quick Deployment Instructions
1. Initial Setup
# Update .env with your email address

```
# Make scripts executable
chmod +x scripts/*.sh
```

2. Deploy
```
# Run the deployment script
./scripts/deploy.sh
```

3. Manual Steps (if needed)
```
# If deploy script fails, run manually:
./scripts/setup-ssl.sh
./scripts/install-cronjob.sh
```

Maintenance Commands
```
# View logs
docker-compose logs -f n8n
docker-compose logs -f nginx

# Restart services
docker-compose restart

# Create backup
./scripts/backup.sh

# Check SSL status
openssl s_client -connect <your_domain>:443 -servername <your_domain>

# Manual SSL renewal
./scripts/renew-ssl.sh
```
