---
title: "Self-Hosting Codecov and Integrating with GitHub Actions"
date: 2026-02-07
draft: true
description: "A comprehensive guide to deploying Codecov on your own infrastructure and integrating it with GitHub Actions pipeline"
summary: "Learn how to deploy a self-hosted Codecov instance and seamlessly integrate it with your GitHub Actions CI/CD pipeline"
tags: ["codecov", "ci", "cd", "github", "actions", "coverage", "devops", "self-hosted"]
series: ["CI|CD"]
series_order: 2
---

# Self-Hosting Codecov and Integrating with GitHub Actions

Code coverage is an essential metric in software development, helping teams understand how much of their codebase is tested. While [Codecov](https://codecov.io) offers an excellent SaaS solution, there are scenarios where hosting your own Codecov instance makes sense: data sovereignty requirements, air-gapped environments, cost optimization for large organizations, or simply having full control over your infrastructure.

This guide will walk you through deploying a self-hosted Codecov instance and integrating it with GitHub Actions to automatically upload coverage reports from your CI/CD pipeline.

## Why Self-Host Codecov?

Before diving into the implementation, let's understand when self-hosting makes sense:

1. **Data Privacy and Compliance**: Keep sensitive code coverage data within your infrastructure
2. **Air-Gapped Environments**: Deploy in networks isolated from the internet
3. **Cost Control**: For large organizations with many repositories, self-hosting can be more economical
4. **Customization**: Full control over configuration, plugins, and integrations
5. **Performance**: Reduce latency by hosting closer to your development infrastructure

## Prerequisites

Before starting, ensure you have:

- A Linux server or virtual machine (minimum 4GB RAM, 2 CPUs)
- Docker and Docker Compose installed
- PostgreSQL database (can be containerized)
- Redis instance (can be containerized)
- MinIO or S3-compatible storage for coverage reports
- GitHub App credentials for authentication
- SSL certificate for HTTPS (recommended)

## Architecture Overview

A typical self-hosted Codecov deployment consists of:

- **Worker**: Processes coverage reports
- **Web**: Serves the UI and API
- **PostgreSQL**: Stores metadata and user data
- **Redis**: Handles caching and job queues
- **MinIO/S3**: Stores coverage reports and artifacts

## Step 1: Setting Up the Infrastructure

### Docker Compose Configuration

Create a `docker-compose.yml` file for your Codecov deployment:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_USER: codecov
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: codecov
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U codecov"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ACCESS_KEY}
      MINIO_ROOT_PASSWORD: ${MINIO_SECRET_KEY}
    volumes:
      - minio_data:/data
    ports:
      - "9000:9000"
      - "9001:9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  codecov-worker:
    image: codecov/self-hosted-worker:latest
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://codecov:${POSTGRES_PASSWORD}@postgres:5432/codecov
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      MINIO_URL: http://minio:9000
      MINIO_ACCESS_KEY: ${MINIO_ACCESS_KEY}
      MINIO_SECRET_KEY: ${MINIO_SECRET_KEY}
      CODECOV_URL: ${CODECOV_URL}
    volumes:
      - ./codecov.yml:/config/codecov.yml
    restart: unless-stopped

  codecov-web:
    image: codecov/self-hosted-web:latest
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://codecov:${POSTGRES_PASSWORD}@postgres:5432/codecov
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      MINIO_URL: http://minio:9000
      MINIO_ACCESS_KEY: ${MINIO_ACCESS_KEY}
      MINIO_SECRET_KEY: ${MINIO_SECRET_KEY}
      CODECOV_URL: ${CODECOV_URL}
      GITHUB_CLIENT_ID: ${GITHUB_CLIENT_ID}
      GITHUB_CLIENT_SECRET: ${GITHUB_CLIENT_SECRET}
      SECRET_KEY: ${SECRET_KEY}
    ports:
      - "8080:8080"
    volumes:
      - ./codecov.yml:/config/codecov.yml
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
  minio_data:
```

### Environment Variables

Create a `.env` file with your configuration:

```bash
# Database
POSTGRES_PASSWORD=your_secure_postgres_password

# Redis
REDIS_PASSWORD=your_secure_redis_password

# MinIO/S3
MINIO_ACCESS_KEY=your_minio_access_key
MINIO_SECRET_KEY=your_minio_secret_key

# Codecov
CODECOV_URL=https://codecov.yourdomain.com
SECRET_KEY=your_secret_key_for_django

# GitHub App
GITHUB_CLIENT_ID=your_github_app_client_id
GITHUB_CLIENT_SECRET=your_github_app_client_secret
```

## Step 2: Creating a GitHub App

To integrate with GitHub, you need to create a GitHub App:

1. Go to your GitHub organization settings
2. Navigate to **Developer settings** > **GitHub Apps** > **New GitHub App**
3. Configure the app with these settings:
   - **GitHub App name**: Your Codecov Instance
   - **Homepage URL**: `https://codecov.yourdomain.com`
   - **Callback URL**: `https://codecov.yourdomain.com/login/github/authorized`
   - **Webhook URL**: `https://codecov.yourdomain.com/webhooks/github`
   - **Webhook secret**: Generate a secure random string

4. Set the following **Repository permissions**:
   - Contents: Read
   - Pull requests: Read & Write
   - Checks: Read & Write
   - Commit statuses: Read & Write

5. Subscribe to these **events**:
   - Pull request
   - Push
   - Repository
   - Status

6. Generate and save the **Client ID** and **Client secret**
7. Download the **Private key** (you'll need this for webhook verification)

## Step 3: Deploying Codecov

### Initialize the Database

Before starting the services, initialize the database:

```bash
# Start only PostgreSQL
docker-compose up -d postgres

# Wait for it to be healthy
docker-compose exec postgres pg_isready -U codecov

# Run migrations
docker-compose run --rm codecov-web python manage.py migrate

# Create an admin user
docker-compose run --rm codecov-web python manage.py createsuperuser
```

### Start All Services

```bash
# Start all services
docker-compose up -d

# Check logs
docker-compose logs -f codecov-web codecov-worker
```

### Configure Reverse Proxy (Nginx)

For production, use a reverse proxy with SSL:

```nginx
server {
    listen 443 ssl http2;
    server_name codecov.yourdomain.com;

    ssl_certificate /etc/nginx/ssl/codecov.crt;
    ssl_certificate_key /etc/nginx/ssl/codecov.key;

    client_max_body_size 100M;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 90;
    }
}

server {
    listen 80;
    server_name codecov.yourdomain.com;
    return 301 https://$server_name$request_uri;
}
```

## Step 4: Integrating with GitHub Actions

Now that your Codecov instance is running, integrate it with GitHub Actions.

### Generate Upload Token

1. Log into your Codecov instance at `https://codecov.yourdomain.com`
2. Add your repository
3. Navigate to the repository settings
4. Copy the **Upload Token**

### Add Token to GitHub Secrets

1. Go to your repository on GitHub
2. Navigate to **Settings** > **Secrets and variables** > **Actions**
3. Add a new secret:
   - Name: `CODECOV_TOKEN`
   - Value: Your upload token from Codecov

### GitHub Actions Workflow

Create or update your `.github/workflows/test.yml`:

```yaml
name: Test and Coverage

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.9', '3.10', '3.11']

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python ${{ matrix.python-version }}
        uses: actions/setup-python@v4
        with:
          python-version: ${{ matrix.python-version }}

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install pytest pytest-cov

      - name: Run tests with coverage
        run: |
          pytest --cov=./ --cov-report=xml --cov-report=html

      - name: Upload coverage to self-hosted Codecov
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
          url: https://codecov.yourdomain.com
          files: ./coverage.xml
          flags: unittests
          name: codecov-${{ matrix.python-version }}
          fail_ci_if_error: true
          verbose: true
```

### For Different Languages

**JavaScript/Node.js**:

```yaml
- name: Run tests with coverage
  run: |
    npm install
    npm test -- --coverage --coverageReporters=lcov

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    url: https://codecov.yourdomain.com
    files: ./coverage/lcov.info
```

**Go**:

```yaml
- name: Run tests with coverage
  run: |
    go test -v -coverprofile=coverage.out ./...

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    url: https://codecov.yourdomain.com
    files: ./coverage.out
```

**Java/Maven**:

```yaml
- name: Run tests with coverage
  run: mvn clean test jacoco:report

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    url: https://codecov.yourdomain.com
    files: ./target/site/jacoco/jacoco.xml
```

## Step 5: Codecov Configuration

Create a `codecov.yml` file in your repository root to customize behavior:

```yaml
coverage:
  precision: 2
  round: down
  range: "70...100"
  status:
    project:
      default:
        target: 80%
        threshold: 5%
        if_ci_failed: error
    patch:
      default:
        target: 80%
        threshold: 5%

comment:
  layout: "reach,diff,flags,tree,reach"
  behavior: default
  require_changes: false
  require_base: false

ignore:
  - "tests/**/*"
  - "**/__pycache__/**/*"
  - "**/node_modules/**/*"
  - "**/*.min.js"
```

## Step 6: Monitoring and Maintenance

### Health Checks

Monitor your Codecov instance with health check endpoints:

```bash
# Check web service
curl https://codecov.yourdomain.com/health

# Check worker status
docker-compose exec codecov-worker celery -A tasks status
```

### Backup Strategy

Regularly backup critical data:

```bash
#!/bin/bash
# backup-codecov.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/codecov"

# Backup PostgreSQL
docker-compose exec -T postgres pg_dump -U codecov codecov | gzip > "${BACKUP_DIR}/postgres_${DATE}.sql.gz"

# Backup MinIO data
docker run --rm \
  -v minio_data:/data \
  -v ${BACKUP_DIR}:/backup \
  alpine tar czf /backup/minio_${DATE}.tar.gz /data

# Backup configuration
tar czf "${BACKUP_DIR}/config_${DATE}.tar.gz" codecov.yml docker-compose.yml .env

# Cleanup old backups (keep last 30 days)
find ${BACKUP_DIR} -type f -mtime +30 -delete
```

### Log Management

Configure log rotation to prevent disk space issues:

```yaml
# Add to docker-compose.yml under each service
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

## Advanced Configuration

### Multiple Worker Nodes

For high-throughput environments, scale the worker:

```bash
# Scale to 3 worker instances
docker-compose up -d --scale codecov-worker=3
```

### Custom Storage Backend

If you prefer AWS S3 over MinIO:

```yaml
# In .env
AWS_ACCESS_KEY_ID=your_aws_access_key
AWS_SECRET_ACCESS_KEY=your_aws_secret_key
S3_BUCKET=your-codecov-bucket
S3_REGION=us-east-1

# In codecov-worker and codecov-web environment
STORAGE_BACKEND=s3
AWS_S3_BUCKET_NAME: ${S3_BUCKET}
AWS_S3_REGION_NAME: ${S3_REGION}
```

### SSO Integration

For enterprise environments, integrate with SAML/OAuth:

```python
# In codecov configuration
AUTHENTICATION_BACKENDS = [
    'django.contrib.auth.backends.ModelBackend',
    'social_core.backends.github.GithubOAuth2',
    'social_core.backends.okta.OktaOAuth2',
]
```

## Troubleshooting

### Common Issues

**Coverage not uploading**:

- Verify the `CODECOV_TOKEN` is correct
- Check that the `url` parameter points to your instance
- Ensure the coverage file path is correct

**Worker not processing reports**:

```bash
# Check worker logs
docker-compose logs codecov-worker

# Restart worker
docker-compose restart codecov-worker
```

**Database connection errors**:

```bash
# Verify PostgreSQL is running
docker-compose exec postgres pg_isready

# Check connection string
docker-compose exec codecov-web env | grep DATABASE_URL
```

**Authentication failures**:

- Verify GitHub App credentials are correct
- Check callback URLs match exactly
- Ensure webhook secret is configured

## Security Best Practices

1. **Use HTTPS**: Always use SSL/TLS for production deployments
2. **Rotate Secrets**: Regularly rotate database passwords, API tokens, and encryption keys
3. **Network Isolation**: Use Docker networks to isolate services
4. **Access Control**: Implement proper authentication and authorization
5. **Regular Updates**: Keep Docker images and dependencies up to date
6. **Audit Logs**: Enable and monitor audit logs for security events
7. **Backup Encryption**: Encrypt backups at rest and in transit

## Conclusion

Self-hosting Codecov gives you complete control over your code coverage infrastructure while maintaining the powerful features of Codecov. By following this guide, you've set up a production-ready Codecov instance integrated with GitHub Actions, enabling your team to track code coverage with confidence.

Key takeaways:

- Self-hosted Codecov provides data sovereignty and customization options
- Docker Compose simplifies deployment and management
- GitHub Actions integration is straightforward with the codecov-action
- Proper monitoring and backups are essential for production use
- Security should be a top priority in your deployment

As you scale, consider implementing high availability with multiple workers, database replication, and distributed storage. Monitor your instance closely and adjust resources based on your team's needs.

## References

1. [Codecov Self-Hosted Documentation](https://docs.codecov.io/docs/deploying-codecov)
2. [GitHub Actions - Codecov Action](https://github.com/codecov/codecov-action)
3. [Docker Compose Documentation](https://docs.docker.com/compose/)
4. [Creating a GitHub App](https://docs.github.com/en/developers/apps/creating-a-github-app)
5. [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
