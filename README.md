# blog

This is my blog repo - a static site built with Hugo using the Blowfish theme.

## Overview

This blog is automatically deployed to Cloudflare Pages at [www.irishlab.io](https://www.irishlab.io) using GitHub Actions.

## Prerequisites

- Hugo Extended v0.139.3 or later
- Cloudflare account with API token

## Local Development

### Install Hugo

Download and install Hugo Extended from [https://github.com/gohugoio/hugo/releases](https://github.com/gohugoio/hugo/releases)

### Initialize Theme

```bash
git submodule update --init --recursive
```

### Build the Site

```bash
cd docs
hugo server -D
```

The site will be available at `http://localhost:1313`

### Build for Production

```bash
cd docs
hugo --minify --destination public
```

## Deployment

### Automated Deployment via GitHub Actions

The site is automatically deployed to Cloudflare Pages when changes are pushed to the `main` branch. The deployment workflow:

1. Checks out the repository with submodules
2. Sets up Hugo
3. Builds the site with `hugo --minify`
4. Deploys to Cloudflare Pages

### Required GitHub Secrets

Configure the following secrets in your GitHub repository settings:

- `CLOUDFLARE_API_TOKEN` - Cloudflare API token with "Cloudflare Pages:Edit" permission
- `CLOUDFLARE_ACCOUNT_ID` - Your Cloudflare account ID

### Manual Deployment

You can trigger a manual deployment from the Actions tab in GitHub, or deploy locally using Wrangler:

```bash
# Install Wrangler
npm install -g wrangler

# Login to Cloudflare
wrangler login

# Deploy
cd docs
hugo --minify --destination public
cd ..
wrangler pages deploy docs/public --project-name=irishlab-blog
```

## Configuration

- **Domain**: www.irishlab.io
- **Base URL**: https://irishlab.io
- **Hugo Config**: `docs/hugo.toml`
- **Theme**: Blowfish (git submodule)

## Docker Build (Legacy)

Build the container locally:

```bash
docker build --no-cache -f docker/Dockerfile . -t blog_local
```
