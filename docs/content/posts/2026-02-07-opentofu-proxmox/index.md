---
title: "Deploying Virtual Machines on Proxmox with OpenTofu: A Complete Guide"
date: 2026-02-07
draft: true
description: "Learn how to use OpenTofu (or Terraform) to deploy VMs on Proxmox with GitHub Actions integration"
summary: "A comprehensive guide to Infrastructure as Code for Proxmox virtual environments, covering state management strategies and CI/CD integration"
tags: ["opentofu", "terraform", "proxmox", "iac", "github-actions", "ci-cd", "homelab"]
series: ["Infrastructure as Code"]
series_order: 1
---

# Deploying Virtual Machines on Proxmox with OpenTofu

Infrastructure as Code (IaC) has revolutionized how we manage and deploy infrastructure. In this comprehensive guide, I'll walk you through using OpenTofu (or Terraform) to deploy virtual machines on a Proxmox Virtual Environment server. We'll pay special attention to state storage strategies and integrating this workflow into a GitHub Actions pipeline.

## What is OpenTofu?

OpenTofu is an open-source fork of Terraform that maintains full compatibility with Terraform's syntax and providers while ensuring the project remains truly open source under the Linux Foundation. For this guide, everything applies to both OpenTofu and Terraform - you can use either tool interchangeably.

## Prerequisites

Before we begin, ensure you have:

- A Proxmox VE server (version 7.0 or later)
- OpenTofu or Terraform installed locally (version 1.6+)
- API credentials for your Proxmox server
- Basic understanding of Infrastructure as Code concepts
- A GitHub account (for the CI/CD integration)

## Understanding Proxmox API Access

Proxmox provides a robust REST API that allows programmatic access to all its features. To use OpenTofu with Proxmox, you'll need to create an API token:

1. Log into your Proxmox web interface
2. Navigate to **Datacenter** → **Permissions** → **API Tokens**
3. Create a new token with appropriate permissions
4. Save the token ID and secret - you'll need these for authentication

For production environments, I recommend creating a dedicated user with specific permissions rather than using root:

```bash
# On your Proxmox server
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role PVEVMAdmin
pveum user token add terraform@pve terraform-token --privsep 0
```

## Project Structure

Let's start with a well-organized project structure:

```text
proxmox-infrastructure/
├── .github/
│   └── workflows/
│       └── terraform.yml
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
├── modules/
│   └── proxmox-vm/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── .gitignore
└── README.md
```

## Setting Up the Proxmox Provider

First, let's create our provider configuration. Create a `main.tf` file:

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 3.0"
    }
  }

  # We'll configure the backend for state storage later
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_api_token_id = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret

  # Skip TLS verification for self-signed certificates (not recommended for production)
  pm_tls_insecure = var.proxmox_tls_insecure
}
```

Create a `variables.tf` file to define our variables:

```hcl
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = false
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "target_node" {
  description = "Proxmox node to deploy to"
  type        = string
  default     = "pve"
}
```

## Creating a Virtual Machine Resource

Now, let's create a virtual machine. Add this to your `main.tf`:

```hcl
resource "proxmox_vm_qemu" "vm" {
  name        = var.vm_name
  target_node = var.target_node

  # Clone from a template (recommended approach)
  clone       = "ubuntu-cloud-template"
  full_clone  = true

  # VM specifications
  cores       = 2
  sockets     = 1
  memory      = 2048

  # Disk configuration
  disks {
    scsi {
      scsi0 {
        disk {
          size    = 32
          storage = "local-lvm"
        }
      }
    }
  }

  # Network configuration
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud-init configuration
  os_type    = "cloud-init"
  ipconfig0  = "ip=dhcp"

  # SSH configuration
  sshkeys = var.ssh_public_key

  # Lifecycle configuration
  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}

output "vm_ip" {
  description = "IP address of the VM"
  value       = proxmox_vm_qemu.vm.default_ipv4_address
}
```

## Preparing Cloud-Init Templates

For a smoother experience, create a cloud-init enabled template on Proxmox:

```bash
# Download Ubuntu Cloud Image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Create VM
qm create 9000 --name ubuntu-cloud-template --memory 2048 --net0 virtio,bridge=vmbr0

# Import disk
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm

# Attach disk
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0

# Add cloud-init drive
qm set 9000 --ide2 local-lvm:cloudinit

# Set boot from disk
qm set 9000 --boot c --bootdisk scsi0

# Add serial console
qm set 9000 --serial0 socket --vga serial0

