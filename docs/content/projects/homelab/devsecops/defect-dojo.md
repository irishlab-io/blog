---
date: 2026-02-07T15:26:15Z
lastmod: 2026-02-07T15:26:15Z
publishdate: 2026-02-07T15:26:15Z
draft: false

title: "Deploying DefectDojo with Docker and Integrations"
description: "A comprehensive guide to deploying DefectDojo using Docker on your own infrastructure and integrating it with GitHub, SonarQube, and OWASP Dependency Track"
author:
  - irish1986

weight: 1
---

# Deploying DefectDojo with Docker and Integrations

DefectDojo is an open-source vulnerability management tool that helps security teams track and manage security findings from various security scanners in a centralized location. In this guide, I'll walk you through deploying DefectDojo using Docker on your own infrastructure and integrating it with GitHub organizations, SonarQube, and OWASP Dependency Track.

## Prerequisites

Before starting, ensure you have:

- Docker and Docker Compose installed
- At least 4GB of RAM available for the DefectDojo containers
- A domain name (optional, for HTTPS configuration)
- Access tokens for GitHub, SonarQube, and OWASP Dependency Track

## Deploying DefectDojo with Docker

### Step 1: Prepare the Environment

Create a directory for DefectDojo and navigate into it:

```bash
mkdir -p /opt/stacks/defectdojo
cd /opt/stacks/defectdojo
```

### Step 2: Create Docker Compose Configuration

Create a `compose.yml` file with the following configuration:

```yaml
---
version: '3.8'

services:
  nginx:
    image: defectdojo/defectdojo-nginx:latest
    container_name: defectdojo-nginx
    depends_on:
      - uwsgi
    environment:
      NGINX_METRICS_ENABLED: "${NGINX_METRICS_ENABLED:-false}"
    ports:
      - "${DD_PORT:-8080}:8080"
      - "${DD_TLS_PORT:-8443}:8443"
    volumes:
      - defectdojo_media:/usr/share/nginx/html/media
    restart: unless-stopped

  uwsgi:
    image: defectdojo/defectdojo-django:latest
    container_name: defectdojo-uwsgi
    depends_on:
      - postgres
      - redis
    entrypoint: ['/wait-for-it.sh', 'postgres:5432', '-t', '30', '--', '/entrypoint-uwsgi.sh']
    environment:
      DD_DEBUG: 'False'
      DD_DJANGO_ADMIN_ENABLED: 'True'
      DD_ALLOWED_HOSTS: "${DD_ALLOWED_HOSTS:-*}"
      DD_DATABASE_URL: "postgresql://${DD_DATABASE_USER}:${DD_DATABASE_PASSWORD}@postgres:5432/${DD_DATABASE_NAME}"
      DD_CELERY_BROKER_URL: "redis://redis:6379/0"
      DD_SECRET_KEY: "${DD_SECRET_KEY}"
      DD_CREDENTIAL_AES_256_KEY: "${DD_CREDENTIAL_AES_256_KEY}"
      DD_SITE_URL: "${DD_SITE_URL:-http://localhost:8080}"
      DD_SESSION_COOKIE_SECURE: "${DD_SESSION_COOKIE_SECURE:-False}"
      DD_CSRF_COOKIE_SECURE: "${DD_CSRF_COOKIE_SECURE:-False}"
    volumes:
      - defectdojo_media:/app/media
    restart: unless-stopped

  celerybeat:
    image: defectdojo/defectdojo-django:latest
    container_name: defectdojo-celerybeat
    depends_on:
      - postgres
      - redis
    entrypoint: ['/wait-for-it.sh', 'postgres:5432', '-t', '30', '--', '/entrypoint-celery-beat.sh']
    environment:
      DD_DATABASE_URL: "postgresql://${DD_DATABASE_USER}:${DD_DATABASE_PASSWORD}@postgres:5432/${DD_DATABASE_NAME}"
      DD_CELERY_BROKER_URL: "redis://redis:6379/0"
      DD_SECRET_KEY: "${DD_SECRET_KEY}"
      DD_CREDENTIAL_AES_256_KEY: "${DD_CREDENTIAL_AES_256_KEY}"
    restart: unless-stopped

  celeryworker:
    image: defectdojo/defectdojo-django:latest
    container_name: defectdojo-celeryworker
    depends_on:
      - postgres
      - redis
    entrypoint: ['/wait-for-it.sh', 'postgres:5432', '-t', '30', '--', '/entrypoint-celery-worker.sh']
    environment:
      DD_DATABASE_URL: "postgresql://${DD_DATABASE_USER}:${DD_DATABASE_PASSWORD}@postgres:5432/${DD_DATABASE_NAME}"
      DD_CELERY_BROKER_URL: "redis://redis:6379/0"
      DD_SECRET_KEY: "${DD_SECRET_KEY}"
      DD_CREDENTIAL_AES_256_KEY: "${DD_CREDENTIAL_AES_256_KEY}"
    restart: unless-stopped

  initializer:
    image: defectdojo/defectdojo-django:latest
    container_name: defectdojo-initializer
    depends_on:
      - postgres
    entrypoint: ['/wait-for-it.sh', 'postgres:5432', '--', '/entrypoint-initializer.sh']
    environment:
      DD_DATABASE_URL: "postgresql://${DD_DATABASE_USER}:${DD_DATABASE_PASSWORD}@postgres:5432/${DD_DATABASE_NAME}"
      DD_ADMIN_USER: "${DD_ADMIN_USER:-admin}"
      DD_ADMIN_MAIL: "${DD_ADMIN_MAIL:-admin@defectdojo.local}"
      DD_ADMIN_PASSWORD: "${DD_ADMIN_PASSWORD}"
      DD_SECRET_KEY: "${DD_SECRET_KEY}"
      DD_CREDENTIAL_AES_256_KEY: "${DD_CREDENTIAL_AES_256_KEY}"
    restart: "no"

  postgres:
    image: postgres:16-alpine
    container_name: defectdojo-postgres
    environment:
      POSTGRES_DB: "${DD_DATABASE_NAME}"
      POSTGRES_USER: "${DD_DATABASE_USER}"
      POSTGRES_PASSWORD: "${DD_DATABASE_PASSWORD}"
    volumes:
      - defectdojo_postgres:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: defectdojo-redis
    volumes:
      - defectdojo_redis:/data
    restart: unless-stopped

volumes:
  defectdojo_media:
  defectdojo_postgres:
  defectdojo_redis:
```

