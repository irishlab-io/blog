---
title: "Git Best Practices for GitHub"
date: 2026-01-10
draft: true
description: "A practical guide to Git workflows, branching strategies, commit hygiene, and collaboration patterns on GitHub"
summary: "Establishing solid Git practices is one of the highest-leverage investments a team can make. This post covers branching strategies, commit conventions, pull request discipline, and repository hygiene for teams working on GitHub."
tags: ["git", "github", "devops", "automation", "development-workflow"]
---

Version control is the backbone of modern software development, and Git is the tool most teams rely on daily. Yet many teams treat Git as a simple save button rather than a precision instrument for collaboration. Poor habits compound quickly: unclear commit histories, tangled branches, broken main lines, and merge conflicts that consume entire afternoons.

This post lays out the practices I follow and recommend for teams working with Git on GitHub. These are not theoretical ideals; they are patterns born from real projects where things went wrong and lessons were learned the hard way.

## Branching Strategy

Choosing the right branching model depends on team size, release cadence, and project maturity. The two most common strategies are [`gitflow`](https://nvie.com/posts/a-successful-git-branching-model/), a bit outdated nowadays but still functionnal, and [`trunk-based development`](https://trunkbaseddevelopment.com/), which has been adopted by more and more teams.  I might do a deep dive eventually on each of these but regardless of which branching strategy you pick for your team; the goal is to pick one.

Given, I often work alone on my side project, I use my own personnaly twist branching strategy which use a little bit of both.

- The only long-lived branch I maintain is `main` (I avoid `master` for PC reason) which represent my production code.
- Short-lived branches would be prefixed like `feat/`, `fix/`, `docs/`, and `chore/` communicate intent at a glance.
- Fast-track branch is prefixed with  `hotfix/` which by-pass some steps in the Ci pipeline but require approval to merge.  **To be use in extreme situation only.**

## Commit Hygiene

A commit history is a communication tool. When written well, it tells the story of how and why the codebase evolved. When written poorly, it becomes noise that nobody reads.  This is why, I extensively use the [Conventional Commits](https://www.conventionalcommits.org/) specification provides a structured format for commit messages:

```text
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

This makes reviewing a project `git log` clear and easy, intents of changes can be understood at a glances and some automation can be initiated for it.

- **Automated Changelogs**: become possible when commit messages follow a predictable format
- **Semantic Versioning**: can be derived from commit types (`feat` = minor bump, `fix` = patch bump, `BREAKING CHANGE` footer = major bump)
- **Code Review**: is faster when reviewers can scan commit messages and immediately understand the scope and intention of each change

## Pull Request Discipline

Pull requests are where collaboration happens on GitHub. A well-structured PR accelerates review; a poorly structured one stalls the entire team.  All changes to the code `main` branch must go trhough a PR which includes automation to ensure code quality, security checks and peer reviews therefore no commit can be pushed on the `main` directly, for all team members.

Large Pull Requests are where productivity goes to die. Research from the engineering team at Google suggests that review quality drops sharply above 200 lines of change. Aim for pull requests that:

- Address a single concern
- Can be reviewed in under 30 minutes
- Include fewer than 400 lines of diff (excluding generated files)

If the feature is large, break it into a series of stacked PRs or use feature flags to merge incremental progress safely.  This can be encourage using a pull request template ensures every PR carries the context a reviewer needs and help the developper create meaningful PR.

### Atomic Commits

Each commit should represent a single logical change. Resist the temptation to bundle unrelated modifications into a single commit.  Reviewing a log full of `docs: update README.md` that

Atomic commits make `git bisect` useful, make reverts surgical, and make code review manageable.

### Code Review Culture

Code review is not about gatekeeping. It is about shared understanding and collective code ownership. A few guidelines that improve review culture:

- **Review promptly.** Blocked PRs block people. Aim to provide initial feedback within a few hours, not days.
- **Be specific.** "This could be better" is not actionable. "Consider extracting this into a helper function to reduce duplication with the handler on line 45" is.
- **Distinguish between blocking and non-blocking feedback.** Use prefixes like `nit:` for style suggestions and `blocking:` for issues that must be resolved before merge.
- **Approve when satisfied, not when perfect.** Perfect is the enemy of shipped.

### Required Reviews and Branch Protection

GitHub branch protection rules enforce review discipline at the platform level. At a minimum, configure:

- Require at least one approving review before merge
- Require status checks (CI) to pass before merge
- Require branches to be up to date before merge
- Dismiss stale reviews when new commits are pushed
- Restrict who can push directly to `main`

These rules eliminate an entire class of mistakes by making the risky path harder than the safe path.

## Repository Hygiene

A clean repository communicates professionalism and makes onboarding faster.

### The README

Every repository needs a `README.md` that answers:

- What does this project do?
- How do I set it up locally?
- How do I run the tests?
- How do I contribute?
- Who maintains this project?

If a new team member cannot go from clone to running tests in under 15 minutes by following the README, the README needs work.

### .gitignore

Maintain a thorough `.gitignore` from day one. GitHub provides excellent starter templates at [github.com/github/gitignore](https://github.com/github/gitignore). Common categories to exclude:

- Build artifacts and compiled output
- IDE and editor configuration files
- OS-specific files (`.DS_Store`, `Thumbs.db`)
- Dependency directories (`node_modules/`, `__pycache__/`, `.venv/`)
- Environment files containing secrets (`.env`)

### CODEOWNERS

The `CODEOWNERS` file maps file patterns to responsible teams or individuals. When a pull request touches files matching a pattern, the designated owners are automatically requested for review:

```text
# Default owner for everything
* @org/platform-team

# Frontend specialists own the UI
/src/frontend/ @org/frontend-team

# Security team must review auth changes
/src/auth/ @org/security-team

# DevOps owns infrastructure config
/infrastructure/ @org/devops-team
```

This ensures the right people see the right changes without manual assignment.

### Issue and PR Labels

A consistent labeling system helps with triage, filtering, and reporting. A baseline set of labels:

```text
bug          - Something is broken
feature      - New functionality
documentation - Documentation improvements
dependencies - Dependency updates
security     - Security-related changes
breaking     - Contains breaking changes
good first issue - Suitable for new contributors
```

## Security Practices

Code repositories are high-value targets. A few non-negotiable practices:

### Never Commit Secrets

API keys, passwords, tokens, and certificates do not belong in version control. Use environment variables, secret management tools, or GitHub's encrypted secrets for Actions workflows. Pair this with secret scanning tools like [Gitleaks](https://github.com/gitleaks/gitleaks) or GitHub's built-in secret scanning to catch accidental commits before they reach the remote.

### Sign Your Commits

GPG or SSH commit signing provides cryptographic proof that a commit came from who it claims to come from. GitHub displays a "Verified" badge on signed commits. Configure signing globally:

```bash
git config --global commit.gpgsign true
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
```

In high-security environments, require signed commits through branch protection rules.

### Enable Dependabot

GitHub Dependabot automatically opens pull requests when dependencies have known vulnerabilities or new versions available. Enable it with a `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    reviewers:
      - "org/platform-team"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

Keeping dependencies current is one of the simplest and most effective security measures available.

## Git Configuration Tips

A few configuration tweaks that improve the daily experience:

```bash
# Default branch name for new repositories
git config --global init.defaultBranch main

# Rebase by default when pulling
git config --global pull.rebase true

# Prune stale remote-tracking branches automatically
git config --global fetch.prune true

# Improve diff readability
git config --global diff.algorithm histogram

# Set a global gitignore for OS and editor files
git config --global core.excludesfile ~/.gitignore_global
```

Setting `pull.rebase true` deserves special mention. It keeps your history linear by replaying your local commits on top of the upstream changes instead of creating merge commits. The result is a cleaner, more readable history.

## Tagging and Releases

Use annotated tags for releases rather than lightweight tags. Annotated tags carry metadata (author, date, message) and are the standard for marking release points:

```bash
git tag -a v1.2.0 -m "Release v1.2.0: add OAuth2 support and fix session handling"
git push origin v1.2.0
```

Pair this with GitHub Releases to provide release notes, changelogs, and downloadable artifacts. If you follow Conventional Commits, tools like [release-please](https://github.com/googleapis/release-please) can automate the entire release process including changelog generation and version bumping.

## Common Pitfalls

A short list of mistakes I see regularly:

- **Force pushing to shared branches.** Never force push to `main` or any branch others are working on. Use `--force-with-lease` if you must force push to your own feature branch.
- **Ignoring CI failures.** A red pipeline is not background noise. Fix it before adding more commits.
- **Massive initial commits.** Breaking a large change into reviewable chunks is not extra work; it is the work.
- **Not pulling before pushing.** Stale local branches cause unnecessary merge conflicts.
- **Storing large binary files.** Git is not designed for large binaries. Use Git LFS or an artifact repository instead.

## Wrapping Up

Git best practices are not about following rules for their own sake. They exist to reduce friction, improve collaboration, and maintain a codebase that teams can work in confidently. The practices outlined here, branching strategies, commit conventions, pull request discipline, repository hygiene, and security measures, form a foundation that scales from solo projects to large engineering organizations.

Start with the basics: clean commits, small pull requests, and branch protection. Layer in automation through pre-commit hooks and CI pipelines. Build a culture where code review is valued as a learning opportunity rather than a bottleneck.

The best Git workflow is the one your team actually follows. Pick practices that match your team's maturity, enforce them with tooling where possible, and iterate as your needs evolve.

---

## References

- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [GitHub Flow Documentation](https://docs.github.com/en/get-started/using-github/github-flow)
- [GitHub Branch Protection Rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-a-branch-protection-rule/about-protected-branches)
- [Git Configuration Documentation](https://git-scm.com/docs/git-config)
- [GitHub CODEOWNERS Documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
- [Dependabot Configuration Options](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file)
- [Release Please](https://github.com/googleapis/release-please)
