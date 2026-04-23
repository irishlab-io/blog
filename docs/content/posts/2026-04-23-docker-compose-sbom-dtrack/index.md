---
title: "SBOM Before You Ship: Scanning Docker Compose Images and Publishing to Dependency-Track"
date: 2026-04-23
draft: true
description: "How to automatically generate SBOMs for every image in a Docker Compose stack and publish them to OWASP Dependency-Track before each deployment."
summary: "Learn how to wire Syft and the Dependency-Track API into your Docker Compose workflow so every service image is scanned and inventoried before docker compose up runs."
tags: ["security", "sbom", "devsecops", "docker", "docker-compose", "dependency-track", "owasp", "syft"]
series: ["SBOM"]
series_order: 3
---

In the previous posts in this series we generated SBOMs inside a CI pipeline and shipped them to [Dependency-Track](https://dependencytrack.org/) for long-term monitoring. That covers images you *build*. But what about the images you *consume*? If you run a stack with Docker Compose — a database, a reverse proxy, a message broker, a handful of off-the-shelf services — those images land on your host with zero visibility into their contents.

This post closes that gap. The goal: before `docker compose up` runs, every image referenced in your Compose file is scanned with Syft and its SBOM is published to Dependency-Track automatically.

## Why Compose Stacks Are a Blind Spot

A typical CI pipeline watches the code you write. When you `docker build`, Syft can scan the result. But Compose files are often deployment manifests that pull third-party images directly:

```yaml
services:
  db:
    image: postgres:16-alpine
  cache:
    image: redis:7-alpine
  proxy:
    image: nginx:1.27-alpine
```

None of these images go through your build pipeline. They arrive at runtime, often pinned to a floating tag like `latest` or a minor version that gets silently replaced on the next `docker pull`. You have no idea what CVEs are sitting inside them until something goes wrong.

Generating an SBOM per image and publishing it to Dependency-Track gives you:

- **Continuous visibility** — Dependency-Track re-evaluates known components daily against updated vulnerability feeds, so yesterday's clean image may surface a new CVE tomorrow.
- **Portfolio coverage** — your entire Compose stack appears as named projects in the dashboard alongside your built applications.
- **Pre-deploy gate** — the upload step happens *before* `docker compose up`, giving you an opportunity to fail the deployment if a critical policy is violated.

## Prerequisites

You need three things installed on the machine (or CI runner) that performs the deployment:

1. **Syft** — generates the SBOM from each image.
2. **curl** — uploads the SBOM to Dependency-Track (already present on most Linux hosts).
3. **Dependency-Track** running and reachable — see the [previous post](../2026-02-18-dtrack/) for a Docker Compose-based deployment.

Install Syft with the official script:

```bash
curl -sSfL https://get.anchore.io/syft | sudo sh -s -- -b /usr/local/bin
```

You also need a Dependency-Track API key with `BOM_UPLOAD` and `PROJECT_CREATION_UPLOAD` permissions. Generate one under **Administration > Access Management > Teams**.

## The Core Approach

Docker Compose ships a built-in command that lists every resolved image in a project:

```bash
docker compose config --images
```

For the example stack above this outputs:

```text
nginx:1.27-alpine
postgres:16-alpine
redis:7-alpine
```

The workflow is then:

1. Pull the resolved image list.
2. For each image, run `syft scan` and write a CycloneDX JSON SBOM.
3. Upload each SBOM to Dependency-Track using its REST API.
4. Proceed with `docker compose up`.

Steps 1–3 run *before* step 4, so the inventory is captured before any container starts.

## The Script

Save this as `scripts/compose-sbom-upload.sh` next to your Compose file:

```bash
#!/usr/bin/env bash
# Usage: ./scripts/compose-sbom-upload.sh [compose-file] [project-version]
# Requires: syft, curl, DTRACK_URL and DTRACK_API_KEY env vars

set -euo pipefail

COMPOSE_FILE="${1:-docker-compose.yml}"
PROJECT_VERSION="${2:-$(date +%Y%m%d)}"
DTRACK_URL="${DTRACK_URL:?Set DTRACK_URL to your Dependency-Track API base URL}"
DTRACK_API_KEY="${DTRACK_API_KEY:?Set DTRACK_API_KEY to your Dependency-Track API key}"
SBOM_DIR="$(mktemp -d)"

echo "==> Resolving images from ${COMPOSE_FILE}"
mapfile -t IMAGES < <(docker compose -f "${COMPOSE_FILE}" config --images | sort -u)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo "No images found in ${COMPOSE_FILE}. Exiting."
  exit 0
fi

for IMAGE in "${IMAGES[@]}"; do
  # Derive a safe project name from the image reference (strip registry/tag)
  PROJECT_NAME=$(echo "${IMAGE}" | sed 's|.*/||; s|:.*||')
  SBOM_FILE="${SBOM_DIR}/${PROJECT_NAME}.cdx.json"

  echo "==> Scanning ${IMAGE}"
  syft scan "${IMAGE}" \
    --source-name "${PROJECT_NAME}" \
    --source-version "${PROJECT_VERSION}" \
    -o cyclonedx-json="${SBOM_FILE}" \
    --quiet

  echo "    Uploading SBOM for ${PROJECT_NAME} (version ${PROJECT_VERSION})"
  HTTP_STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" \
    -X POST "${DTRACK_URL}/api/v1/bom" \
    -H "X-Api-Key: ${DTRACK_API_KEY}" \
    -F "autoCreate=true" \
    -F "projectName=${PROJECT_NAME}" \
    -F "projectVersion=${PROJECT_VERSION}" \
    -F "bom=@${SBOM_FILE}")

  if [[ "${HTTP_STATUS}" != "200" ]]; then
    echo "    ERROR: Dependency-Track returned HTTP ${HTTP_STATUS} for ${PROJECT_NAME}"
    exit 1
  fi

  echo "    Done (HTTP ${HTTP_STATUS})"
done

rm -rf "${SBOM_DIR}"
echo "==> All SBOMs uploaded. Proceeding with deployment."
```

Make it executable:

```bash
chmod +x scripts/compose-sbom-upload.sh
```

## Wiring It Into Your Deployment

### Manual deployment

Replace your usual deploy command with a two-step sequence:

```bash
export DTRACK_URL="https://dtrack.example.com"
export DTRACK_API_KEY="your-api-key"

./scripts/compose-sbom-upload.sh docker-compose.yml v1.4.2
docker compose up -d
```

### Makefile target

If you drive deployments from a `Makefile`, add a phony target that enforces the order:

```makefile
DTRACK_URL   ?= https://dtrack.example.com
COMPOSE_FILE ?= docker-compose.yml
VERSION      ?= $(shell date +%Y%m%d)

.PHONY: sbom-upload deploy

sbom-upload:
	DTRACK_API_KEY=$(DTRACK_API_KEY) \
	DTRACK_URL=$(DTRACK_URL) \
	./scripts/compose-sbom-upload.sh $(COMPOSE_FILE) $(VERSION)

deploy: sbom-upload
	docker compose -f $(COMPOSE_FILE) up -d
```

Run with `make deploy DTRACK_API_KEY=<key>`.

### CI pipeline (GitHub Actions)

If your Compose deployment is handled by a CI job, insert the SBOM step before the deploy step:

```yaml
- name: Install Syft
  run: curl -sSfL https://get.anchore.io/syft | sudo sh -s -- -b /usr/local/bin

- name: Generate and upload SBOMs
  env:
    DTRACK_URL: ${{ vars.DTRACK_URL }}
    DTRACK_API_KEY: ${{ secrets.DTRACK_API_KEY }}
  run: ./scripts/compose-sbom-upload.sh docker-compose.prod.yml ${{ github.sha }}

- name: Deploy
  run: docker compose -f docker-compose.prod.yml up -d
```

Using `github.sha` as the version means every deployment is uniquely trackable in Dependency-Track.

## What It Looks Like in Dependency-Track

After the first run, each service image appears as a separate project in the Dependency-Track dashboard:

- `postgres` — version `20260423`
- `redis` — version `20260423`
- `nginx` — version `20260423`

Each project shows its full component inventory, matched CVEs, and policy violations. Because Dependency-Track re-evaluates components daily, a vulnerability disclosed tomorrow will surface against the SBOM you uploaded today — without rerunning the scan.

If you deploy again next week with updated image tags, a new version entry is created automatically thanks to `autoCreate=true`. You get a full history of which image versions were deployed and when.

## Pitfalls and Trade-offs

**Floating tags make versioning noisy.** An image tagged `redis:7-alpine` silently changes content on every `docker pull`. Pinning images to digest — `redis@sha256:...` — gives you an immutable reference that Syft and Dependency-Track can track reliably. Consider using tools like [Renovate](../2026-02-28-renovate/) to automate digest pinning with controlled upgrade PRs.

**Scan time adds latency.** Syft needs to pull and inspect each image layer. On a cold host with no local cache this can add a few minutes per image. If deployment speed is critical, pre-pull images to warm the cache or run the SBOM step in a separate async job and gate only on failures from a previous run.

**Multi-arch images.** By default Syft scans the image variant matching the current host architecture. If your production host is `linux/amd64` but your CI runner is `linux/arm64`, the SBOMs will differ. Add `--platform linux/amd64` to the `syft scan` invocation to force a consistent target platform regardless of where the script runs.

**Built images in the same Compose file.** If your Compose file mixes `build:` services with `image:` references, `docker compose config --images` will only emit entries for services that resolve to a pullable image. Services defined with `build:` only appear after a `docker compose build`. For those, keep relying on your standard CI SBOM pipeline.

**API key exposure.** The `DTRACK_API_KEY` must be treated as a secret. Never hard-code it in the script or commit it to the repository. Use environment variables, a secrets manager, or a CI secrets store.

## Wrapping Up

Plugging a two-step SBOM generation and upload into your Docker Compose workflow takes less than an hour to set up and gives you full inventory coverage of every third-party image running in your stack. The key steps:

1. Use `docker compose config --images` to enumerate all images without parsing YAML by hand.
2. Run `syft scan` once per image and write a CycloneDX JSON file.
3. Upload each SBOM to Dependency-Track using the `/api/v1/bom` endpoint with `autoCreate=true`.
4. Only then run `docker compose up`.

From that point on, Dependency-Track monitors every component continuously. New CVEs surface automatically, policy violations can block future deployments, and you have an auditable record of exactly what was running and when.

---

## Resources

- [Syft Documentation](https://github.com/anchore/syft)
- [OWASP Dependency-Track API Documentation](https://docs.dependencytrack.org/integrations/rest-api/)
- [Dependency-Track REST API — BOM Upload](https://docs.dependencytrack.org/integrations/rest-api/)
- [CycloneDX Specification](https://cyclonedx.org/)
- [Docker Compose CLI Reference — config](https://docs.docker.com/compose/reference/config/)
