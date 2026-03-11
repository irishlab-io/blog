---
title: "Renovate: The Dependency Update Bot You Didn't Know You Needed"
date: 2026-02-28
draft: false
description: "A practical guide to Renovate, a powerful open-source alternative to Dependabot for automating dependency and configuration updates across any tech stack"
summary: "Discover how Renovate goes beyond Dependabot with rich preset configurations, monorepo support, platform-agnostic design, and fine-grained update scheduling to keep your project dependencies fresh and secure"
tags: ["security", "dependabot", "renovate", "devsecops", "ci-cd", "github", "dependency-management", "automation"]
series: ["SBOM"]
series_order: 4
---

In the previous posts, we explored how to generate SBOMs, track vulnerabilities with Dependency-Track, and automate fixes with Dependabot. Dependabot is a solid choice when you live entirely in the GitHub ecosystem, but it has real limitations: no support for GitLab or Bitbucket, a fixed configuration model, and limited flexibility for monorepos or exotic package managers. Enter [Renovate](https://docs.renovatebot.com/), an open-source dependency update tool that does everything Dependabot does and then some.

## What Is Renovate?

Renovate is a free, open-source bot that automatically raises pull requests (or merge requests) to keep your project's dependencies up to date. It was originally created by Mend (formerly WhiteSource) and is now maintained as an open-source project under the [`renovatebot/renovate`](https://github.com/renovatebot/renovate) repository.

Renovate supports:

- **30+ package managers**: `npm`, `pip`, `maven`, `gradle`, `go modules`, `cargo`, `terraform`, `helm`, `docker`, `github-actions`, and many more
- **All major platforms**: GitHub, GitLab, Bitbucket, Gitea, Azure DevOps — not just GitHub
- **Monorepo awareness**: Can manage multiple packages within a single repository with per-package configuration
- **Self-hosted or managed**: Run it yourself in your own CI or use the free [Renovate GitHub App](https://github.com/apps/renovate)

## Why Renovate Over Dependabot?

If you are already using Dependabot and it covers your needs, there is no pressing reason to switch. But Renovate earns its place in several scenarios:

| Feature | Renovate | Dependabot |
|---|---|---|
| **Platforms** | GitHub, GitLab, Bitbucket, Gitea, Azure DevOps | GitHub only |
| **Package manager support** | 30+ | ~20 |
| **Preset configuration** | Rich preset library | Limited |
| **Monorepo support** | First-class | Limited |
| **Self-hosted** | Yes (Docker, CLI, CI job) | GitHub-managed only |
| **Regex-based versioning** | Yes | No |
| **Changelog summarization** | Yes, with release notes | Yes |
| **Dashboard issue** | Built-in dependency dashboard | No |

The killer feature for most teams is the **preset system**. Instead of hand-crafting every rule, you extend community-maintained configurations that encode battle-tested best practices in a single line.

## Getting Started

### Option 1: Renovate GitHub App (Recommended for GitHub)

The easiest way to get started is to install the [Renovate GitHub App](https://github.com/apps/renovate). Once installed on your repository, Renovate opens an onboarding PR that adds a `renovate.json` configuration file. Merge it, and the bot starts working.

### Option 2: Self-Hosted via GitHub Actions

For teams that need more control or are not on GitHub, run Renovate as a scheduled GitHub Actions workflow:

```yaml
# .github/workflows/renovate.yml
name: Renovate

on:
  schedule:
    - cron: '0 2 * * 1'  # Every Monday at 02:00 UTC
  workflow_dispatch:

jobs:
  renovate:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run Renovate
        uses: renovatebot/github-action@v40
        with:
          configurationFile: renovate.json
          token: ${{ secrets.RENOVATE_TOKEN }}
```

The `RENOVATE_TOKEN` is a GitHub personal access token (or a fine-grained token) with `repo`, `workflow`, and `read:org` scopes.

## The Configuration File

All Renovate behavior is driven by `renovate.json` (or `renovate.json5`, `.renovaterc`, or a `renovate` key in `package.json`). The simplest possible configuration is:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"]
}
```

That single line inherits the [recommended preset](https://docs.renovatebot.com/presets-config/#configrecommended), which enables:

- Weekly update schedule (Monday morning)
- Semantic commit messages
- Grouping of non-major updates where sensible
- Pinning of GitHub Action SHA digests

### A Practical Configuration

Here is a more complete example that mirrors what you might use in a real project:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "schedule:weekly",
    ":automergeMinor",
    ":separatePatchReleases",
    "group:allNonMajor"
  ],
  "timezone": "America/New_York",
  "labels": ["dependencies"],
  "prConcurrentLimit": 10,
  "packageRules": [
    {
      "matchManagers": ["github-actions"],
      "groupName": "GitHub Actions",
      "automerge": true
    },
    {
      "matchManagers": ["dockerfile", "docker-compose"],
      "groupName": "Docker base images",
      "schedule": ["before 4am on Monday"]
    },
    {
      "matchManagers": ["pip_requirements", "pipenv", "poetry"],
      "groupName": "Python dependencies",
      "matchUpdateTypes": ["minor", "patch"],
      "automerge": true
    },
    {
      "matchUpdateTypes": ["major"],
      "automerge": false,
      "labels": ["dependencies", "major-update"]
    }
  ],
  "vulnerabilityAlerts": {
    "enabled": true,
    "schedule": ["at any time"]
  }
}
```

Let's break down the key settings:

- **`extends`**: Inherits reusable presets. `config:recommended` is the sensible baseline; `:automergeMinor` enables auto-merge for minor updates; `group:allNonMajor` batches minor and patch updates into a single PR per ecosystem.
- **`timezone`**: All schedule expressions are evaluated in this timezone, so `before 4am on Monday` means 4 AM Eastern, not UTC.
- **`prConcurrentLimit`**: Caps the number of open Renovate PRs at any given time, preventing your board from being flooded.
- **`packageRules`**: The heart of Renovate's flexibility. Rules are evaluated top-to-bottom and merged, allowing you to apply different strategies per ecosystem, package, or update type.
- **`vulnerabilityAlerts`**: When enabled, Renovate raises PRs immediately for packages with known CVEs, regardless of schedule. This is Renovate's equivalent of Dependabot security updates.

## The Dependency Dashboard

One of Renovate's most useful features is the **Dependency Dashboard** — an automatically maintained GitHub issue that gives you a birds-eye view of everything Renovate is tracking:

- All open update PRs and their current status
- Pending updates waiting to be triggered
- Updates being held back (e.g., major bumps requiring manual approval)
- Packages that could not be updated due to missing changelogs or conflicts

You can also trigger updates on demand directly from the dashboard by checking a checkbox, without waiting for the next scheduled run. Enable it with:

```json
{
  "dependencyDashboard": true,
  "dependencyDashboardTitle": "Renovate Dependency Dashboard"
}
```

This single feature alone can replace the need for a separate tool to track what's out of date across your project.

## Presets: Standing on the Shoulders of Giants

Renovate's preset system is what separates it from every other dependency update tool. A preset is a named, shareable configuration fragment that encodes a specific policy. The community maintains hundreds of presets in the [`renovatebot/renovate-config`](https://github.com/renovatebot/renovate-config) repository, and you can publish your own.

Useful presets to know:

| Preset | What It Does |
|---|---|
| `config:recommended` | Sensible defaults for most projects |
| `:automergeMinor` | Auto-merge minor updates when CI passes |
| `:automergePatch` | Auto-merge patch updates when CI passes |
| `schedule:weekly` | Run updates once per week |
| `schedule:monthly` | Run updates once per month |
| `group:allNonMajor` | Batch all minor + patch into one PR per manager |
| `:separatePatchReleases` | Keep patch PRs separate from minor PRs |
| `helpers:pinGitHubActionDigests` | Pin GitHub Actions to their full SHA, not a tag |

Pinning GitHub Actions to SHA digests deserves special mention. When you use `uses: actions/checkout@v4`, the `v4` tag can be moved by the repository owner at any time. Renovate's `helpers:pinGitHubActionDigests` preset automatically replaces tag references with their immutable SHA, giving you supply chain protection without the maintenance burden:

```yaml
# Before Renovate
- uses: actions/checkout@v4

# After Renovate pins it
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
```

## Monorepo Support

Renovate handles monorepos natively. If your repository contains multiple `package.json`, `pyproject.toml`, or `go.mod` files, Renovate discovers them automatically and generates PRs that update dependencies across all relevant manifests at once.

For large monorepos with hundreds of packages, you can scope updates to specific directories:

```json
{
  "ignorePaths": ["**/node_modules/**", "**/vendor/**"],
  "packageRules": [
    {
      "matchFileNames": ["services/api/**"],
      "groupName": "API service dependencies"
    },
    {
      "matchFileNames": ["services/frontend/**"],
      "groupName": "Frontend dependencies"
    }
  ]
}
```

## Auto-Merge With Safety Rails

Auto-merging is safe when you have good CI coverage. Renovate gives you several layers of control:

```json
{
  "packageRules": [
    {
      "matchUpdateTypes": ["patch"],
      "matchCurrentVersion": "!/^0/",
      "automerge": true,
      "automergeType": "pr",
      "platformAutomerge": true
    }
  ]
}
```

- **`automergeType: "pr"`**: Renovate merges via the platform's native merge button after all required checks pass, respecting your branch protection rules.
- **`platformAutomerge: true`**: Delegates merge to GitHub's auto-merge feature, so Renovate does not need to poll. The PR merges the moment the last required check turns green.
- **`matchCurrentVersion: "!/^0/"`**: Excludes `0.x` packages from auto-merge, since pre-1.0 packages often treat minor bumps as breaking changes.

## Vulnerability-Driven Updates

Like Dependabot, Renovate can react to published CVEs and raise PRs immediately rather than waiting for the weekly schedule. Enable it via:

```json
{
  "vulnerabilityAlerts": {
    "enabled": true,
    "schedule": ["at any time"],
    "labels": ["security", "vulnerability"]
  },
  "osvVulnerabilityAlerts": true
}
```

Setting `osvVulnerabilityAlerts: true` taps into the [OSV database](https://osv.dev/) (Google's open vulnerability database) in addition to GitHub's advisory database, broadening CVE coverage, especially for ecosystems like Go modules and Rust crates where OSV has better data.

## Renovate vs Dependabot: Which Should You Use?

Both tools get the job done for the most common use case — keeping GitHub-hosted repositories up to date. The decision usually comes down to platform and flexibility:

**Choose Dependabot if:**

- Your entire stack lives on GitHub
- You want zero configuration to get started
- You prefer a fully managed solution with no operational overhead

**Choose Renovate if:**

- You use GitLab, Bitbucket, or a self-hosted Git platform
- You need fine-grained control over grouping, scheduling, and auto-merge rules
- You manage monorepos with multiple ecosystems
- You want the Dependency Dashboard for a centralized update overview
- You use exotic package managers not supported by Dependabot (Helm, Gradle catalogs, `nix`, custom regex versioning)

A pragmatic middle ground: start with Dependabot if you are on GitHub (it requires zero setup), and graduate to Renovate when you hit its limits.

## Wrapping Up

Renovate is one of those tools that quietly becomes load-bearing infrastructure. Once configured, it runs weekly, raises well-organized PRs, and auto-merges the safe ones — all without any manual intervention. The Dependency Dashboard transforms the ad-hoc question "what's out of date?" into a structured, always-current list.

The key takeaways:

1. **Install the Renovate GitHub App** or run it as a scheduled GitHub Actions workflow for full control
2. **Start with `config:recommended`** and extend from there rather than hand-crafting every rule
3. **Use `packageRules`** to apply different strategies per ecosystem — auto-merge patches, hold majors for review
4. **Enable the Dependency Dashboard** for a centralized view of all pending and in-progress updates
5. **Consider `helpers:pinGitHubActionDigests`** for supply chain hardening of your CI workflows
6. **Enable `vulnerabilityAlerts`** alongside your weekly version updates for reactive CVE patching

When paired with the SBOM and Dependency-Track pipeline we built earlier in this series, Renovate closes the automated remediation loop: Dependency-Track identifies the risk, Renovate raises the fix.

---

## Resources

- [Renovate Documentation](https://docs.renovatebot.com/)
- [Renovate GitHub App](https://github.com/apps/renovate)
- [Renovate Configuration Presets](https://docs.renovatebot.com/presets-default/)
- [OSV Vulnerability Database](https://osv.dev/)
- [renovatebot/renovate on GitHub](https://github.com/renovatebot/renovate)
