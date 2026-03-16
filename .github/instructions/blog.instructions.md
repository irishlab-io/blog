---
applyTo: docs/content/posts/**/index.md
---
# Blog Post Assistant Instructions

## Intent

Use these rules when helping create or edit posts in `docs/content/posts/**/index.md`.
When the user asks for "a new post about <topic>", produce a practical, publishable draft with minimal back-and-forth.

## For New Topic-Based Posts

- Create the post under `docs/content/posts/YYYY-MM-DD-topic-slug/index.md`.
- Build the slug in lowercase, hyphen-separated, and concise.
- If no date is provided, use today's date.
- Default to `draft: true` for newly created posts unless the user explicitly asks for a ready-to-publish post.
- Keep frontmatter consistent with existing posts in this repository.

Use this frontmatter baseline:

```yaml
---
title: "<Clear, concrete title>"
date: YYYY-MM-DD
draft: true
description: "1-sentence description (about 140-180 chars)"
summary: "1-sentence summary (about 140-220 chars)"
tags: ["tag1", "tag2", "tag3"]
---
```

Optional when relevant:

- `series`
- `series_order`

## Content Structure

Prefer this flow unless the user asks for a different format:

1. Problem and context (why this topic matters)
2. Core concept or approach
3. Step-by-step implementation with concrete examples
4. Pitfalls or trade-offs
5. Wrap-up with practical next actions
6. Resources

## Writing Style

- Use clear, direct, practitioner-focused language.
- Prefer concrete examples over generic statements.
- Keep paragraphs short and scannable.
- Use headings to break up sections.
- Use numbered steps for procedures.
- Use bullet points for checklists or comparisons.

## Technical Accuracy

- Do not invent commands, config keys, features, or tool behavior.
- If unsure, state assumptions plainly in the draft.
- Prefer linking to authoritative docs instead of rewriting long references.
- Keep code snippets runnable and realistic.

## Relevance And Scope

- Focus tightly on the requested topic.
- If the topic is broad, choose one practical angle and state it early.
- Align examples to DevSecOps, platform engineering, CI/CD, security tooling, or homelab contexts when it fits naturally.

## Final Self-Check Before Returning

- The post path and slug follow repository conventions.
- Frontmatter is complete and valid YAML.
- The title, description, and summary are specific and non-redundant.
- The post contains actionable guidance, not only theory.
- Markdown formatting is clean and readable.
