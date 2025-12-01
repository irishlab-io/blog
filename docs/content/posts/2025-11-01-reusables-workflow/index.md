---
title: "GitHub Actions with Reusable Workflows"
date: 2025-11-01
draft: true
description: "Lorem Ipsum"
summary: "Lorem markdownum cursu, centum est iamdudum cest tre"
tags: ["ci", "cd", "github", "actions"]
series: ["CI|CD"]
series_order: 1
---

# GitHub Actions with Reusable Workflows

In GitHub Actions, reusing workflows is a powerful way to streamline CI/CD pipelines. Instead of duplicating code across multiple workflows, reusable workflows allow you to call a pre-existing workflow from other workflows, making maintenance and updates easier, ensuring consistency, and accelerating development. This blog will explain reusable workflows, how they work, their benefits, and key differences between reusable workflows, composite actions, and workflow templates.

## What Are Reusable Workflows?

Reusable workflows enable you to call a single workflow from multiple workflows. With a reusable workflow in place, a “caller” workflow can reference it as a “called” workflow, avoiding repetitive configurations across workflows. This approach allows your team to quickly leverage workflows that are tested and proven to be reliable. With reusable workflows, we can maintain a central library of workflows that in organisations, all teams can benefit from, fostering best practices and a smoother development experience.

## Benefits of Reusable Workflows

1. Avoiding Duplication: Instead of recreating similar workflows across projects, reusable workflows allow teams to maintain a single version of shared tasks.
2. Speed and Efficiency: Reusable workflows make it quicker to set up new workflows, reducing the amount of time developers spend on configuration.
3. Consistency Across Workflows: With reusable workflows, you can ensure that best practices and standards are consistently applied.
4. Central Maintenance: Changes to a reusable workflow automatically apply to any workflow that calls it, reducing maintenance efforts and making updates seamless.

## Understanding the Caller and Called Workflows

When you set up reusable workflows, the calling workflow is known as the “caller,” while the workflow being reused is the “called” workflow. The caller workflow references the called workflow using a single line of code. For example, if a project has a standardised deployment process, you can set up a reusable workflow for deployment and then call it from each project’s workflow. This minimizes the YAML code in the caller workflow, allowing it to trigger complex sequences without having to include all steps explicitly.

## How to Implement Reusable Workflows

Reusable workflows are easy to implement:

1. Define a reusable workflow in a repository.
2. Reference it in the caller workflow using a single line.
3. Ensure access permissions are set up correctly, especially if the called workflow is in a different repository.

```yaml
jobs:
  call-deploy:
    uses: org-name/repo-name/.github/workflows/deploy.yml@main
```

In this example, the caller workflow references a reusable deployment workflow in another repository. This flexibility allows for reuse across projects.

## Workflow Accessibility Based on Repository Visibility

The accessibility of reusable workflows depends on the visibility of the host repository:

Private repositories:

- Private repositories are accessible only to specific users or teams with granted permissions.
- Accessibility:Accessible by workflows in private, internal, and public repositories.

Internal repositories:

- Internal repositories are visible only to users within the organization. They’re not visible to the public.
- Accessibility: Accessible by workflows in internal and public repositories.

Public repositories:

- Public repositories are accessible by anyone, regardless of organization membership.
- Accessibility: Accessible by any repository’s workflow.

Permissions must also be configured within GitHub Actions settings to allow the use of actions and reusable workflows. For internal or private repositories, explicitly configure access policies to permit cross-repository usage of reusable workflows.

## Create the Reusable Workflow

Below is an example of how to set up a reusable GitHub Actions workflow in Python.

First, we will define a reusable workflow in our repository. This workflow will perform common tasks like setting up Python, installing dependencies, running tests, etc.

### File Structure

You might have a file structure like this:

```yaml
my-python-project/
├── .github/
│   ├── workflows/
│   │   ├── reusable-python-workflow.yml
│   │   ├── main-workflow.yml
├── src/
│   └── your_python_code.py
├── tests/
│   └── test_your_code.py
├── requirements.txt
└── README.md
```

### Reusable Workflow Definition

Create a file named reusable-python-workflow.yml in the .github/workflows directory:

```yaml
name: Reusable Python Workflow

on:
  workflow_call:
    inputs:
      python-version:
        required: true
        type: string
      package-manager:
        required: true
        type: string
      install-args:
        required: false
        type: string
        default: ""

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v2

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ inputs.python-version }}

      - name: Install dependencies
        run: |
          if [ "${{ inputs.package-manager }}" == "pip" ]; then
            pip install -r requirements.txt ${{ inputs.install-args }}
          elif [ "${{ inputs.package-manager }}" == "poetry" ]; then
            curl -sSL https://install.python-poetry.org | python3 - --version 1.4.2
            export PATH="$HOME/.local/bin:$PATH"
            poetry install ${{ inputs.install-args }}
          fi

      - name: Run tests
        run: |
          if [ "${{ inputs.package-manager }}" == "pip" ]; then
            pytest
          elif [ "${{ inputs.package-manager }}" == "poetry" ]; then
            poetry run pytest
          fi
```

- This workflow is triggered by the workflow_call event, meaning it can be called by other workflows.
- It takes three inputs: python-version, package-manager, and install-args.
- It includes steps for checking out the repository, setting up Python, installing dependencies based on the specified package manager, and running tests.

## Use the Reusable Workflow

Now that you have defined a reusable workflow, you can call it from another workflow. Create a file named main-workflow.yml in the same directory:

```yaml
name: Main Workflow

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  call-reusable-workflow:
    uses: ./.github/workflows/reusable-python-workflow.yml
    with:
      python-version: '3.10'
      package-manager: 'pip'  # Change to 'poetry' if you are using Poetry
      install-args: ''  # Add additional install args if needed
```

- This workflow is triggered on pushes or pull requests to the main branch.
- It calls the reusable workflow, passing in the desired Python version and package manager.

## Summary

This setup allows you to maintain a single source for common workflows, making it easier to manage CI/CD processes across different projects. By defining reusable workflows, you can ensure consistency and reduce duplication of effort in your GitHub Actions setup.

---

## Refrences

1. [How to start using reusable workflows with GitHub Actions](https://github.blog/developer-skills/github/using-reusable-workflows-github-actions/)