### Step 3: Create Environment File

Create a `.env` file with your configuration:

```bash
# Database Configuration
DD_DATABASE_NAME=defectdojo
DD_DATABASE_USER=defectdojo
DD_DATABASE_PASSWORD=your-secure-database-password

# DefectDojo Configuration
DD_ADMIN_USER=admin
DD_ADMIN_MAIL=admin@yourdomain.com
DD_ADMIN_PASSWORD=your-secure-admin-password
DD_SECRET_KEY=your-secret-key-generate-a-long-random-string
DD_CREDENTIAL_AES_256_KEY=your-256-bit-key-exactly-32-characters

# Site Configuration
DD_SITE_URL=http://localhost:8080
DD_ALLOWED_HOSTS=*
DD_PORT=8080
DD_TLS_PORT=8443

# Security Settings (set to True if using HTTPS)
DD_SESSION_COOKIE_SECURE=False
DD_CSRF_COOKIE_SECURE=False
```

**Important**: Generate secure random strings for `DD_SECRET_KEY` and `DD_CREDENTIAL_AES_256_KEY`:

```bash
# Generate DD_SECRET_KEY (any length)
openssl rand -base64 48

# Generate DD_CREDENTIAL_AES_256_KEY (must be exactly 32 characters/256 bits)
openssl rand -base64 32 | cut -c1-32
```

### Step 4: Deploy DefectDojo

Start the DefectDojo stack:

```bash
docker compose up -d
```

Wait for the initializer to complete (this may take a few minutes on first run):

```bash
docker compose logs -f initializer
```

Once initialization is complete, access DefectDojo at `http://localhost:8080` (or your configured URL).

### Step 5: Initial Login

Log in with the credentials you set in the `.env` file:
- Username: `admin` (or your configured `DD_ADMIN_USER`)
- Password: Your configured `DD_ADMIN_PASSWORD`

## Integrating with GitHub

DefectDojo can integrate with GitHub to automatically import security findings from GitHub Advanced Security and manage vulnerabilities for your repositories.

### Step 1: Create a GitHub Personal Access Token

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a descriptive name like "DefectDojo Integration"
4. Select the following scopes:
   - `repo` (Full control of private repositories)
   - `read:org` (Read org and team membership)
   - `security_events` (Read and write security events)
5. Click "Generate token" and copy the token

### Step 2: Configure GitHub Integration in DefectDojo

1. Navigate to **Configuration** → **Tool Configuration**
2. Click **Add Tool Configuration**
3. Fill in the details:
   - **Name**: GitHub Integration
   - **Tool Type**: GitHub
   - **URL**: https://api.github.com
   - **API Key**: Paste your GitHub Personal Access Token
