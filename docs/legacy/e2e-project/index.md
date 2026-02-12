---
title: "End to end Project"
date: 2025-11-01
draft: true
description: "Lorem Ipsum"
summary: "Lorem markdownum cursu, centum est iamdudum cest tre"
tags: ["example", "tag"]
---

# Overview

**Project**: End-to-End DevSecOps Project (Movies Finder)

Overview While the visible application is a React-based Movie Finder (consuming TMDB API), this project serves as a comprehensive proof-of-concept for a production-grade DevSecOps lifecycle. It demonstrates the automated delivery of a secure, tested, and monitored web application onto a baremetal Kubernetes cluster using GitOps principles.

Goal To architect a "Zero-Touch" delivery pipeline that automates the build, testing, security scanning, and deployment processes, ensuring that only high-quality, secure code reaches production without manual intervention.

## Tech Stack & Tools

- Infrastructure: Homelab, Proxmox, Talos
- GitOps: Kubernetes, Docker, Helm, ArgoCD, Sealed-Secrets
- Code: Python, Django, FastAPI
- CI/CD: GitHub Action, Commitizen, Prek
- TestingA: Pytest, Playwright (E2E)
- Security: Bandit, GitGuardian, Snyk, Syft, Grype, Trivy, OWASP ZAP
- Observability Stack: OpenTelemetry, Prometheus, Grafana, Alloy, Alertmanager, Slack
- Security (DevSecOps): , Gitleaks, , Syft (SBOM)

## Key Results & Achievements

- Optimized Release Cycle: Automated the entire delivery chain, reducing deployment turnaround time by 50% (from 40m to 20m) while adding comprehensive testing and security stages.
360° Observability: Implemented the "Grafana Alloy" & OpenTelemetry stack to correlate metrics and logs, providing real-time performance monitoring and instant Slack alerts for node resource exhaustion.
- Automated Compliance Gates: Shifted security left by integrating Trivy (container scanning) and Dependency Checkinto the CI pipeline, automatically blocking builds with critical CVEs.
- Zero-Downtime Deployment: Leveraged ArgoCD to manage state drift and ensure seamless application updates via GitOps.
