---
title: "The Robots Are Fixing My Dependencies"
date: 2026-02-20
draft: false
description: "A practical guide to implementing GitHub Dependabot for automated dependency updates across Python, GitHub Actions, and Docker ecosystems to reduce software component vulnerabilities"
summary: "Learn how to configure GitHub Dependabot to automatically detect and fix vulnerable dependencies in Python, GitHub Actions, and Docker projects with real-world configuration examples and best practices"
tags: ["security", "dependabot", "devsecops", "ci-cd", "github", "python", "docker", "vulnerability-management"]
series: ["SBOM"]
series_order: 3
---

In the previous posts, we covered how to generate SBOMs with Syft, scan them with Grype, and feed them into Dependency-Track for continuous monitoring. That pipeline tells you *what's wrong*. But knowing about vulnerabilities and actually fixing them are two very different things. The dashboards are blinking red, the Dependency-Track policies are firing alerts and now someone has to go update all those dependencies. Manually or... not.

## Enter Dependabot

[Dependabot](https://docs.github.com/en/code-security/dependabot) is GitHub's built-in automated dependency update tool. It monitors your repository's dependency manifests, checks for outdated or vulnerable packages, and opens pull requests to update them. No external service to deploy, no API keys to manage, no infrastructure to maintain it's baked directly into GitHub.

Dependabot operates in two complementary modes:

- **Security**: Triggered when the [GitHub Advisory Database](https://github.com/advisories) identifies a known vulnerability in one of your dependencies. Dependabot raises a PR to bump the package to the minimum version that includes the patch
- **Version**: Proactively checks for newer versions of your dependencies on a configurable schedule, regardless of whether a vulnerability exists. This keeps your dependency debt low and reduces the blast radius when a security update eventually lands

**Why Dependabot:**

You might be thinking, "another tool?" but Dependabot hits a sweet spot that's hard to ignore:

- **Zero infrastructure**: All repos, no feature gates, no servers, no containers, no SaaS subscriptions
- **Ecosystem breadth**: Supports 20+ package ecosystems including `pip`, `docker`, `github-actions`, `npm`, `gomod`, `terraform`, and more
- **PR-based workflow**: Updates come as pull requests that go through your existing review process, CI checks, and merge policies

When paired with the SBOM + Dependency-Track pipeline we built earlier, Dependabot closes the remediation loop. Dependency-Track identifies and tracks the risk; Dependabot proposes the fix.

## The Configuration File

All Dependabot behavior is driven by the `.github/dependabot.yml` file at the root of your repository. The structure is straightforward:

{{< github-content
    repo="irishlab-io/blog"
    path=".github/dependabot.yml"
    lang="yaml" >}}

Let's break down what this does:

- **`directory: "/"`**: Points to the directory containing the dependency manifests to monitor; useful for monorepo.
- **`schedule`**: Checks for updates every Sunday at 01:00 AM Eastern. I like to have Dependabot run on Sunday, generates a slew of PRs overnight and to start the week merging these into my codebase.  Team tends to have less work in progress early in the week making `rebase` straightforward.
- **`cooldown`**: Formally known as minimum package age, is a configuration option that allows you to specify a waiting period after a new dependency version is published before creating a pull request for it.
- **`labels`**: Tags PRs with the associated ecosystem so they're easy to filter in your project board
- **`commit-message`**: Prefixes commits with `deps` and includes the scope (`deps(deps)` for production, `deps(deps-dev)` for development), which plays nicely with conventional commit tooling
- **`groups`**: Instead of one PR per dependency, minor and patch updates are grouped by dependency type. This reduces PR noise significantly, a project with 30 dependencies won't generate 30 separate PRs
- **`ignore`**: Major version bumps are excluded from automatic updates. These often include breaking changes and should be handled manually with proper testing

**Docker Images:**

Dependabot supports both `docker` (for `Dockerfile`) and `docker-compose` (for `compose.yml`) as separate ecosystems. This is important because they have different manifest formats and update strategies.  Container base images are a massive source of vulnerabilities, as we saw in the SBOM post where an aging `python:3.10.11-alpine3.18` image had 119 known CVEs. Dependabot can monitor `Dockerfile` and `docker-compose.yml` for base image updates:

- Detect the base image tag (e.g., `python:3.12-slim`)
- Check the registry for newer tags matching the same pattern
- Open a PR to update the tag (e.g., `python:3.12-slim → python:3.13-slim`)

**Python Dependencies:**

Python projects typically rely on `requirements.txt`, `pyproject.toml`, `Pipfile`, or `setup.py` to declare dependencies. Dependabot supports all of these through the `pip` ecosystem.

Your CI pipeline runs against the PR branch exactly as it would for any human-authored PR. If tests pass, you merge. If they fail, you investigate before the vulnerable dependency reaches production. This workflow moves as follows:

- The exact version bump (e.g., `requests: 2.31.0 → 2.32.3`)
- A link to the release notes, changelog, and commits between versions
- Compatibility score based on CI results from other repositories
- For security updates: the CVE identifier, severity, and advisory link

**GitHub Actions:**

This one is often overlooked, but your CI/CD workflows are themselves a supply chain risk. Every `uses: actions/checkout@v4` line in your workflow files pins (or doesn't pin) a dependency. Compromised or outdated actions can lead to supply chain attacks, as demonstrated by the [codecov/codecov-action incident](https://about.codecov.io/security-update/) and more recently the [tj-actions incident](https://www.stepsecurity.io/blog/harden-runner-detection-tj-actions-changed-files-action-is-compromised).

## Version Update vs Security Updates

Dependabot is mostly a proactive mechanism to keep dependencies up to date with the expectation that newer version have received improvement and security fixes. Although the [`tj-actions` incident](https://www.wiz.io/blog/github-action-tj-actions-changed-files-supply-chain-attack-cve-2025-30066) demonstrate the latest is not always the best.  This is why I suggest using some `cooldown` in the configuration to reduce **too fast to merge** risk.

For **security updates** which are more reactive, you need to enable them in the GitHub repository. This will trigger Dependabot to run on new entries affecting your dependencies from the [GitHub Advisory Database](https://github.com/advisories).  I wish there were some means to integrate natively Dependency Track and Dependabot but as of today I can only see some custom API workflow could create some kind of process.  Maybe in the future.

To enable the default **security updates** in the repository GitHub change the following settings:

1. Navigate to your repository on GitHub
2. Go to **Settings > Code security**
3. Enable **Dependabot alerts** (required)
4. Enable **Dependabot security updates**

## Automating Dependabot PRs

One of the most common complaints about Dependabot is "too many PRs." The grouping feature from the configuration above helps significantly, but there are additional strategies:

- **Schedule wisely**: Weekly updates on Monday morning give you a predictable, batched workflow. Avoid `daily` unless you have a very active codebase
- **Use `open-pull-requests-limit`**: Set a reasonable cap (e.g., 10) to prevent Dependabot from overwhelming your review queue
- **Ignore major versions selectively**: Major bumps often require migration work and shouldn't be automated blindly
- **Auto-merge what you can**: Patch updates with passing CI are generally safe to merge automatically
- **Use labels and filters**: Configure meaningful labels so you can triage Dependabot PRs separately from feature work

The real power comes when you combine Dependabot with GitHub Actions to automate the merge process for low-risk updates. Dependabot can create a high number of pull requests, slowing down the team's review of **all green checks PRs**.  So automation to the rescue, here's a workflow that auto-merges patch-level Dependabot PRs once CI passes:

{{< github-content
    repo="irishlab-io/blog"
    path=".github/workflows/automerge.yml"
    lang="yaml" >}}

This workflow:

1. Triggers on every pull request
2. Checks if the PR author is Dependabot
3. Uses the official `dependabot/fetch-metadata` action to extract the update type
4. Auto-merges patch and minor updates using `gh pr merge --auto`, which waits for required status checks to pass before merging

For major version bumps, the PR stays open for manual review, exactly where you want human judgment.  Obviously, there are some risks automating dependencies **minor and patch** updates if your project has flaky tests, poor CI validation and in some cases (looking at you `tj-action`) possibly ingesting new vulnerabilities.

## Wrapping Up

Detected vulnerabilities are only useful if you act on them. Dependabot bridges the gap between *knowing* about a vulnerable dependency and *fixing* it by automating the most tedious part of supply chain security: keeping dependencies up to date.

The key takeaways:

1. **Configure `dependabot.yml`** in your repository to enable automated version updates for your ecosystem
2. **Enable security updates** in your repository settings for reactive CVE patching
3. **Group updates** to reduce PR noise while still getting the security benefits
4. **Auto-merge low-risk updates** with a simple GitHub Actions workflow
5. **Combine with Dependency-Track** for the complete detect → track → fix lifecycle

Your SBOMs tell you what's in your software. Dependency-Track tells you what's vulnerable. Dependabot fixes it. That's the closed loop.

---

## Resources

- [GitHub Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)
- [Dependabot Configuration Options Reference](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file)
- [Dependabot Supported Ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot)
- [Automating Dependabot with GitHub Actions](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/automating-dependabot-with-github-actions)
- [GitHub Advisory Database](https://github.com/advisories)
- [dependabot/fetch-metadata Action](https://github.com/dependabot/fetch-metadata)
