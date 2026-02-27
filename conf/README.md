# Slidev Presentations

A [pnpm workspace](https://pnpm.io/workspaces) for managing multiple [Slidev](https://sli.dev/) presentations, powered by [slidev-workspace](https://github.com/leochiu-a/slidev-workspace).

## Quick Start

```bash
# Install dependencies (requires pnpm)
pnpm install

# Preview all presentations in a unified interface
pnpm preview

# Build all presentations for deployment
pnpm build
```

## Develop a single presentation

```bash
# Navigate into the presentation directory
cd slides/2026-03-owasp-sbom

# Start dev server
pnpm dev
```

## Add a new presentation

1. Create a new directory under `slides/`:

```bash
mkdir -p slides/my-new-talk
```

2. Add a `package.json`:

```json
{
  "name": "my-new-talk",
  "type": "module",
  "private": true,
  "scripts": {
    "build": "slidev build",
    "dev": "slidev",
    "export": "slidev export"
  },
  "dependencies": {
    "@slidev/cli": "catalog:",
    "@slidev/theme-default": "catalog:",
    "@slidev/theme-seriph": "catalog:",
    "vue": "catalog:"
  }
}
```

3. Add a `slides.md` with your content.

4. Run `pnpm install` from the workspace root.

## Structure

```
talk/slidev/
├── package.json              # Root workspace config
├── pnpm-workspace.yaml       # Workspace definition
├── slidev-workspace.yaml     # Workspace UI config
└── slides/
    ├── 2026-03-owasp-sbom/   # OWASP SBOM presentation
    │   ├── package.json
    │   ├── slides.md
    │   ├── components/
    │   ├── pages/
    │   └── snippets/
    └── <next-talk>/          # Add more here
```

## Presentations

| Directory | Title |
|---|---|
| `2026-03-owasp-sbom` | C'est SBOM mais il est bon ton SBOM ? (OWASP Montréal - Mars 2026) |