4. Click **Submit**

### Step 3: Create a Product for Your GitHub Organization

1. Navigate to **Products** → **Add Product**
2. Fill in the product details:
   - **Name**: Your GitHub Organization Name
   - **Description**: GitHub repositories security findings
   - **Product Type**: Select appropriate type
3. Click **Submit**

### Step 4: Set Up Automated Imports

Create an engagement for automated imports:

1. Navigate to your product and click **Add Engagement**
2. Set up the engagement details
3. Under **Tests**, create a new test
4. Select **GitHub Vulnerability** as the scan type
5. Configure the tool configuration you created earlier

### Step 5: Configure GitHub Actions (Optional)

To automatically send scan results to DefectDojo from GitHub Actions, create a workflow:

```yaml
name: Security Scan to DefectDojo

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run security scan
        run: |
          # Your security scanning tool (e.g., Trivy, Bandit, etc.)
          # Generate report in JSON format
          
      - name: Upload to DefectDojo
        env:
          DEFECTDOJO_URL: ${{ secrets.DEFECTDOJO_URL }}
          DEFECTDOJO_API_KEY: ${{ secrets.DEFECTDOJO_API_KEY }}
        run: |
          curl -X POST "${DEFECTDOJO_URL}/api/v2/import-scan/" \
            -H "Authorization: Token ${DEFECTDOJO_API_KEY}" \
            -F "scan_type=Your Scanner Type" \
            -F "file=@scan-results.json" \
            -F "engagement=YOUR_ENGAGEMENT_ID" \
            -F "active=true" \
            -F "verified=false"
```

## Integrating with SonarQube

SonarQube is a code quality and security analysis platform. DefectDojo can import findings from SonarQube to provide a unified view of vulnerabilities.

### Step 1: Generate SonarQube API Token

1. Log in to your SonarQube instance
2. Navigate to **My Account** → **Security**
3. Under **Tokens**, enter a name (e.g., "DefectDojo") and click **Generate**
4. Copy the generated token

### Step 2: Configure SonarQube Integration in DefectDojo

