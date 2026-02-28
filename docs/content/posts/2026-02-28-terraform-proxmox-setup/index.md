---
title: "Setting Up Terraform on an Existing Proxmox Cluster"
date: 2026-02-28
draft: false
description: "A step-by-step guide to configuring Terraform to manage virtual machines and resources on a Proxmox VE cluster that is already up and running"
summary: "Learn how to connect Terraform to your existing Proxmox cluster: create API credentials, configure the provider, manage state, and provision your first VM with Infrastructure as Code"
tags: ["terraform", "proxmox", "iac", "homelab", "infrastructure"]
series: ["Infrastructure as Code"]
series_order: 2
---

# Setting Up Terraform on an Existing Proxmox Cluster

If you already have a Proxmox Virtual Environment (VE) cluster running, adopting Terraform lets you manage virtual machines, containers, and network resources through code rather than through the web UI. This guide walks you through everything needed to go from a bare Proxmox cluster to a fully functional Terraform workflow.

## Prerequisites

Before starting, you should have:

- A running Proxmox VE cluster (version 7.x or 8.x) with at least one node
- A workstation running Linux, macOS, or Windows (WSL2 recommended)
- Basic familiarity with the command line
- A Proxmox user account with administrator access for the initial API token creation

## Step 1: Install Terraform

### Linux (Debian/Ubuntu)

```bash
# Install HashiCorp GPG key and repository
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# Verify installation
terraform -version
```

### macOS (Homebrew)

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

terraform -version
```

### Windows (winget)

```powershell
winget install HashiCorp.Terraform
```

After installation confirm the version output looks similar to:

```text
Terraform v1.9.x
on linux_amd64
```

## Step 2: Create a Dedicated Proxmox User and API Token

Terraform authenticates to Proxmox via API tokens. Creating a dedicated user with the minimum required permissions is a security best practice.

### Create the user and role

Log into any Proxmox node via SSH as root, then run:

```bash
# Create a dedicated Terraform user
pveum user add terraform@pve --comment "Terraform automation user"

# Create a custom role with only the permissions Terraform needs
pveum role add TerraformRole -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit SDN.Use"

# Grant the role on the root path (or narrow this down to a specific pool)
pveum aclmod / -user terraform@pve -role TerraformRole
```

### Create an API token

```bash
# Create the token (--privsep 0 disables privilege separation so the token inherits the user's ACLs)
pveum user token add terraform@pve terraform-token --privsep 0
```

The command output will display the token secret **once**. Save it immediately:

```text
┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
╞══════════════╪══════════════════════════════════════╡
│ full-tokenid │ terraform@pve!terraform-token        │
├──────────────┼──────────────────────────────────────┤
│ info         │ {"privsep":"0"}                      │
├──────────────┼──────────────────────────────────────┤
│ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
└──────────────┴──────────────────────────────────────┘
```

You will use `terraform@pve!terraform-token` as the **token ID** and the `value` as the **token secret**.

## Step 3: Prepare a Cloud-Init Template

Terraform provisions VMs by cloning a template. The following creates a lightweight Ubuntu 24.04 cloud-init template on Proxmox (run on the Proxmox node):

```bash
# Download the Ubuntu 24.04 cloud image
wget -q https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img \
  -O /tmp/noble-server-cloudimg-amd64.img

# Create the template VM (ID 9000, adjust as needed)
qm create 9000 \
  --name ubuntu-2404-template \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26

# Import the cloud image as a disk (replace 'local-lvm' with your storage pool)
qm importdisk 9000 /tmp/noble-server-cloudimg-amd64.img local-lvm

# Attach the disk and configure boot order
qm set 9000 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:vm-9000-disk-0 \
  --ide2 local-lvm:cloudinit \
  --boot order=scsi0 \
  --serial0 socket \
  --vga serial0 \
  --agent enabled=1

# Convert to template
qm template 9000

echo "Template 9000 created successfully"
```

## Step 4: Create the Terraform Project

Create a new directory for your Terraform code:

```bash
mkdir -p ~/proxmox-tf && cd ~/proxmox-tf
```

### Directory structure

```text
proxmox-tf/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
└── .gitignore
```

### `.gitignore`

Create this file first to avoid accidentally committing secrets:

```gitignore
# Terraform state and secrets
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
terraform.tfvars
*.tfvars.json
crash.log
override.tf
```

## Step 5: Configure the Proxmox Provider

### `main.tf`

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 3.0"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = var.proxmox_tls_insecure
}
```

### `variables.tf`

```hcl
variable "proxmox_api_url" {
  description = "Full Proxmox API URL, e.g. https://192.168.1.10:8006/api2/json"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "API token ID in the form user@realm!token-name"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "API token secret value"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Set to true to skip TLS certificate validation (self-signed certs)"
  type        = bool
  default     = false
}

variable "proxmox_node" {
  description = "The Proxmox node on which to create resources"
  type        = string
  default     = "pve"
}

variable "ssh_public_key" {
  description = "SSH public key injected via cloud-init"
  type        = string
}
```

### `terraform.tfvars`

Populate this file with your actual values. **Never commit this file to version control.**

```hcl
proxmox_api_url          = "https://192.168.1.10:8006/api2/json"
proxmox_api_token_id     = "terraform@pve!terraform-token"
proxmox_api_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
proxmox_tls_insecure     = true   # set to false if you have a valid certificate
proxmox_node             = "pve"
ssh_public_key           = "ssh-ed25519 AAAA... your-key-comment"
```

## Step 6: Define Your First VM Resource

Add the following to `main.tf` below the provider block:

