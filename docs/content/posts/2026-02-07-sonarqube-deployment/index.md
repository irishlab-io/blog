---
title: "Deploying SonarQube CE on Your Infrastructure with GitHub Integration"
date: 2026-02-07
draft: true
description: "A comprehensive guide to deploying SonarQube Community Edition on your own infrastructure and integrating it with GitHub organizations and repositories"
summary: "Learn how to deploy SonarQube CE on your infrastructure and seamlessly integrate it with your GitHub organizations for effective code quality management across your team"
tags: ["sonarqube", "github", "devsecops", "code-quality", "ci", "cd"]
series: ["DevSecOps"]
series_order: 2
---

# Deploying SonarQube CE on Your Infrastructure with GitHub Integration

SonarQube Community Edition (CE) is a powerful open-source platform for continuous inspection of code quality. It performs automatic reviews with static analysis to detect bugs, code smells, and security vulnerabilities across 30+ programming languages. In this guide, I'll walk you through deploying SonarQube CE on your own infrastructure and integrating it seamlessly with your GitHub organizations and repositories.

## Why Self-Host SonarQube?

Before diving into the deployment, let's understand why you might want to self-host SonarQube CE:

1. **Data Control**: Keep your code analysis data within your infrastructure
2. **Cost Effective**: Free for unlimited private repositories
3. **Customization**: Full control over configuration and plugins
4. **Compliance**: Meet organizational security and compliance requirements
5. **Integration Flexibility**: Deep integration with your existing CI/CD pipelines

## Prerequisites

Before we begin, ensure you have:

- A server with at least 4GB RAM and 2 CPU cores (8GB RAM recommended for larger projects)
- Docker and Docker Compose installed
- A PostgreSQL database (we'll set this up with Docker)
- A GitHub organization or repository with admin access
- A reverse proxy (optional but recommended for HTTPS)
- Domain name pointing to your server (optional)

## Architecture Overview

Our setup will consist of:

1. **SonarQube Server**: The main application server
2. **PostgreSQL Database**: For storing analysis results and configuration
3. **GitHub Integration**: Using GitHub Apps for seamless authentication and PR decoration
4. **CI/CD Integration**: GitHub Actions workflows for automatic analysis

## Step 1: Deploy SonarQube with Docker Compose

First, let's create a Docker Compose configuration for SonarQube and PostgreSQL.

Create a directory for your deployment:

```bash
mkdir -p ~/sonarqube-deployment
cd ~/sonarqube-deployment
```

Create a `docker-compose.yml` file:

```yaml
version: "3.8"

services:
  sonarqube:
    image: sonarqube:community
    container_name: sonarqube
    depends_on:
      - db
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: sonar_password
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_extensions:/opt/sonarqube/extensions
      - sonarqube_logs:/opt/sonarqube/logs
    ports:
      - "9000:9000"
    restart: unless-stopped
    ulimits:
      nofile:
        soft: 65536
        hard: 65536

  db:
    image: postgres:15-alpine
    container_name: sonarqube-db
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: sonar_password
      POSTGRES_DB: sonar
    volumes:
      - postgresql_data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  sonarqube_data:
  sonarqube_extensions:
  sonarqube_logs:
  postgresql_data:
```

Before starting, configure system settings (required for Elasticsearch):

```bash
# Set vm.max_map_count for the current session
sudo sysctl -w vm.max_map_count=524288

# Make it permanent
echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
```

Now start the services:

```bash
docker-compose up -d
```

Wait a few minutes for SonarQube to start, then access it at `http://your-server:9000`. The default credentials are:

- Username: `admin`
- Password: `admin`

**Important**: Change the default password immediately after first login!

## Step 2: Configure Reverse Proxy with HTTPS (Optional but Recommended)

For production use, you should run SonarQube behind a reverse proxy with HTTPS. Here's an example using Traefik:

```yaml
version: "3.8"

services:
  sonarqube:
    image: sonarqube:community
    container_name: sonarqube
    depends_on:
      - db
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: ${DB_PASSWORD}
      SONAR_WEB_CONTEXT: /
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_extensions:/opt/sonarqube/extensions
      - sonarqube_logs:/opt/sonarqube/logs
    restart: unless-stopped
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.sonarqube.rule=Host(`sonar.yourdomain.com`)"
      - "traefik.http.routers.sonarqube.entrypoints=websecure"
      - "traefik.http.routers.sonarqube.tls.certresolver=letsencrypt"
      - "traefik.http.services.sonarqube.loadbalancer.server.port=9000"

  db:
    image: postgres:15-alpine
    container_name: sonarqube-db
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: sonar
    volumes:
      - postgresql_data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  sonarqube_data:
  sonarqube_extensions:
  sonarqube_logs:
  postgresql_data:
```

Create a `.env` file to store sensitive information:

```bash
DB_PASSWORD=your_secure_password_here
```

## Step 3: Create a GitHub App for Integration

The best way to integrate SonarQube with GitHub is using a GitHub App. This provides better security and more granular permissions than personal access tokens.

### Create the GitHub App

Follow these steps to create a GitHub App:

1. Go to your GitHub organization settings
2. Navigate to **Settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**
3. Fill in the following details:

   **Basic Information:**

   - **GitHub App name**: `SonarQube Code Analysis` (or your preferred name)
   - **Homepage URL**: `https://sonar.yourdomain.com` (your SonarQube URL)
   - **Webhook URL**: `https://sonar.yourdomain.com/github-webhook/` (note the trailing slash)
   - **Webhook secret**: Generate a random string (save this for later)

   **Permissions:**

   Repository permissions:

   - **Checks**: Read & write (for PR decoration)
   - **Contents**: Read (for accessing code)
   - **Metadata**: Read (required)
   - **Pull requests**: Read & write (for PR comments)
   - **Commit statuses**: Read & write (for status checks)

   Organization permissions:

   - **Members**: Read (for user mapping)

   **Subscribe to events:**

   - Pull request
   - Push

4. Click **Create GitHub App**
5. Generate a private key (save the downloaded `.pem` file securely)
6. Note the **App ID** (you'll need this)

### Install the GitHub App

1. From your GitHub App page, click **Install App**
2. Choose your organization
3. Select repositories:
   - **All repositories** (recommended for organization-wide use)
   - Or select specific repositories
4. Click **Install**

## Step 4: Configure SonarQube GitHub Integration

Now let's configure SonarQube to use the GitHub App:

1. Log in to SonarQube as an administrator
2. Navigate to **Administration** → **Configuration** → **General Settings** → **ALM Integrations** → **GitHub**

3. Add a new GitHub configuration:
   - **Configuration Name**: `GitHub` (or your preferred name)
   - **GitHub API URL**: `https://api.github.com` (for GitHub.com) or your GitHub Enterprise URL
   - **GitHub App ID**: The App ID from your GitHub App
   - **Client ID**: From your GitHub App settings
   - **Client Secret**: Generate this in your GitHub App settings
   - **Private Key**: Paste the contents of the `.pem` file you downloaded
   - **Webhook Secret**: The webhook secret you generated earlier

4. Click **Save**

## Step 5: Create a Project in SonarQube

1. In SonarQube, click **Create Project**
2. Select **GitHub**
3. Choose your GitHub configuration
4. Select the organization and repository you want to analyze
5. Click **Set Up**

SonarQube will:

- Create the project
- Configure the quality gate
- Set up PR decoration
- Generate an authentication token

## Step 6: Set Up GitHub Actions for Automatic Analysis

Create a GitHub Actions workflow to automatically analyze your code on every push and pull request.

Create `.github/workflows/sonarqube.yml` in your repository:

```yaml
name: SonarQube Analysis

on:
  push:
    branches:
      - main
      - develop
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  sonarqube:
    name: SonarQube Scan
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Shallow clones should be disabled for better analysis

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Cache SonarQube packages
        uses: actions/cache@v4
        with:
          path: ~/.sonar/cache
          key: ${{ runner.os }}-sonar
          restore-keys: ${{ runner.os }}-sonar

      - name: SonarQube Scan
        uses: sonarsource/sonarqube-scan-action@master
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
        with:
          args: >
            -Dsonar.projectKey=your-project-key
            -Dsonar.organization=your-org

      - name: SonarQube Quality Gate check
        uses: sonarsource/sonarqube-quality-gate-action@master
        timeout-minutes: 5
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
```

### Add GitHub Secrets

In your GitHub repository, add the following secrets:

1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Add the following repository secrets:
   - `SONAR_TOKEN`: The token generated by SonarQube
   - `SONAR_HOST_URL`: Your SonarQube URL (e.g., `https://sonar.yourdomain.com`)

## Step 7: Configure Quality Gates and Rules

Quality Gates determine whether your code meets your quality standards:

1. In SonarQube, go to **Quality Gates**
2. Either use the default "Sonar way" quality gate or create a custom one
3. Customize conditions based on your requirements:
   - Coverage on new code
   - Duplicated lines on new code
   - Maintainability rating on new code
   - Reliability rating on new code
   - Security rating on new code
   - Security hotspots reviewed

Example custom quality gate conditions:

```text
Coverage on New Code >= 80%
Duplicated Lines on New Code <= 3%
Maintainability Rating on New Code = A
Reliability Rating on New Code = A
Security Rating on New Code = A
Security Hotspots Reviewed = 100%
```

## Step 8: Enable PR Decoration

PR decoration allows SonarQube to comment directly on pull requests with analysis results:

1. Ensure your GitHub App has the correct permissions (set in Step 3)
2. In SonarQube project settings, go to **General Settings** → **Pull Request Decoration**
3. Verify that your GitHub configuration is selected
4. Enable **Decorate Pull Requests**

Now when you create a pull request, SonarQube will:

- Add inline comments on issues found in the changed code
- Post a summary comment with the quality gate status
- Update the PR status check

## Step 9: Team Onboarding and Best Practices

To ensure seamless usage across your team:

### User Authentication

Configure GitHub authentication for your team:

1. In SonarQube, go to **Administration** → **Security** → **Authentication**
2. Enable **GitHub** authentication
3. Configure the GitHub OAuth app (or use the GitHub App authentication)
4. Team members can now log in using their GitHub accounts

### Access Control

Set up appropriate permissions:

1. Create user groups in SonarQube (e.g., `developers`, `leads`, `admins`)
2. Map GitHub teams to SonarQube groups
3. Assign permissions:
   - **Browse**: All team members
   - **Execute Analysis**: CI/CD service accounts
   - **Administer**: Project leads
   - **Administer System**: Platform team

### Branch Analysis

Configure branch analysis for better workflow integration:

```yaml
# In your sonarqube.yml workflow
name: SonarQube Branch Analysis

on:
  push:
    branches:
      - '**'  # Analyze all branches
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: SonarQube Scan
        uses: sonarsource/sonarqube-scan-action@master
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
```

### Best Practices for Your Team

1. **Code Review Integration**: Make SonarQube quality gate a required check before merging PRs
2. **Fix Issues Before New Code**: Encourage fixing issues in new code immediately
3. **Regular Housekeeping**: Schedule time to address technical debt
4. **Custom Rules**: Define organization-specific coding standards
5. **Training**: Ensure team members understand how to interpret and fix issues
6. **Metrics Visibility**: Display quality metrics on dashboards

## Step 10: Advanced Configuration

### Multi-Language Support

SonarQube CE supports multiple languages out of the box. For specific languages, you may need additional configuration:

**For JavaScript/TypeScript projects:**

```yaml
- name: Install dependencies
  run: npm ci

- name: SonarQube Scan
  uses: sonarsource/sonarqube-scan-action@master
  env:
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
    SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
  with:
    args: >
      -Dsonar.sources=src
      -Dsonar.tests=tests
      -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info
```

**For Python projects:**

```yaml
- name: Set up Python
  uses: actions/setup-python@v5
  with:
    python-version: '3.11'

- name: Install dependencies
  run: |
    pip install -r requirements.txt
    pip install coverage pytest

- name: Run tests with coverage
  run: |
    coverage run -m pytest
    coverage xml

- name: SonarQube Scan
  uses: sonarsource/sonarqube-scan-action@master
  env:
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
    SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
  with:
    args: >
      -Dsonar.python.coverage.reportPaths=coverage.xml
```

**For Java/Maven projects:**

```yaml
- name: Set up JDK
  uses: actions/setup-java@v4
  with:
    java-version: '17'
    distribution: 'temurin'

- name: Build and analyze
  run: |
    mvn clean verify sonar:sonar \
      -Dsonar.projectKey=${{ secrets.SONAR_PROJECT_KEY }} \
      -Dsonar.host.url=${{ secrets.SONAR_HOST_URL }} \
      -Dsonar.login=${{ secrets.SONAR_TOKEN }}
```

### Monorepo Configuration

For monorepo setups, you can configure multiple projects:

```properties
# sonar-project.properties at root
sonar.projectKey=my-monorepo
sonar.organization=my-org

# Module configuration
sonar.modules=frontend,backend,shared

# Frontend module
frontend.sonar.projectName=Frontend
frontend.sonar.sources=packages/frontend/src
frontend.sonar.tests=packages/frontend/tests

# Backend module
backend.sonar.projectName=Backend
backend.sonar.sources=packages/backend/src
backend.sonar.tests=packages/backend/tests
```

### Performance Tuning

Optimize SonarQube for better performance:

```yaml
# docker-compose.yml
services:
  sonarqube:
    environment:
      # Increase memory for larger projects
      SONAR_WEB_JAVAADDITIONALOPTS: "-Xmx2g -Xms512m"
      SONAR_CE_JAVAADDITIONALOPTS: "-Xmx2g -Xms512m"
      SONAR_SEARCH_JAVAADDITIONALOPTS: "-Xmx1g -Xms512m"
```

## Monitoring and Maintenance

### Backup Strategy

Implement regular backups:

```bash
#!/bin/bash
# backup-sonarqube.sh

BACKUP_DIR="/backups/sonarqube"
DATE=$(date +%Y%m%d_%H%M%S)

# Backup database
docker exec sonarqube-db pg_dump -U sonar sonar > $BACKUP_DIR/db_$DATE.sql

# Backup SonarQube data
docker run --rm -v sonarqube_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/data_$DATE.tar.gz /data

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
```

Add to crontab:

```bash
0 2 * * * /path/to/backup-sonarqube.sh
```

### Health Checks

Monitor SonarQube health:

```bash
# Check SonarQube status
curl -s https://sonar.yourdomain.com/api/system/health | jq

# Check database connection
docker exec sonarqube-db pg_isready -U sonar
```

### Upgrading SonarQube

To upgrade to a newer version:

```bash
# Backup first!
./backup-sonarqube.sh

# Update docker-compose.yml with new version
# For example: sonarqube:community -> sonarqube:10.8-community

# Pull new image and restart
docker-compose pull
docker-compose up -d

# Check logs
docker-compose logs -f sonarqube
```

## Troubleshooting Common Issues

### Issue: "Elasticsearch: Max virtual memory areas vm.max_map_count is too low"

**Solution:**

```bash
sudo sysctl -w vm.max_map_count=524288
echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
```

### Issue: GitHub PR decoration not working

**Checklist:**

1. Verify GitHub App permissions are correct
2. Check webhook secret matches
3. Ensure GitHub App is installed on the repository
4. Verify private key is correctly configured
5. Check SonarQube logs for webhook errors

### Issue: Analysis failing in GitHub Actions

**Common causes:**

1. Missing or incorrect `SONAR_TOKEN`
2. Invalid `SONAR_HOST_URL`
3. Network issues accessing SonarQube
4. Quality gate timeout

**Debug steps:**

```yaml
- name: Debug SonarQube connection
  run: |
    curl -v ${{ secrets.SONAR_HOST_URL }}/api/system/status
```

### Issue: High memory usage

**Solutions:**

1. Increase container memory limits
2. Optimize analysis scope (exclude unnecessary files)
3. Reduce concurrent analyses
4. Upgrade to a server with more resources

## Security Considerations

1. **Use HTTPS**: Always run SonarQube behind HTTPS in production
2. **Secure Secrets**: Store tokens and credentials securely (GitHub Secrets, HashiCorp Vault, etc.)
3. **Regular Updates**: Keep SonarQube and all components updated
4. **Network Segmentation**: Restrict access to SonarQube server
5. **Audit Logs**: Enable and monitor audit logs
6. **Access Control**: Implement principle of least privilege
7. **Database Security**: Use strong passwords and restrict database access

## Conclusion

You now have a fully functional SonarQube CE deployment integrated with your GitHub organization. This setup provides:

✅ Automated code quality analysis on every push and PR
✅ Inline PR comments highlighting issues
✅ Quality gate enforcement before merging
✅ Team-wide visibility into code quality metrics
✅ Centralized configuration and management

### Next Steps

1. **Customize Quality Gates**: Adjust thresholds based on your team's standards
2. **Create Organization Standards**: Define custom rules for your specific needs
3. **Set Up Dashboards**: Create custom dashboards for different stakeholders
4. **Integrate with Other Tools**: Connect SonarQube with Jira, Slack, or other tools
5. **Educate Your Team**: Conduct training sessions on using SonarQube effectively
6. **Monitor Trends**: Track quality metrics over time and celebrate improvements

### Additional Resources

- [SonarQube Documentation](https://docs.sonarqube.org/latest/)
- [SonarQube Community Forum](https://community.sonarsource.com/)
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [SonarQube Best Practices](https://docs.sonarqube.org/latest/analysis/overview/)

## References

1. [SonarQube Official Documentation](https://docs.sonarqube.org/latest/)
2. [GitHub Apps Documentation](https://docs.github.com/en/apps)
3. [SonarQube GitHub Integration](https://docs.sonarqube.org/latest/analysis/github-integration/)
4. [Docker Compose Documentation](https://docs.docker.com/compose/)
5. [SonarQube Scanner for GitHub Actions](https://github.com/SonarSource/sonarqube-scan-action)

---

*Have questions or suggestions about this guide? Feel free to reach out or leave a comment below!*
