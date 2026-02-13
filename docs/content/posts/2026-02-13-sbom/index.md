---
title: "Dr. Strangelove or: How I Learned to Stop Worrying and Love the SBOM"
date: 2026-02-13
draft: true
description: "A comprehensive guide to integrating Syft and Grype in your CI/CD pipeline to generate immutable SBOMs and upload them to your self-hosted OWASP Dependency Track instance"
summary: "Learn how to leverage Syft for SBOM generation and Grype for vulnerability scanning, while integrating with OWASP Dependency Track for comprehensive supply chain security in your CI/CD pipeline"
tags: ["security", "sbom", "devsecops", "ci-cd", "grype", "syft", "dependency-track", "owasp"]
---

Software Bill of Materials (SBOM) has become a critical component of modern software supply chain security. With increasing regulatory requirements and security concerns, organizations need to maintain accurate inventories of their software components. In this post, I'll walk you through integrating Syft and Grype into your CI/CD pipeline to generate immutable SBOMs and upload to a secure long term storage location.

## Why SBOM Matters

An SBOM is essentially an inventory of all components, libraries, and dependencies used in your software. Think of it as a "ingredients list" for your application. Key benefits include:

- **Vulnerability Management**: Quickly identify which applications are affected when new vulnerabilities are discovered
- **License Compliance**: Track open source licenses across your organization
- **Supply Chain Security**: Understand your software's dependency tree
- **Regulatory Compliance**: Meet requirements like the US Executive Order 14028, Canadian Bill C-26 and many industries standards & best practices

