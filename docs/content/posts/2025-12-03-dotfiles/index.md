---
title: "My dotfiles"
date: 2025-12-01
draft: false
description: "Idempotent workstation setup with Ansible, WSL2, and secrets management"
summary: "A tour of my dotfiles repository: goals, structure, setup flow, and how I keep workstations reproducible with Ansible."
tags: ["ansible", "dotfiles", "linux", "wsl2", "automation", "devops"]
---

This post documents my dotfiles repository and how I use it to bootstrap and maintain Linux workstations with a strong emphasis on WSL2. The repo lives at [github.com/irish1986/dotfiles](https://github.com/irish1986/dotfiles) and focuses on repeatable, idempotent configuration using Ansible.

The core goal is simple: I want a versioned, repeatable setup for Ubuntu that I can apply to multiple machines (personal and professional), including WSL2 on Windows 11. The playbooks are written to be idempotent so I can run them anytime to reconcile drift.

## What’s inside

The repository is structured like a full configuration project rather than a single dotfiles dump:

- Ansible playbooks and roles for system configuration.
- Inventory and group variables for environment-specific customization.
- Pre and post task hooks to keep the flow modular.
- Scripts for bootstrap and maintenance tasks.
- CI automation and pre-commit checks for consistency.

My primary use case is WSL2. The README documents the flow I follow:

1. **Provision WSL2** — clean slate or fresh distro install.
2. **SSH keys** — ensure a working key in GitHub (either native WSL2 or copied from Windows).
3. **Bootstrap install** — run the setup script to initialize the environment.

The bootstrap command is in the repository `README.md` and invokes a shell script that installs dependencies and sets up the baseline playbook execution.

## The `main` playbook

Here’s the main playbook file pulled directly from the repo:

{{< github-content
    repo="irish1986/dotfiles"
    path="main.yml"
    lang="yaml" >}}

## The `roles` playbook

Every feature of my `.dotfiles` is implemented using an independent Ansible roles.  This allows me to add and remove feature fairly easily when deploying on different hardware without requiring an entire reworks of the workflows.

## Why this approach works for me

- **Idempotent** let me reapply changes safely.
- **Roles** keep responsibilities isolated and easier to evolve.
- **Automation** make onboarding fast and consistent.

---

## References

This repository is inspired by a couple of excellent projects:

- [github.com/ALT-F4-LLC/dotfiles](https://github.com/ALT-F4-LLC/dotfiles)
- [github.com/TechDufus/dotfiles](https://github.com/TechDufus/dotfiles)