1. In DefectDojo, navigate to **Configuration** → **Tool Configuration**
2. Click **Add Tool Configuration**
3. Fill in the details:
   - **Name**: SonarQube Integration
   - **Tool Type**: SonarQube
   - **URL**: Your SonarQube instance URL (e.g., https://sonarqube.yourdomain.com)
   - **API Key**: Paste your SonarQube API token
4. Click **Submit**

### Step 3: Import SonarQube Findings

You can import SonarQube findings in two ways:

#### Option 1: Manual Import

1. In SonarQube, navigate to your project
2. Download the issues report (you can use the SonarQube API)
3. In DefectDojo, navigate to your product/engagement
4. Click **Import Scan Results**
5. Select **SonarQube Scan** as the scan type
6. Upload the exported file
7. Click **Submit**

#### Option 2: Automated Import via API

Create a script to automatically fetch and import SonarQube findings:

```bash
#!/bin/bash

# Configuration
SONARQUBE_URL="https://sonarqube.yourdomain.com"
SONARQUBE_TOKEN="your-sonarqube-token"
SONARQUBE_PROJECT="your-project-key"

DEFECTDOJO_URL="http://localhost:8080"
DEFECTDOJO_TOKEN="your-defectdojo-api-token"
ENGAGEMENT_ID="your-engagement-id"

# Fetch SonarQube issues
curl -u "${SONARQUBE_TOKEN}:" \
  "${SONARQUBE_URL}/api/issues/search?componentKeys=${SONARQUBE_PROJECT}&types=VULNERABILITY,BUG,CODE_SMELL&resolved=false" \
  -o sonarqube-report.json

# Import to DefectDojo
curl -X POST "${DEFECTDOJO_URL}/api/v2/import-scan/" \
  -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
  -F "scan_type=SonarQube API Import" \
  -F "file=@sonarqube-report.json" \
  -F "engagement=${ENGAGEMENT_ID}" \
  -F "active=true" \
  -F "verified=false"

# Cleanup
rm sonarqube-report.json
```

### Step 4: Schedule Regular Imports

You can schedule this script to run periodically using cron:

```bash
# Edit crontab
crontab -e

# Add entry to run daily at 2 AM
0 2 * * * /path/to/sonarqube-import.sh >> /var/log/sonarqube-import.log 2>&1
```

## Integrating with OWASP Dependency Track

OWASP Dependency Track is a Software Composition Analysis (SCA) platform that identifies and manages risks in the software supply chain.

### Step 1: Generate Dependency Track API Key

1. Log in to your OWASP Dependency Track instance
2. Navigate to **Administration** → **Access Management** → **Teams**
3. Select or create a team
4. Under **API Keys**, click **Generate** or use an existing key
5. Copy the API key

### Step 2: Configure Dependency Track in DefectDojo

1. In DefectDojo, navigate to **Configuration** → **Tool Configuration**
2. Click **Add Tool Configuration**
3. Fill in the details:
   - **Name**: Dependency Track Integration
   - **Tool Type**: Dependency Track
   - **URL**: Your Dependency Track instance URL (e.g., https://dependencytrack.yourdomain.com)
   - **API Key**: Paste your Dependency Track API key
4. Click **Submit**

### Step 3: Set Up Bidirectional Integration

#### A. Send Findings from Dependency Track to DefectDojo

Configure Dependency Track to send notifications to DefectDojo:

1. In Dependency Track, navigate to **Administration** → **Notifications**
2. Click **Create Notification**
3. Configure the notification:
   - **Name**: DefectDojo Integration
   - **Scope**: Select appropriate scope (Portfolio, Project, etc.)
   - **Level**: Select notification level
   - **Publisher**: Select **Webhook**
   - **Destination**: `http://defectdojo:8080/api/v2/import-scan/`
   - **Template**: Configure the payload template

#### B. Import Dependency Track Findings into DefectDojo

Create a script to import findings from Dependency Track:

```bash
#!/bin/bash

# Configuration
DT_URL="https://dependencytrack.yourdomain.com"
DT_API_KEY="your-dependency-track-api-key"
DT_PROJECT_UUID="your-project-uuid"

DEFECTDOJO_URL="http://localhost:8080"
DEFECTDOJO_TOKEN="your-defectdojo-api-token"
ENGAGEMENT_ID="your-engagement-id"

# Fetch findings from Dependency Track
curl -X GET "${DT_URL}/api/v1/finding/project/${DT_PROJECT_UUID}" \
  -H "X-Api-Key: ${DT_API_KEY}" \
  -H "Accept: application/json" \
  -o dt-findings.json

# Import to DefectDojo
curl -X POST "${DEFECTDOJO_URL}/api/v2/import-scan/" \
  -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
  -F "scan_type=Dependency Track Finding Packaging Format (FPF) Export" \
  -F "file=@dt-findings.json" \
  -F "engagement=${ENGAGEMENT_ID}" \
  -F "active=true" \
  -F "verified=false"

# Cleanup
rm dt-findings.json
```

### Step 4: Automate SBOM Upload to Dependency Track

If you're generating SBOMs (Software Bill of Materials) in your CI/CD pipeline, you can automatically upload them to Dependency Track:

```yaml
# GitHub Actions example
- name: Generate SBOM
  run: |
    # Example using syft
    syft . -o cyclonedx-json > sbom.json

- name: Upload to Dependency Track
  env:
    DT_URL: ${{ secrets.DEPENDENCY_TRACK_URL }}
    DT_API_KEY: ${{ secrets.DEPENDENCY_TRACK_API_KEY }}
    DT_PROJECT_UUID: ${{ secrets.DT_PROJECT_UUID }}
  run: |
    curl -X POST "${DT_URL}/api/v1/bom" \
      -H "X-Api-Key: ${DT_API_KEY}" \
      -H "Content-Type: multipart/form-data" \
      -F "project=${DT_PROJECT_UUID}" \
      -F "bom=@sbom.json"
```

## Advanced Configuration

### Setting Up HTTPS with Traefik

If you're using Traefik as a reverse proxy, you can configure HTTPS for DefectDojo:

```yaml
# Add to docker-compose.yml under nginx service
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.defectdojo.rule=Host(`defectdojo.yourdomain.com`)"
  - "traefik.http.routers.defectdojo.entrypoints=https"
  - "traefik.http.routers.defectdojo.tls=true"
  - "traefik.http.routers.defectdojo.tls.certresolver=cloudflare"
  - "traefik.http.services.defectdojo.loadbalancer.server.port=8080"
```

### Backup and Restore

#### Backup DefectDojo Data

```bash
#!/bin/bash
BACKUP_DIR="/opt/backups/defectdojo"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p ${BACKUP_DIR}

# Backup PostgreSQL database
docker exec defectdojo-postgres pg_dump -U defectdojo defectdojo > ${BACKUP_DIR}/defectdojo_db_${DATE}.sql

# Backup media files
docker run --rm -v defectdojo_media:/data -v ${BACKUP_DIR}:/backup alpine tar czf /backup/media_${DATE}.tar.gz -C /data .

echo "Backup completed: ${DATE}"
```

#### Restore DefectDojo Data

```bash
#!/bin/bash
BACKUP_DIR="/opt/backups/defectdojo"
DB_BACKUP="defectdojo_db_20260207_120000.sql"
MEDIA_BACKUP="media_20260207_120000.tar.gz"

# Restore database
cat ${BACKUP_DIR}/${DB_BACKUP} | docker exec -i defectdojo-postgres psql -U defectdojo defectdojo

# Restore media files
docker run --rm -v defectdojo_media:/data -v ${BACKUP_DIR}:/backup alpine tar xzf /backup/${MEDIA_BACKUP} -C /data

echo "Restore completed"
```

### Monitoring and Maintenance

#### Health Check Script

```bash
#!/bin/bash
DEFECTDOJO_URL="http://localhost:8080"

# Check if DefectDojo is responding
if curl -f -s -o /dev/null "${DEFECTDOJO_URL}/login"; then
    echo "DefectDojo is healthy"
    exit 0
else
    echo "DefectDojo is not responding"
    exit 1
fi
```

#### Update DefectDojo

To update DefectDojo to the latest version:

```bash
cd /opt/stacks/defectdojo

# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Check logs
docker compose logs -f
```

## Best Practices

1. **Secure Your Secrets**: Store sensitive information like API keys and passwords in a secure vault (e.g., HashiCorp Vault, AWS Secrets Manager)

2. **Regular Backups**: Implement automated daily backups of both the database and media files

3. **Use HTTPS**: Always use HTTPS in production environments to protect sensitive security data

4. **Access Control**: Implement proper role-based access control (RBAC) in DefectDojo to limit who can view and modify findings

5. **Regular Updates**: Keep DefectDojo and all integrations updated to the latest versions to benefit from security patches and new features

6. **Monitor Resource Usage**: DefectDojo can be resource-intensive with large datasets. Monitor CPU, memory, and disk usage regularly

7. **Automated Imports**: Set up automated imports from all your security tools to ensure findings are always up-to-date

8. **Finding Deduplication**: Configure DefectDojo's deduplication settings to avoid duplicate findings across multiple scans

9. **SLA Configuration**: Set up Service Level Agreements (SLAs) for different finding severities to ensure timely remediation

10. **Integration Testing**: Regularly test your integrations to ensure they're working correctly and findings are being imported properly

## Troubleshooting

### Common Issues

#### Container Won't Start

Check logs:
```bash
docker compose logs uwsgi
docker compose logs postgres
```

Ensure environment variables are set correctly in `.env` file.

#### Database Connection Issues

Verify PostgreSQL is running:
```bash
docker compose ps postgres
docker exec defectdojo-postgres pg_isready -U defectdojo
```

#### API Authentication Failures

1. Generate a new API token in DefectDojo:
   - Navigate to **API v2 Key (Token Auth)**
   - Click **Generate**
2. Update your integration scripts with the new token

#### Memory Issues

If experiencing out-of-memory errors, increase Docker memory limits or add swap space:

```yaml
# Add to services in compose.yml
services:
  uwsgi:
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G
```

## Conclusion

DefectDojo provides a centralized platform for managing security findings from multiple sources. By deploying it with Docker and integrating it with GitHub, SonarQube, and OWASP Dependency Track, you create a comprehensive security vulnerability management system that helps you track, prioritize, and remediate security issues across your entire infrastructure.

The integrations enable you to:
- Automatically import security findings from multiple sources
- Correlate and deduplicate findings
- Track remediation progress
- Generate compliance reports
- Set SLAs for vulnerability remediation

With proper configuration and maintenance, DefectDojo becomes an essential tool in your DevSecOps toolkit, helping you shift security left and maintain a strong security posture across all your projects.

## Additional Resources

- [DefectDojo Official Documentation](https://documentation.defectdojo.com/)
- [DefectDojo GitHub Repository](https://github.com/DefectDojo/django-DefectDojo)
- [DefectDojo Docker Deployment Guide](https://github.com/DefectDojo/django-DefectDojo/tree/master/docker)
- [OWASP Dependency Track Documentation](https://docs.dependencytrack.org/)
- [SonarQube API Documentation](https://docs.sonarqube.org/latest/extend/web-api/)
- [GitHub Security Features](https://docs.github.com/en/code-security)
