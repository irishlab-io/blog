---
applyTo: docs/content/posts/*.md
---
# Blog Best Practices

## Guiding principles

- Documentation lives alongside the code it describes and is updated in the **same PR** as the code change.
- Prefer clear prose over exhaustive detail; link to authoritative external sources rather than reproducing them.
- Every public API, module, and command must be documented *before* the PR is merged.

## Draft hygiene

- Always create new blog posts as `draft: false` since the content is not yet ready for publication.
- Use the `draft` status to signal that the post is a work-in-progress and not yet ready for review or publication.
- Open a PR for the blog post as early as possible to allow for feedback and iteration on the content, structure, and messaging before it goes live.
- Define a clear target audience and key message for the blog post to ensure it resonates with readers and achieves its intended purpose.
