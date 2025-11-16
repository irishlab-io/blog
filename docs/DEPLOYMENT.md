# Cloudflare Pages Deployment Setup Guide

This guide walks you through setting up automated deployment of the Hugo blog to Cloudflare Pages.

## Overview

The blog is automatically deployed to Cloudflare Pages using GitHub Actions whenever changes are pushed to the `main` branch. The deployment uses Cloudflare's Wrangler CLI via the `cloudflare/wrangler-action@v3` GitHub Action.

## Prerequisites

1. A Cloudflare account
2. Domain `irishlab.io` configured in Cloudflare
3. GitHub repository access to configure secrets

## Step 1: Create a Cloudflare API Token

1. Log in to your Cloudflare dashboard: https://dash.cloudflare.com
2. Navigate to **My Profile** → **API Tokens**
3. Click **Create Token**
4. Use the **Edit Cloudflare Workers** template or create a custom token with the following permissions:
   - **Account** → **Cloudflare Pages** → **Edit**
5. Set **Account Resources** to include your account
6. Click **Continue to summary** and then **Create Token**
7. **Copy the token** - you won't be able to see it again!

## Step 2: Get Your Cloudflare Account ID

1. In the Cloudflare dashboard, select your website (`irishlab.io`)
2. Scroll down on the **Overview** page
3. In the **API** section on the right side, you'll see your **Account ID**
4. Copy the Account ID

## Step 3: Configure GitHub Secrets

1. Go to your GitHub repository: https://github.com/irishlab-io/blog
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add the following secrets:

### Secret 1: CLOUDFLARE_API_TOKEN
- **Name**: `CLOUDFLARE_API_TOKEN`
- **Value**: Paste the API token you created in Step 1

### Secret 2: CLOUDFLARE_ACCOUNT_ID
- **Name**: `CLOUDFLARE_ACCOUNT_ID`
- **Value**: Paste your Account ID from Step 2

## Step 4: Configure Cloudflare Pages Project

The GitHub Action will automatically create the Cloudflare Pages project on the first deployment. However, you may want to configure it manually:

1. Go to your Cloudflare dashboard
2. Navigate to **Workers & Pages**
3. After the first deployment, you'll see the `irishlab-blog` project
4. Click on the project to configure:
   - **Custom Domain**: Add `www.irishlab.io` as a custom domain
   - **Build Settings**: These are handled by the GitHub Action, not needed in Cloudflare
   - **Environment Variables**: Add any required variables (currently none needed)

## Step 5: Configure DNS (if not already done)

1. In Cloudflare dashboard, go to **DNS** for `irishlab.io`
2. Ensure you have a CNAME record:
   - **Type**: CNAME
   - **Name**: www
   - **Target**: irishlab-blog.pages.dev (or your custom Cloudflare Pages domain)
   - **Proxy status**: Proxied (orange cloud)

## Step 6: Test the Deployment

1. Make a change to your blog (e.g., add a new post or edit content)
2. Commit and push to the `main` branch
3. Go to **Actions** tab in your GitHub repository
4. Watch the **Deploy to Cloudflare Workers** workflow run
5. Once completed, visit https://www.irishlab.io to see your deployed site

## Manual Deployment

If you need to deploy manually without pushing to `main`:

1. Go to the **Actions** tab in GitHub
2. Select **Deploy to Cloudflare Workers** workflow
3. Click **Run workflow** dropdown
4. Select the `main` branch
5. Click **Run workflow**

## Troubleshooting

### Deployment fails with authentication error
- Verify that `CLOUDFLARE_API_TOKEN` is correctly set in GitHub secrets
- Ensure the API token has the correct permissions (Cloudflare Pages:Edit)
- Check that the token hasn't expired

### Deployment fails with account error
- Verify that `CLOUDFLARE_ACCOUNT_ID` matches your Cloudflare account
- Ensure you're using the correct account (if you have multiple Cloudflare accounts)

### Site deploys but shows 404 errors
- Check that the Hugo build completed successfully in the workflow logs
- Verify that `docs/public` directory contains the built site
- Check Cloudflare Pages project settings for correct output directory

### Theme not loading
- Ensure git submodules are being checked out (the workflow uses `submodules: recursive`)
- Check that the Blowfish theme is properly configured in `docs/hugo.toml`

### Custom domain not working
- Verify DNS records in Cloudflare
- Wait for DNS propagation (can take up to 48 hours, usually much faster)
- Check SSL/TLS settings in Cloudflare (should be set to "Full" or "Full (strict)")

## Workflow Details

The deployment workflow (`.github/workflows/deploy.yml`) performs the following steps:

1. **Checkout**: Clones the repository with all submodules
2. **Setup Hugo**: Installs Hugo Extended v0.139.3
3. **Build**: Runs `hugo --minify` in the `docs` directory
4. **Deploy**: Uses Wrangler to deploy the built site to Cloudflare Pages

The workflow triggers on:
- Push to `main` branch (excluding README.md and most .github files)
- Manual workflow dispatch

## Configuration Files

### wrangler.toml
Contains Cloudflare Workers/Pages configuration:
- Project name: `irishlab-blog`
- Output directory: `docs/public`
- Routes configuration for `www.irishlab.io`

### .github/workflows/deploy.yml
GitHub Actions workflow for automated deployment.

## Local Testing

To test the build locally before deploying:

```bash
# Initialize submodules
git submodule update --init --recursive

# Build the site
cd docs
hugo --minify --destination public

# Preview the site locally
hugo server -D
```

## Security Notes

- API tokens should never be committed to the repository
- Use GitHub Secrets for all sensitive credentials
- Regularly rotate your API tokens
- Use minimal permissions for API tokens (only what's needed)
- Enable branch protection rules on `main` to prevent unauthorized deployments

## Additional Resources

- [Cloudflare Pages Documentation](https://developers.cloudflare.com/pages/)
- [Hugo Documentation](https://gohugo.io/documentation/)
- [Blowfish Theme Documentation](https://blowfish.page/docs/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