# Convert to template
qm template 9000
```

## State Storage Strategies: The Critical Decision

This is where many teams stumble. Terraform/OpenTofu state files contain sensitive information and must be managed carefully. Let's explore different strategies:

### Option 1: Local State (Development Only)

**Pros:**

- Simple to set up
- No external dependencies
- Fast

**Cons:**

- Not suitable for teams
- No state locking
- Risk of state file loss
- Cannot be used in CI/CD safely

```hcl
# No backend configuration needed - state stored in terraform.tfstate
```

**Use Case:** Personal experimentation and learning only.

### Option 2: S3-Compatible Backend (Recommended)

Many organizations use S3 or S3-compatible storage (like MinIO) for state management.

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state"
    key            = "proxmox/prod/terraform.tfstate"
    region         = "us-east-1"
    endpoint       = "https://s3.example.com"  # For S3-compatible storage

    # State locking with DynamoDB
    dynamodb_table = "terraform-locks"
    encrypt        = true

    # Skip AWS-specific validations for S3-compatible storage
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
```

**Pros:**

- Reliable and proven
- State locking with DynamoDB
- Versioning support
- Encryption at rest
- Suitable for teams

**Cons:**

- Requires AWS account or S3-compatible storage
- Additional infrastructure to manage
- Costs associated with storage

### Option 3: Terraform Cloud/Spacelift (Enterprise)

```hcl
terraform {
  cloud {
    organization = "your-org"

    workspaces {
      name = "proxmox-prod"
    }
  }
}
```

**Pros:**

- Managed state storage and locking
- Built-in collaboration features
- Audit logs
- Policy enforcement
- Remote execution

**Cons:**

- Requires subscription for advanced features
- Vendor lock-in
- Less control over infrastructure

### Option 4: HTTP Backend with GitLab/GitHub (Self-Hosted)

For self-hosted setups, you can use GitLab's or GitHub's built-in state storage:

```hcl
terraform {
  backend "http" {
    address        = "https://gitlab.example.com/api/v4/projects/PROJECT_ID/terraform/state/STATE_NAME"
    lock_address   = "https://gitlab.example.com/api/v4/projects/PROJECT_ID/terraform/state/STATE_NAME/lock"
    unlock_address = "https://gitlab.example.com/api/v4/projects/PROJECT_ID/terraform/state/STATE_NAME/lock"
    username       = "gitlab-token"
    password       = var.gitlab_token
  }
}
```

### My Recommendation: Tiered Approach

For most homelab and small business scenarios, I recommend:

1. **Development:** Local state for quick iterations
2. **Staging/Production:** S3-compatible backend (MinIO on your Proxmox cluster)
3. **Enterprise:** Terraform Cloud or Spacelift for advanced features

## Setting Up MinIO for State Storage

Here's how to set up a self-hosted S3-compatible backend using MinIO on your Proxmox server:

```bash
# Create MinIO container on Proxmox
docker run -d \
  --name minio \
  -p 9000:9000 \
  -p 9001:9001 \
  -v /mnt/data:/data \
  -e "MINIO_ROOT_USER=admin" \
  -e "MINIO_ROOT_PASSWORD=your-secure-password" \
  minio/minio server /data --console-address ":9001"

# Create bucket for Terraform state
mc alias set myminio http://localhost:9000 admin your-secure-password
mc mb myminio/terraform-state
mc version enable myminio/terraform-state
```

Then configure your backend:

```hcl
terraform {
  backend "s3" {
    bucket                      = "terraform-state"
    key                         = "proxmox/terraform.tfstate"
    region                      = "us-east-1"
    endpoint                    = "http://your-proxmox-ip:9000"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true

    access_key = "your-access-key"
    secret_key = "your-secret-key"
  }
}
```

## GitHub Actions Integration

Now for the exciting part - automating everything with GitHub Actions! Create `.github/workflows/terraform.yml`:

```yaml
name: 'Terraform Proxmox Deployment'

on:
  push:
    branches:
      - main
    paths:
      - 'environments/**'
      - 'modules/**'
      - '.github/workflows/terraform.yml'
  pull_request:
    branches:
      - main
    paths:
      - 'environments/**'
      - 'modules/**'
  workflow_dispatch:

env:
  TF_VERSION: '1.6'

jobs:
  terraform-plan:
    name: 'Terraform Plan'
    runs-on: ubuntu-latest
    environment: development

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TF_VERSION }}
          tofu_wrapper: false

      # Or use Terraform
      # - name: Setup Terraform
      #   uses: hashicorp/setup-terraform@v3
      #   with:
      #     terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS credentials for S3 backend
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Terraform Init
        working-directory: ./environments/dev
        env:
          TF_VAR_proxmox_api_token_id: ${{ secrets.PROXMOX_API_TOKEN_ID }}
          TF_VAR_proxmox_api_token_secret: ${{ secrets.PROXMOX_API_TOKEN_SECRET }}
        run: tofu init

      - name: Terraform Validate
        working-directory: ./environments/dev
        run: tofu validate

      - name: Terraform Format Check
        working-directory: ./environments/dev
        run: tofu fmt -check -recursive

      - name: Terraform Plan
        working-directory: ./environments/dev
        env:
          TF_VAR_proxmox_api_url: ${{ secrets.PROXMOX_API_URL }}
          TF_VAR_proxmox_api_token_id: ${{ secrets.PROXMOX_API_TOKEN_ID }}
          TF_VAR_proxmox_api_token_secret: ${{ secrets.PROXMOX_API_TOKEN_SECRET }}
        run: |
          tofu plan -out=tfplan -input=false

      - name: Upload Plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: environments/dev/tfplan
          retention-days: 5

  terraform-apply:
    name: 'Terraform Apply'
    runs-on: ubuntu-latest
    needs: terraform-plan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment:
      name: production
      url: https://proxmox.example.com

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TF_VERSION }}
          tofu_wrapper: false

      - name: Configure AWS credentials for S3 backend
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: environments/dev/

      - name: Terraform Init
        working-directory: ./environments/dev
        env:
          TF_VAR_proxmox_api_token_id: ${{ secrets.PROXMOX_API_TOKEN_ID }}
          TF_VAR_proxmox_api_token_secret: ${{ secrets.PROXMOX_API_TOKEN_SECRET }}
        run: tofu init

      - name: Terraform Apply
        working-directory: ./environments/dev
        env:
          TF_VAR_proxmox_api_url: ${{ secrets.PROXMOX_API_URL }}
          TF_VAR_proxmox_api_token_id: ${{ secrets.PROXMOX_API_TOKEN_ID }}
          TF_VAR_proxmox_api_token_secret: ${{ secrets.PROXMOX_API_TOKEN_SECRET }}
        run: tofu apply -input=false tfplan
```

## GitHub Secrets Configuration

You'll need to configure these secrets in your GitHub repository:

1. Navigate to **Settings** → **Secrets and variables** → **Actions**
2. Add the following secrets:

```text
PROXMOX_API_URL=https://your-proxmox-server:8006/api2/json
PROXMOX_API_TOKEN_ID=terraform@pve!terraform-token
PROXMOX_API_TOKEN_SECRET=your-token-secret
AWS_ACCESS_KEY_ID=your-s3-access-key
AWS_SECRET_ACCESS_KEY=your-s3-secret-key
```

## Advanced: Multi-Environment Strategy

For production-grade setups, use separate workspaces or directories for each environment:

```hcl
# environments/dev/main.tf
module "proxmox_vm" {
  source = "../../modules/proxmox-vm"

  vm_name      = "dev-web-server"
  target_node  = "pve-dev"
  cores        = 2
  memory       = 2048
  environment  = "development"
}

# environments/prod/main.tf
module "proxmox_vm" {
  source = "../../modules/proxmox-vm"

  vm_name      = "prod-web-server"
  target_node  = "pve-prod"
  cores        = 4
  memory       = 8192
  environment  = "production"
}
```

Each environment should have its own state file and potentially different backends.

## Best Practices and Security Considerations

### 1. Never Commit Secrets

Add to your `.gitignore`:

```gitignore
# Terraform/OpenTofu
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
terraform.tfvars
*.tfvars.json
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Secrets
*.pem
*.key
.env
secrets.auto.tfvars
```

### 2. Use Variable Files for Non-Sensitive Configuration

Create a `terraform.tfvars.example`:

```hcl
proxmox_api_url = "https://proxmox.example.com:8006/api2/json"
target_node     = "pve"
vm_name         = "my-vm"
```

### 3. Implement State Locking

Always enable state locking to prevent concurrent modifications:

```hcl
# For S3 backend
terraform {
  backend "s3" {
    # ... other configuration ...
    dynamodb_table = "terraform-locks"
  }
}
```

### 4. Enable State Encryption

```hcl
terraform {
  backend "s3" {
    # ... other configuration ...
    encrypt = true
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }
}
```