```hcl
resource "proxmox_vm_qemu" "web" {
  name        = "web-01"
  target_node = var.proxmox_node

  # Clone from the cloud-init template created in Step 3
  clone      = "ubuntu-2404-template"
  full_clone = true

  # Hardware
  cores   = 2
  sockets = 1
  memory  = 2048

  # Disk
  disks {
    scsi {
      scsi0 {
        disk {
          size    = 20
          storage = "local-lvm"
        }
      }
    }
  }

  # Network
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud-init
  os_type   = "cloud-init"
  ipconfig0 = "ip=dhcp"
  sshkeys   = var.ssh_public_key

  # Keep the VM running after provisioning
  oncreate = true

  lifecycle {
    ignore_changes = [network]
  }
}
```

### `outputs.tf`

```hcl
output "web_ip" {
  description = "IP address assigned to web-01"
  value       = proxmox_vm_qemu.web.default_ipv4_address
}
```

## Step 7: Initialize and Apply

### Initialize the working directory

```bash
terraform init
```

Terraform downloads the Proxmox provider and sets up the `.terraform` directory:

```text
Initializing the backend...
Initializing provider plugins...
- Finding telmate/proxmox versions matching "~> 3.0"...
- Installing telmate/proxmox v3.0.1...

Terraform has been successfully initialized!
```

### Validate and format the configuration

```bash
terraform validate   # check for syntax errors
terraform fmt        # auto-format your .tf files
```

### Preview the plan

```bash
terraform plan
```

Review the output carefully. You should see a plan to create one VM resource:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

### Apply the configuration

```bash
terraform apply
```

Type `yes` when prompted. Terraform will clone the template and configure the VM via cloud-init. Once complete, the output will display the assigned IP address.

## Step 8: Manage Terraform State

The state file (`terraform.tfstate`) is the source of truth for what Terraform currently manages. For a homelab or small team, storing state remotely is strongly recommended to prevent accidental loss and enable collaboration.

### Option A: Local state (single user only)

No additional configuration is needed. State is stored in `terraform.tfstate` in your working directory. Back it up manually.

### Option B: S3-compatible backend with MinIO (recommended for homelab)

Run MinIO as a container on your Proxmox cluster:

```bash
docker run -d \
  --name minio \
  --restart unless-stopped \
  -p 9000:9000 \
  -p 9001:9001 \
  -v /mnt/data/minio:/data \
  -e MINIO_ROOT_USER=admin \
  -e MINIO_ROOT_PASSWORD=change-me-strong-password \
  minio/minio server /data --console-address ":9001"
```

Create a bucket and then add a backend block to `main.tf`:

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket                      = "terraform-state"
    key                         = "proxmox/terraform.tfstate"
    region                      = "us-east-1"            # required but ignored by MinIO
    endpoint                    = "http://192.168.1.10:9000"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true

    access_key = "your-minio-access-key"
    secret_key = "your-minio-secret-key"
  }
}
```

After adding the backend block, re-run `terraform init` to migrate existing state:

```bash
terraform init -migrate-state
```

## Common Day-2 Operations

### List managed resources

```bash
terraform state list
```

### Inspect a specific resource

```bash
terraform state show proxmox_vm_qemu.web
```

### Destroy a VM

```bash
terraform destroy -target=proxmox_vm_qemu.web
```

### Import an existing VM into state

If you already have a VM with ID `105` on node `pve` that you want Terraform to manage:

```bash
terraform import proxmox_vm_qemu.web pve/105
```

## Troubleshooting

### Error: `unexpected status code 401`

The API token is invalid or expired. Verify the token ID and secret in `terraform.tfvars`, then re-create the token in Proxmox if needed:

```bash
pveum user token remove terraform@pve terraform-token
pveum user token add terraform@pve terraform-token --privsep 0
```

### Error: `unable to find template`

The template name in `clone` must match exactly what is shown in the Proxmox UI. Verify with:

```bash
qm list | grep template
```

### Error: TLS certificate verification

If your Proxmox cluster uses a self-signed certificate, set `pm_tls_insecure = true` in the provider block (or `proxmox_tls_insecure = true` in `terraform.tfvars`). For production environments, deploy a trusted certificate via Let's Encrypt or your internal CA instead.

### Slow VM provisioning

Cloud-init initialization can take 2–5 minutes on first boot. The `terraform apply` command will wait until the QEMU guest agent reports the VM is ready. Ensure the guest agent is installed in your template (the Step 3 snippet enables it automatically).

## Security Hardening Checklist

- ✅ Use a dedicated `terraform@pve` user — never use root
- ✅ Restrict the API token role to only necessary privileges
- ✅ Keep `terraform.tfvars` out of version control (use `.gitignore`)
- ✅ Use a remote backend with encryption at rest
- ✅ Enable state locking (S3 + DynamoDB or MinIO with locking support)
- ✅ Rotate API tokens periodically
- ✅ Replace self-signed certificates with trusted ones in production

## Next Steps

With Terraform connected to your Proxmox cluster, you can:

- **Create reusable modules** to standardize VM definitions across environments
- **Integrate with GitHub Actions** to run `terraform plan` on pull requests and `terraform apply` on merge (see the [OpenTofu/Terraform CI/CD guide](/posts/2026-02-07-opentofu-proxmox/))
- **Add more VM types**: LXC containers, networks, and storage pools are all manageable via the Proxmox provider
- **Implement drift detection**: schedule a nightly `terraform plan` to catch manual changes

---

*Have questions or run into issues? Feel free to leave a comment below or open a discussion.*
