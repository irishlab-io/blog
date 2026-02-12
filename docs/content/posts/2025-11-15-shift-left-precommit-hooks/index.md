---
title: "Shifting Left with Pre-Commit"
date: 2025-11-15
draft: false
description: "Exploring how automated quality gates at commit time can transform your development workflow"
summary: "Last month, I had the opportunity to share my experiences with implementing quality automation in development workflows. Across any industries where software development occurs, one truth stands out: early defect detection saves exponentially more time and money than late-stage fixes."
tags: ["devsecops", "security", "git", "automation", "development-workflow"]
series: ["DevSecOps"]
series_order: 1
---

# Shifting Left with Pre-Commit

The Developer's Dilemma in a simple scenario: Your team lead is asking for a slew of check on every commit and **then** the Security team just announced new requirements for every code commit. It is an neverending pile up on your developper mental load.

```text
1. Execute unit tests before pushing
2. Check for accidentally committed secrets
3. Format code according to team standards
4. Verify dependencies are properly pinned
5. Run static analysis tools
```

Each requirement individually seems reasonable, but collectively they create **checklist fatigue**. Developers now have a mental burden of remembering and manually executing multiple steps before every commit. This isn't sustainable, and it's not fair to expect perfect adherence. Developers aren't resistant to quality; they're resistant to manual, repetitive tasks.

Research consistently shows that bugs found during development cost a fraction of bugs discovered in production. Some studies suggest the multiplier can be **640x or more**.  The challenge becomes: how do we enforce quality without adding friction?

## Git Hooks: The Hidden Automation Layer

Most developers know git has hooks sample files sitting in `.git/hooks` that rarely get touched. These hooks are essentially event listeners that run scripts at key moments in the git lifecycle.

The beauty of hooks is they're automatic. When configured, they execute without any conscious effort from the developer. But native git hooks have problems:

- Are not tracked in version control
- Distribution requires manual setup
- Updates are a coordination nightmare
- Multi-repo management is painful

## Modern Hook Management Solutions

Several frameworks emerged to solve the git hook distribution problem. Here's what they typically provide:

1. **Centralized configuration** - One file defining all hooks
2. **Version control integration** - Configuration lives in your repo
3. **Simple installation** - One command gets developers running
4. **Cross-language support** - Works with any programming language
5. **Hook composition** - Multiple tools can run in sequence

Popular options include:

- [Pre-Commit](https://pre-commit.com) written in Python
- [Husky](https://typicode.github.io/husky) written in JavaScript
- [Lefthook](https://github.com/evilmartians/lefthook) written in Go
- and several others

They all solve similar problems with slightly different philosophies.  My go to tool is [Pre-Commit](https://pre-commit.com) given my programming language of choice is typically Python.  Although Pre-Commit is not limited to the Python-ecosystem and can be use in context of others language.

## Building Your Hook Strategy

Rather than showing generic examples, let me share the progression I recommend based on real implementation experience:

**Phase 1: Start with Quick Wins:**

Begin with non-controversial linting that are almost universally accepted.  These run in under a second and catch common accidents without disrupting flow.

```text
- Remove trailing whitespace
- Ensure files end with newlines
- Check MD/JSON/TOML/YAML syntax
- Prevent large file commits
```

**Phase 2: Add Secret Scanning:**

Once the team is comfortable with the concept, add secret detection. This is where real value starts showing:

```text
- Include a secret scanning tool
```

Secret scanning tool are the ideal first security usage of pre-commit hooks.  Tools such as [GitGuardian](https://www.gitguardian.com/), [Trufflehog](https://trufflesecurity.com/trufflehog) and [Gitleaks](https://github.com/gitleaks/gitleaks) can scan commit for patterns matching API keys, passwords, tokens, and other credentials. A secret caught locally has fewwer changes to never enters the repository commit history therefore remediation is much easier and less impactful.

**Phase 3: Language-Specific Quality:**

At this point in time, the team should start to use the associated pre-commit hooks regularly with limited impact while generating better quality.  The next fcous should be about improving code quality:

```text
- Include minimal unit testing steps
- Standardize commits message
- Restrict git worklows to certain agreed conventions
```

**Phase 4: The Heavy Hitters:**

Finally, consider adding longer and more complexe steps once the pre-commit hooks adoption is fairly high.

```text
- Larger and onger test suites
- Opinionated security toolchain
- Serious SAST tool for code quality
- Dependency vulnerability scans
- License compliance checks
```

These might take longer, so consider making run only on changed files, have manual trigger instead of every commit and be considerate of large codebases.

## The CI Safety Net

A critical principle is taht **hooks are developer helpers, not enforcers.**  Developers can always bypass hooks with `git commit --no-verify`. That's by design since given some type of emergencies might require quick commits against agreed upon convention.

That where the CI pipeline comes into play trying to catch anything that was bypassed during local validation.  This creates a healthy dynamic:

- Hooks catch 95% of issues locally (fast feedback)
- CI catches the remaining 5% (enforcement)
- Developers learn from CI failures what hooks prevented
- The value of local hooks becomes self-evident

## Developper Resistance

Real talk: some developers will resist. Common objections and responses:

**"It slows me down":**

- Profile your hooks—keep total time under 5 seconds
- Use faster framework alternatives
- Make expensive checks manual or CI-only

**"I need to commit work in progress":**

- That's what `--no-verify` is for
- Consider allowing WIP commits on feature branches
- CI still catches issues before merging

**"The linter is wrong":**

- Configuration files let you customize rules
- Some checks can be suppressed with inline comments
- Regularly review rules with the team
- Allow team member to suggest rules changes

**"This breaks my workflow":**

- Listen and adapt; the goal is enablement, not obstruction
- Different hooks for different branches
- Allow team-specific configurations
- Somtimes workflow breakage is mandatory

## Measuring Success

How do you know if your hook implementation is working? In order to improve monitoring and tracking is required.  Consider measuring and monitoring the following:

- **Reduction in CI failures** - Fewer builds broken by preventable issues
- **Time saved** - Less context switching from CI feedback
- **Developer adoption** - How many devs install hooks voluntarily
- **False positive rate** - Are hooks annoying or helpful?
- **Security incidents** - Decline in committed secrets

## Wrapping Up

Implementing automated quality checks through hooks represents a fundamental shift in how we think about code quality. Instead of relying on developer memory and discipline, we build quality into the workflow itself.

The journey from manual checklists to automated validation takes time and iteration. Start small, prove value, and expand gradually. Focus on developer experience—if hooks feel helpful rather than obstructive, adoption follows naturally.

Most importantly, remember that hooks are means to an end. The goal isn't running hooks—it's shipping quality code efficiently. Keep that focus, and your implementation will succeed.

---

## Additional Resources

*This post draws from experiences implementing quality automation across aerospace and financial services organizations. For a hands-on demonstration of these concepts, check out the [pyquiz repository](https://github.com/irishlab-io/pyquiz) which provides practical examples of hook implementation.*

*Have questions about implementing hooks in your organization? The concepts discussed here are language and framework agnostic—the principles apply universally.*