### 5. Use Remote State Data Sources

When one configuration needs to reference another's outputs:

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "terraform-state"
    key    = "proxmox/network/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "proxmox_vm_qemu" "vm" {
  # Reference outputs from network configuration
  network {
    bridge = data.terraform_remote_state.network.outputs.bridge_name
  }
}
```

### 6. Implement Drift Detection

Add a scheduled workflow to detect infrastructure drift:

```yaml
name: 'Drift Detection'

on:
  schedule:
    # Run every day at 2 AM
    - cron: '0 2 * * *'
  workflow_dispatch:

jobs:
  drift-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
      - name: Init
        run: tofu init
      - name: Plan
        run: tofu plan -detailed-exitcode
        continue-on-error: true
      - name: Notify on Drift
        if: failure()
        run: echo "Drift detected! Manual review required."
```

### 7. Use Workspaces for Environment Isolation

```bash
# Create workspaces
tofu workspace new dev
tofu workspace new staging
tofu workspace new prod

# Switch workspaces
tofu workspace select prod

# List workspaces
tofu workspace list
```

## Troubleshooting Common Issues

### Issue 1: API Connection Failures

```text
Error: error creating Proxmox client: error during login: unexpected status code 403
```

**Solution:** Verify your API token has the correct permissions:

```bash
pveum user token permissions terraform@pve terraform-token
```

### Issue 2: State Lock Conflicts

```text
Error: Error acquiring the state lock
```

**Solution:** Manually unlock the state (use with caution):

```bash
tofu force-unlock <lock-id>
```

### Issue 3: Clone Template Not Found

```text
Error: unable to find template 'ubuntu-cloud-template'
```

**Solution:** Ensure your template exists and is properly named:

```bash
qm list | grep template
```

## Monitoring and Observability

Integrate monitoring into your workflow:

```hcl
resource "proxmox_vm_qemu" "monitored_vm" {
  name = "monitored-vm"

  # ... other configuration ...

  # Add monitoring agents
  agent = 1

  # Custom initialization script
  cicustom = "user=local:snippets/monitoring-setup.yml"
}
```

Create a monitoring setup script in Proxmox's snippet storage:

```yaml
#cloud-config
packages:
  - prometheus-node-exporter
  - telegraf

runcmd:
  - systemctl enable prometheus-node-exporter
  - systemctl start prometheus-node-exporter
  - systemctl enable telegraf
  - systemctl start telegraf
```

## Cost Optimization Tips

1. **Use Spot/Preemptible VMs:** Consider implementing auto-shutdown for dev environments
2. **Right-size Resources:** Start small and scale up based on metrics
3. **Implement Auto-scaling:** Use Terraform/OpenTofu with monitoring to scale resources
4. **Clean Up Unused Resources:** Regular audits and automated cleanup workflows

```hcl
# Auto-shutdown for development VMs
resource "proxmox_vm_qemu" "dev_vm" {
  # ... configuration ...

  lifecycle {
    prevent_destroy = false
  }

  # Add tags for auto-shutdown
  tags = "auto-shutdown,development"
}
```

## Conclusion

Deploying virtual machines on Proxmox using OpenTofu/Terraform provides a powerful, reproducible approach to infrastructure management. By following the state storage strategies outlined in this guide and integrating with GitHub Actions, you create a robust CI/CD pipeline that:

- **Ensures consistency** across environments
- **Provides audit trails** for all infrastructure changes
- **Enables collaboration** through code review processes
- **Reduces manual errors** through automation
- **Maintains security** through proper secret management

The key takeaways:

1. **Always use remote state storage** for production environments
2. **Implement state locking** to prevent concurrent modifications
3. **Use GitHub Actions environments** for approval workflows
4. **Never commit secrets** to version control
5. **Test changes in development** before applying to production
6. **Implement drift detection** to catch manual changes

Remember, Infrastructure as Code is not just about automation - it's about creating a reliable, repeatable, and auditable process for managing your infrastructure. Start small, iterate, and continuously improve your processes.

## Additional Resources

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- [Proxmox VE API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

## Next Steps

In future posts, I'll cover:

- Advanced networking configurations with Proxmox and Terraform
- Creating custom modules for reusable infrastructure components
- Implementing Policy as Code with OPA and Sentinel
- Building a complete homelab infrastructure with IaC
- Disaster recovery and backup strategies for Terraform-managed infrastructure

---

Have questions or suggestions? Feel free to reach out or leave a comment below. Happy automating!