The primary SBOM formats, recognized for ensuring software supply chain security and interoperability, are [CycloneDX](https://cyclonedx.org/), [SPDX](https://spdx.dev/), and [SWID Tags](https://csrc.nist.gov/projects/Software-Identification-SWID). These formats enable automated, machine-readable documentation of components, licenses, and vulnerabilities.

- **CycloneDX (OWASP)**: A lightweight, modern format designed specifically for application security, vulnerability tracking, and supply chain security. It is highly versatile, supporting software, services, and hardware, and is often used within DevOps build pipelines.  CycloneDX tends to be more focused on security, vulnerability management, and ease of use in CI/CD pipelines.
- **SPDX (Linux Foundation)**: An open international standard (ISO/IEC 5962:2021) that originated for tracking software licenses but has evolved to include detailed component tracking, copyright, and security metadata.  SPDX is often favored for detailed legal compliance and intellectual property management.
- SWID Tags (ISO/IEC 19770-2): These are not full, comprehensive SBOM documents like CycloneDX or SPDX, but rather tags that provide identity and version information for software components.

## The Tools

[Syft](https://github.com/anchore/syft) is a powerful CLI tool and library for generating SBOMs from container images and filesystems. It supports multiple formats including:
[Grype](https://github.com/anchore/grype) is a vulnerability scanner that works hand-in-hand with Syft. It can scan container images, filesystems, and SBOMs to identify known vulnerabilities from multiple databases.

The quickest way to get up and going is to use Anchor helpers script.

```bash
curl -sSfL https://get.anchore.io/syft | sudo sh -s -- -b /usr/local/bin
curl -sSfL https://get.anchore.io/grype | sudo sh -s -- -b /usr/local/bin
syft version
grype version
```

**Syft:**

In order to explore SBOM we shall use an obslete and aging container.  Container binary are typically the final artefact that modern workflows push to be promote between the various environment.  Running the `syft scan docker.io/python:3.10.11-alpine3.18` will scan and generate the associated container SBOM in the terminal which is nice but not necessarily convenient.  Although we can see some of the interesting metadata from this containers.

```text
  ~ ❯ syft scan docker.io/python:3.10.11-alpine3.18
 ✔ Loaded image          index.docker.io/library/python:3.10.11-alpine3.18
 ✔ Parsed image          sha256:bee261a96575c66a0d892947a6d7803348f49aa8734bc4a0ecb1df96c34d8134
 ✔ Cataloged contents    b42d5a5a34e11c7014e0bbb647f2b6970b2047043f19de43ce0d787a87091eb1
   ├── ✔ Packages                        [56 packages]
   ├── ✔ Executables                     [144 executables]
   ├── ✔ File metadata                   [1,030 locations]
   └── ✔ File digests                    [1,030 files]
NAME                    VERSION           TYPE
.python-rundeps         20230511.234154   apk
Simple Launcher         1.1.0.14          binary  (+5 duplicates)
alpine-baselayout       3.4.3-r1          apk
alpine-baselayout-data  3.4.3-r1          apk
alpine-keys             2.4-r1            apk
apk-tools               2.14.0-r0         apk
busybox                 1.36.0-r9         apk
busybox-binsh           1.36.0-r9         apk
ca-certificates         20230506-r0       apk
ca-certificates-bundle  20230506-r0       apk
cli                     UNKNOWN           binary
cli-32                  UNKNOWN           binary
cli-64                  UNKNOWN           binary
and many more...
```

Let's now generate an `sbom.json` file that we could store, analyze and evaluate for vulnerabilities using this command `syft scan docker.io/python:3.10.11-alpine3.18 -o cyclonedx-json=./sbom.json`.  Two (2) differents SBOM standards are commonly in used:

**Grype:**

```yaml
name: SBOM Generation and Vulnerability Scanning

on:
```

## CI/CD Integration

Now let's integrate Syft and Grype into your pipeline. I'll show examples for both GitHub Actions and GitLab CI.

### GitHub Actions

Create `.github/workflows/sbom-scanning.yml`:

```yaml
name: SBOM Generation and Vulnerability Scanning

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    # Run daily at 2 AM UTC
    - cron: '0 2 * * *'

env:
  DEPENDENCY_TRACK_URL: https://dependency-track.your-domain.com
  PROJECT_NAME: my-application
  PROJECT_VERSION: ${{ github.sha }}

jobs:
  sbom-and-scan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          load: true
          tags: ${{ env.PROJECT_NAME }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Install Syft
        uses: anchore/sbom-action/download-syft@v0.15.8

      - name: Generate SBOM with Syft
        run: |
          # Generate SBOM in CycloneDX JSON format
          syft packages ${{ env.PROJECT_NAME }}:${{ github.sha }} \
            -o cyclonedx-json \
            --file sbom-cyclonedx.json

          # Also generate in SPDX format for backup
          syft packages ${{ env.PROJECT_NAME }}:${{ github.sha }} \
            -o spdx-json \
            --file sbom-spdx.json

      - name: Upload SBOM to Dependency Track
        env:
          DEPENDENCY_TRACK_API_KEY: ${{ secrets.DEPENDENCY_TRACK_API_KEY }}
        run: |
          # Encode SBOM in base64
          SBOM_BASE64=$(cat sbom-cyclonedx.json | base64 -w 0)

          # Upload to Dependency Track
          curl -X PUT "${{ env.DEPENDENCY_TRACK_URL }}/api/v1/bom" \
            -H "Content-Type: application/json" \
            -H "X-Api-Key: $DEPENDENCY_TRACK_API_KEY" \
            -d "{
              \"project\": \"${{ env.PROJECT_NAME }}\",
              \"projectVersion\": \"${{ env.PROJECT_VERSION }}\",
              \"autoCreate\": true,
              \"bom\": \"$SBOM_BASE64\"
            }"

      - name: Install Grype
        uses: anchore/scan-action/download-grype@v3

      - name: Scan for vulnerabilities with Grype
        run: |
          grype ${{ env.PROJECT_NAME }}:${{ github.sha }} \
            -o json \
            --file grype-results.json \
            --fail-on critical

          # Also generate SARIF format for GitHub Security
          grype ${{ env.PROJECT_NAME }}:${{ github.sha }} \
            -o sarif \
            --file grype-results.sarif

      - name: Upload Grype results to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: grype-results.sarif

      - name: Archive SBOM artifacts
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: sbom-${{ github.sha }}
          path: |
            sbom-*.json
            grype-results.*
          retention-days: 90

      - name: Comment PR with scan results
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const results = JSON.parse(fs.readFileSync('grype-results.json', 'utf8'));

            const critical = results.matches.filter(m => m.vulnerability.severity === 'Critical').length;
            const high = results.matches.filter(m => m.vulnerability.severity === 'High').length;
            const medium = results.matches.filter(m => m.vulnerability.severity === 'Medium').length;
            const low = results.matches.filter(m => m.vulnerability.severity === 'Low').length;

            const comment = `## 🔍 Vulnerability Scan Results

            | Severity | Count |
            |----------|-------|
            | 🔴 Critical | ${critical} |
            | 🟠 High | ${high} |
            | 🟡 Medium | ${medium} |
            | 🟢 Low | ${low} |

            **SBOM Generated**: ✅
            **Uploaded to Dependency Track**: ✅

            View full details in [Dependency Track](${{ env.DEPENDENCY_TRACK_URL }})`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: comment
            });
```

### GitLab CI

Create or update `.gitlab-ci.yml`:

```yaml
stages:
  - build
  - security
  - upload

variables:
  DEPENDENCY_TRACK_URL: "https://dependency-track.your-domain.com"
  PROJECT_NAME: "my-application"
  DOCKER_IMAGE: "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}"
  SYFT_VERSION: "v0.100.0"
  GRYPE_VERSION: "v0.74.0"

build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t ${DOCKER_IMAGE} .
    - docker save ${DOCKER_IMAGE} -o image.tar
  artifacts:
    paths:
      - image.tar
    expire_in: 1 hour

generate-sbom:
  stage: security
  image: alpine:latest
  before_script:
    - apk add --no-cache curl
    - |
      # Install Syft
      curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin ${SYFT_VERSION}
  script:
    - |
      # Generate SBOM from saved image
      syft packages oci-archive:image.tar \
        -o cyclonedx-json \
        --file sbom-cyclonedx.json

      syft packages oci-archive:image.tar \
        -o spdx-json \
        --file sbom-spdx.json
  artifacts:
    paths:
      - sbom-*.json
    reports:
      cyclonedx: sbom-cyclonedx.json
    expire_in: 90 days

vulnerability-scan:
  stage: security
  image: alpine:latest
  dependencies:
    - build
  before_script:
    - apk add --no-cache curl
    - |
      # Install Grype
      curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin ${GRYPE_VERSION}
  script:
    - |
      # Scan for vulnerabilities
      grype oci-archive:image.tar \
        -o json \
        --file grype-results.json

      # Check for critical vulnerabilities
      CRITICAL=$(cat grype-results.json | grep -o '"severity":"Critical"' | wc -l)
      echo "Found $CRITICAL critical vulnerabilities"

      if [ $CRITICAL -gt 0 ]; then
        echo "❌ Build failed due to critical vulnerabilities"
        exit 1
      fi
  artifacts:
    paths:
      - grype-results.json
    expire_in: 90 days
  allow_failure: false

upload-to-dependency-track:
  stage: upload
  image: alpine:latest
  dependencies:
    - generate-sbom
  before_script:
    - apk add --no-cache curl jq coreutils
  script:
    - |
      # Encode SBOM in base64
      SBOM_BASE64=$(cat sbom-cyclonedx.json | base64 -w 0)

      # Upload to Dependency Track
      RESPONSE=$(curl -X PUT "${DEPENDENCY_TRACK_URL}/api/v1/bom" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: ${DEPENDENCY_TRACK_API_KEY}" \
        -d "{
          \"project\": \"${PROJECT_NAME}\",
          \"projectVersion\": \"${CI_COMMIT_SHA}\",
          \"autoCreate\": true,
          \"bom\": \"${SBOM_BASE64}\"
        }")

      echo "Upload response: $RESPONSE"

      # Extract token for tracking
      TOKEN=$(echo $RESPONSE | jq -r '.token')
      echo "Upload token: $TOKEN"

      # Wait for processing (optional)
      sleep 10

      echo "✅ SBOM uploaded successfully to Dependency Track"
  only:
    - main
    - develop
    - tags
```

## Advanced Configuration

### Making SBOMs Immutable

To ensure SBOMs are immutable and traceable:

1. **Version Pinning**: Use specific commit SHAs or semantic versions
2. **Artifact Storage**: Store SBOMs in artifact repositories (e.g., Artifactory, Nexus)
3. **Signing**: Sign SBOMs with GPG or Cosign for integrity verification

Example with Cosign:

```bash
# Generate SBOM
syft packages myimage:latest -o cyclonedx-json --file sbom.json

# Sign the SBOM
cosign sign-blob --key cosign.key sbom.json > sbom.json.sig

# Upload both to artifact storage
curl -X PUT "https://artifactory.example.com/sboms/${PROJECT}/${VERSION}/sbom.json" \
  --upload-file sbom.json

curl -X PUT "https://artifactory.example.com/sboms/${PROJECT}/${VERSION}/sbom.json.sig" \
  --upload-file sbom.json.sig
```

### Customizing Syft Output

Syft allows you to customize what's included in the SBOM:

```bash
# Include only production dependencies
syft packages . \
  -o cyclonedx-json \
  --exclude '**/test/**' \
  --exclude '**/tests/**'

# Specify package catalogers
syft packages . \
  -o cyclonedx-json \
  --catalogers python,javascript,go
```

### Grype Custom Policies

Create a `.grype.yaml` file for custom scanning policies:

```yaml
# .grype.yaml
ignore:
  # Ignore specific CVEs with justification
  - vulnerability: CVE-2023-12345
    fix-state: wont-fix
    reason: "Not applicable to our use case"

  # Ignore by package
  - package:
      name: "lodash"
      version: "4.17.15"

# Fail on specific severities
fail-on-severity: high

# Configure matchers
match:
  python:
    using-cpes: true
  java:
    using-cpes: true
```

### Monitoring with Dependency Track

Set up automated alerts in Dependency Track:

1. Navigate to Notifications in the admin panel
2. Configure webhooks for:
   - New vulnerabilities discovered
   - Policy violations
   - SBOM upload failures
3. Integrate with Slack, Teams, or PagerDuty

Example webhook payload processing:

```python
# webhook_handler.py
from flask import Flask, request
import requests

app = Flask(__name__)

@app.route('/dependency-track-webhook', methods=['POST'])
def handle_webhook():
    data = request.json

    if data['notification']['level'] == 'INFORMATIONAL':
        severity = '🔵'
    elif data['notification']['level'] == 'WARNING':
        severity = '🟡'
    elif data['notification']['level'] == 'ERROR':
        severity = '🔴'

    message = f"{severity} Dependency Track Alert\n"
    message += f"Project: {data['subject']['project']['name']}\n"
    message += f"Title: {data['notification']['title']}\n"
    message += f"Content: {data['notification']['content']}"

    # Send to Slack
    requests.post(SLACK_WEBHOOK_URL, json={'text': message})

    return 'OK', 200

if __name__ == '__main__':
    app.run(port=5000)
```

## Best Practices

### 1. Generate SBOMs at Build Time

Always generate SBOMs during the build process, not deployment. This ensures consistency and prevents tampering.

### 2. Store SBOMs with Artifacts

Keep SBOMs alongside your container images:

```bash
# Tag and push image
docker tag myapp:${VERSION} registry.example.com/myapp:${VERSION}
docker push registry.example.com/myapp:${VERSION}

# Generate and upload SBOM
syft packages registry.example.com/myapp:${VERSION} -o cyclonedx-json --file sbom.json
curl -X PUT "https://registry.example.com/sboms/myapp/${VERSION}" \
  --upload-file sbom.json
```

### 3. Automate Regular Scans

Don't just scan on commits - run scheduled scans to catch newly discovered vulnerabilities:

```yaml
# GitHub Actions scheduled scan
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
```

### 4. Define Clear Policies

Establish policies for:

- Acceptable vulnerability severities
- Required remediation timeframes
- License compliance requirements
- Approval workflows for exceptions

### 5. Integrate with Development Workflow

Make SBOM generation visible to developers:

- Show vulnerability counts in PRs
- Block merges on critical vulnerabilities
- Provide actionable remediation guidance

## Troubleshooting

### Common Issues

**Issue**: "Unable to connect to Dependency Track"

```bash
# Test connectivity
curl -v https://dependency-track.your-domain.com/api/version

# Verify API key
curl https://dependency-track.your-domain.com/api/v1/project \
  -H "X-Api-Key: ${DEPENDENCY_TRACK_API_KEY}"
```

**Issue**: "SBOM upload fails silently"

```bash
# Check Dependency Track logs
docker logs dependency-track-apiserver

# Validate SBOM format
cat sbom.json | jq '.'
```

**Issue**: "Grype fails with database errors"

```bash
# Update Grype database
grype db update

# Use specific database
grype image:latest --db /path/to/custom/db
```

## Conclusion

Integrating Syft and Grype with OWASP Dependency Track provides a robust, self-hosted solution for software supply chain security. This setup gives you:

- ✅ Automated SBOM generation for every build
- ✅ Continuous vulnerability scanning
- ✅ Centralized visibility across all projects
- ✅ Complete control over your security data
- ✅ Compliance with regulatory requirements

The initial setup requires some effort, but the long-term benefits in security posture, compliance, and incident response capabilities are well worth it. Start with a single project, refine your pipeline, and gradually roll it out across your organization.

## Resources

- [Syft Documentation](https://github.com/anchore/syft)
- [Grype Documentation](https://github.com/anchore/grype)
- [OWASP Dependency Track](https://dependencytrack.org/)
- [NTIA SBOM Minimum Elements](https://www.ntia.gov/report/2021/minimum-elements-software-bill-materials-sbom)
- [CycloneDX Specification](https://cyclonedx.org/)
- [SPDX Specification](https://spdx.dev/)

Happy securing! 🔒
