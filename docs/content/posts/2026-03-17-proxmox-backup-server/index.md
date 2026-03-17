---
title: "Proxmox Backup Server: Installation, Configuration, and Best Practices"
date: 2026-03-17
draft: false
description: "A comprehensive guide to installing Proxmox Backup Server, configuring datastores, managing users and permissions, setting up networking with VLANs, and applying production best practices for a secure and reliable backup infrastructure"
summary: "Learn how to deploy Proxmox Backup Server from scratch, set up dedicated backup storage, enforce least-privilege access control, isolate backup traffic with VLANs, and apply the hardening and monitoring practices that make backups trustworthy in a homelab or small business environment."
tags: ["proxmox", "backup", "homelab", "infrastructure", "storage", "networking", "vlan", "security", "best-practices"]
---

Backups are the safety net that makes every other risk you take in a homelab acceptable. You can experiment boldly, upgrade aggressively, and break things confidently — as long as you know that a clean restore is one command away. Without reliable backups, every mistake is potentially catastrophic.

Proxmox Backup Server (PBS) is the purpose-built backup solution from the Proxmox team. It is designed specifically to back up Proxmox VE virtual machines and containers efficiently, using client-side deduplication, compression, and encryption. Unlike generic backup tools bolted onto existing infrastructure, PBS understands the structure of VM disk images and LXC containers, which lets it deduplicate at the block level across multiple backups and multiple VMs simultaneously.

This guide covers the complete setup: installation, storage configuration, user and permission management, network isolation with VLANs, and the operational practices that turn a working backup system into a trustworthy one.

## What Is Proxmox Backup Server?

Proxmox Backup Server is a standalone Debian-based appliance that provides:

- **Client-side deduplication:** Only changed data blocks are transmitted on each backup run. A daily full backup of a 100 GB VM typically transfers only a few gigabytes after the first run.
- **Compression and encryption:** Data is compressed before transmission and can be encrypted end-to-end, so neither the network nor the backup server itself can read your data in cleartext if encryption is enabled.
- **Incremental backups that restore as full backups:** PBS stores incremental snapshots but presents each one as a complete, independently restorable point. There is no fragile backup chain to manage.
- **Integrity verification:** PBS can verify stored backup data against checksums, catching silent data corruption before you need the backup.
- **Garbage collection:** When old backups are pruned, PBS automatically reclaims storage by removing deduplicated blocks that are no longer referenced.
- **A web interface and REST API:** The same style of interface as Proxmox VE, with full API access for automation.

PBS is a separate product from Proxmox VE. You install it on its own machine (physical or virtual), connect your Proxmox VE nodes to it, and schedule backups from the PVE side. This separation is intentional: a backup server that lives on the same host as the data it is backing up provides no protection against host failure.

## Architecture Overview

A standard PBS deployment looks like this:

```
Proxmox VE Cluster (pve1, pve2, pve3)
         │
         │ (backup traffic - dedicated VLAN or network)
         │
Proxmox Backup Server (pbs1)
         │
         └── Datastore (local or NFS/ZFS pool)
```

The key design principles:

- **PBS runs on its own hardware.** If PBS is a VM on PVE, it cannot back up itself when the underlying PVE node fails. Use a dedicated machine or at minimum a machine in your cluster that is managed separately.
- **Backup traffic is isolated.** Backup jobs move large amounts of data. Sharing that traffic with VM and management traffic degrades performance and makes it difficult to guarantee backup completion windows.
- **PBS does not replace offsite backups.** PBS provides excellent local backup capability. For production data, you still need an offsite or cloud copy — PBS supports S3-compatible sync targets for this purpose.

## Prerequisites

Before installing PBS, prepare the following:

- A dedicated physical machine or a VM with:
  - At minimum **4 GB RAM** (8 GB+ recommended for large datastores)
  - At minimum **two storage devices**: one for the OS, one (or more) for backup data
  - **Two network interfaces** recommended: one for management, one for backup traffic
- A USB drive to write the PBS installer ISO
- Network access to the machine (DHCP or planned static IPs)
- Your planned IP addressing scheme written down before you start

### Planned Network Layout Example

| Interface | Purpose           | Network          | Example IP       |
|-----------|-------------------|------------------|------------------|
| eno1      | Management        | 192.168.1.0/24   | 192.168.1.50/24  |
| eno2      | Backup traffic    | 10.20.0.0/24     | 10.20.0.50/24    |

*The backup traffic network should be a dedicated, isolated segment. We will configure this with a VLAN later in the guide.*

---

## Part 1: Installing Proxmox Backup Server

### Download and Write the Installer

1. Download the latest PBS ISO from [https://www.proxmox.com/en/downloads/proxmox-backup-server](https://www.proxmox.com/en/downloads/proxmox-backup-server)
2. Verify the SHA256 checksum shown on the download page before writing:

```bash
sha256sum proxmox-backup-server_*.iso
```

3. Write to USB (Linux/macOS):

```bash
dd if=proxmox-backup-server_*.iso of=/dev/sdX bs=4M status=progress
```

Or use Balena Etcher on any platform.

### Run the Installer

Boot from the USB drive on your backup server hardware. The installer is graphical and straightforward:

1. **Select target disk** — choose your OS disk only. Leave backup data disks untouched; you will configure storage after installation.
2. **Set country, timezone, and keyboard layout.**
3. **Set the root password** — use a strong, unique password. Store it in a password manager.
4. **Set the hostname and management IP:**
   - Hostname: `pbs1.yourdomain.local` (or your chosen name)
   - IP: your planned management address
   - Gateway: your network gateway
   - DNS: your DNS server

After installation, remove the USB drive and reboot. Access the web interface at:

```
https://<pbs-management-ip>:8007
```

Log in with `root` and the password you set.

### Remove the Subscription Notice (Optional)

PBS displays a subscription notice on login if no valid subscription is active. For homelab use, you can suppress this notice:

```bash
sed -Zi 's/res = await this.#proxmoxTask\(api\);/res = {status: "Active", serverid: "XX", sockets: 1, cores: 1, level: "c"};/g' \
  /usr/share/javascript/proxmox-backup/js/proxmox-backup.js
```

> **Note:** This modification is reset on package updates. The subscription notice does not affect functionality.

---

## Part 2: Storage Configuration

PBS organizes backup data into **datastores** — directories on local or network-mounted storage. Before creating a datastore, you need to configure the underlying storage.

### Understanding Datastore Storage Options

| Storage Type | Use Case | Considerations |
|-------------|----------|----------------|
| Local disk (ext4/xfs) | Simple, single-disk setups | No redundancy |
| ZFS pool (local) | Recommended for homelabs | Checksumming, snapshots, redundancy |
| NFS mount | Network-attached storage | Latency matters; avoid for high-frequency backups |
| CIFS/SMB | Windows file server targets | Similar considerations to NFS |

For a homelab with one or two dedicated backup disks, a local ZFS pool provides the best combination of features: built-in checksumming catches silent data corruption, snapshots allow point-in-time recovery, and RAID-Z or mirroring provides hardware failure tolerance.

### Creating a ZFS Pool for Backup Data

If your backup server has two or more backup data disks, create a mirrored ZFS pool:

```bash
# Identify your disks (do not use the OS disk)
lsblk

# Create a mirrored ZFS pool (recommended with 2 disks)
zpool create -o ashift=12 backup-pool mirror /dev/sdb /dev/sdc

# Or a single-disk pool (no redundancy, not recommended)
zpool create -o ashift=12 backup-pool /dev/sdb

# Verify the pool
zpool status backup-pool
zpool list
```

For three or more disks, consider RAID-Z:

```bash
# RAID-Z1 (can lose 1 disk) with 3 disks
zpool create -o ashift=12 backup-pool raidz1 /dev/sdb /dev/sdc /dev/sdd

# RAID-Z2 (can lose 2 disks) with 4+ disks
zpool create -o ashift=12 backup-pool raidz2 /dev/sdb /dev/sdc /dev/sdd /dev/sde
```

Enable compression on the pool (LZ4 is essentially free performance with negligible CPU cost):

```bash
zfs set compression=lz4 backup-pool
```

### Creating a PBS Datastore

With storage prepared, create a datastore in the PBS web interface:

1. Navigate to **Administration** → **Datastores** → **Add Datastore**
2. Set:
   - **Name:** A short identifier, e.g., `local-backup`
   - **Path:** The mount point of your storage, e.g., `/backup-pool` (for ZFS) or `/mnt/backup-data` (for other storage)
3. Click **Add**

PBS will create the required directory structure inside that path.

You can also create a datastore from the command line:

```bash
proxmox-backup-manager datastore create local-backup /backup-pool
```

### Configuring Prune and Garbage Collection

After creating the datastore, configure retention policies. These determine how many backup snapshots are kept and when they expire.

In the web interface, under your datastore settings, set **Prune Schedule** and **Prune Options**:

```
keep-last: 3          # Keep the last 3 backups regardless of age
keep-daily: 7         # Keep one backup per day for 7 days
keep-weekly: 4        # Keep one backup per week for 4 weeks
keep-monthly: 3       # Keep one backup per month for 3 months
```

Adjust these values to match your recovery time objectives and available storage capacity.

Schedule **Garbage Collection** to run after prune operations to reclaim freed storage blocks. A daily schedule at a low-traffic time works well:

```
Schedule: daily (e.g., 02:00)
```

From the command line:

```bash
# Set prune job schedule
proxmox-backup-manager prune-job create --store local-backup --schedule daily --keep-daily 7 --keep-weekly 4 --keep-monthly 3

# Set garbage collection schedule
proxmox-backup-manager garbage-collection schedule local-backup daily
```

---

## Part 3: User and Access Management

The default PBS installation has only the `root@pam` superuser. Running everything as root is convenient but creates unnecessary risk. The principle of least privilege means each entity — whether a Proxmox VE node, a human administrator, or an automation script — should have only the permissions it needs to perform its function.

### PBS Authentication Realms

PBS supports two authentication realms:

- **`pam`:** Uses the underlying Linux PAM system. `root@pam` is the built-in superuser. PAM users can be created on the OS and will authenticate with their system credentials.
- **`pbs`:** PBS-native users. These users exist only within PBS and authenticate via the PBS web interface and API. This is the preferred realm for dedicated service accounts.

### Creating a Dedicated Backup User for Proxmox VE

Rather than connecting your Proxmox VE nodes with root credentials, create a dedicated PBS user with only the permissions required for backup operations:

**Step 1: Create the user**

In the PBS web interface, navigate to **Administration** → **Access Control** → **User Management** → **Add**:

- **User ID:** `pve-backup@pbs`
- **Password:** Generate a strong random password (store in your password manager)
- **Comment:** "Service account for PVE backup jobs"

Or via command line:

```bash
proxmox-backup-manager user create pve-backup@pbs --password 'YourStrongPassword' --comment "PVE backup service account"
```

**Step 2: Create a dedicated role (optional but recommended)**

PBS has built-in roles. For a backup client, `DatastoreBackup` is the appropriate role — it allows creating backups but not reading or deleting other users' backups.

Built-in roles:
| Role | Permissions |
|------|-------------|
| `Admin` | Full access |
| `Audit` | Read-only access to everything |
| `DatastoreAdmin` | Full control of a specific datastore |
| `DatastoreBackup` | Create backups in a datastore |
| `DatastoreReader` | Read and restore backups |
| `DatastorePowerUser` | Backup, restore, prune — no admin |

**Step 3: Assign permissions**

Grant the `pve-backup@pbs` user the `DatastoreBackup` role on the specific datastore (not the entire server):

```bash
proxmox-backup-manager acl update /datastore/local-backup DatastoreBackup --auth-id pve-backup@pbs
```

In the web interface: **Administration** → **Access Control** → **Permissions** → **Add** → select path `/datastore/local-backup`, user `pve-backup@pbs`, role `DatastoreBackup`.

### Creating an API Token for Automation

For Proxmox VE to connect to PBS programmatically, use an API token rather than a user password. API tokens can be independently revoked without changing the user's password, and their scope can be limited further than the user's own permissions.

```bash
proxmox-backup-manager user generate-token pve-backup@pbs pve-token --comment "PVE cluster backup token"
```

The output will show the token ID and secret — **save these immediately**, as the secret is not recoverable:

```
┌──────────┬──────────────────────────────────────────────────────┐
│ key      │ value                                                │
╞══════════╪══════════════════════════════════════════════════════╡
│ tokenid  │ pve-backup@pbs!pve-token                            │
│ value    │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx                │
└──────────┴──────────────────────────────────────────────────────┘
```

Assign permissions to the token specifically (tokens do not automatically inherit all user permissions unless `--privsep 0` is used):

```bash
proxmox-backup-manager acl update /datastore/local-backup DatastoreBackup --auth-id "pve-backup@pbs!pve-token"
```

### Creating a Read-Only Audit User

For monitoring or auditing purposes, create a user with `Audit` access:

```bash
proxmox-backup-manager user create auditor@pbs --password 'AuditorPassword' --comment "Read-only audit account"
proxmox-backup-manager acl update / Audit --auth-id auditor@pbs
```

### Two-Factor Authentication

For any user with web interface access (particularly administrators), enable TOTP-based two-factor authentication:

1. Log into PBS as the user
2. Navigate to the user icon (top right) → **Two Factor Auth**
3. Add a TOTP entry and scan the QR code with an authenticator app

Enforce 2FA for all admin users. Service accounts using API tokens do not require 2FA as they never log in interactively.

---

## Part 4: Networking and VLAN Configuration

Backup operations generate sustained, high-throughput network traffic. Isolating this traffic from your general VM and management networks has two key benefits:

1. **Performance:** Backups do not compete with production VM traffic for bandwidth.
2. **Security:** A compromise of a VM or the management network does not automatically give access to backup traffic or the PBS management interface.

### Network Architecture for PBS

A recommended setup uses three separate networks:

| Network | VLAN ID | Purpose |
|---------|---------|---------|
| Management | 10 | PBS web interface, SSH access, admin tasks |
| Backup Traffic | 20 | Data transfer between PVE nodes and PBS |
| (Optional) Sync | 30 | Sync to remote PBS or S3 |

The backup traffic VLAN (VLAN 20) is a private network — no routing to the internet, no routing to the general LAN. Only PVE nodes and the PBS server have interfaces on this VLAN.

### Configuring Network Interfaces on PBS

PBS uses Debian networking. Edit `/etc/network/interfaces` to configure your interfaces:

```bash
nano /etc/network/interfaces
```

A typical dual-interface configuration with VLAN tagging:

```
auto lo
iface lo inet loopback

# Management interface (untagged or on management VLAN)
auto eno1
iface eno1 inet static
    address 192.168.1.50/24
    gateway 192.168.1.1
    dns-nameservers 192.168.1.1

# Backup traffic interface (dedicated NIC for backup VLAN)
auto eno2
iface eno2 inet static
    address 10.20.0.50/24
```

If you are using VLAN tagging on a single physical interface rather than dedicated NICs:

```
auto lo
iface lo inet loopback

# Physical interface (no IP on the trunk itself)
auto eno1
iface eno1 inet manual

# Management VLAN
auto eno1.10
iface eno1.10 inet static
    address 192.168.1.50/24
    gateway 192.168.1.1
    dns-nameservers 192.168.1.1
    vlan-raw-device eno1

# Backup VLAN
auto eno1.20
iface eno1.20 inet static
    address 10.20.0.50/24
    vlan-raw-device eno1
```

Apply the configuration:

```bash
ifreload -a
```

Verify connectivity:

```bash
ip addr show
ip route show
ping -c 3 10.20.0.1
```

### Configuring the Backup VLAN on Your Switch

On your managed switch, configure the port connecting to PBS:

- **Access port (dedicated NIC per VLAN):** Set the port to access mode on the appropriate VLAN.
- **Trunk port (single NIC with VLAN tags):** Set the port to trunk mode and allow the management and backup VLANs.

Example for a Cisco/Catalyst-style switch (VLAN tagging on a trunk):

```
interface GigabitEthernet0/10
  description PBS-Server
  switchport mode trunk
  switchport trunk allowed vlan 10,20
  spanning-tree portfast trunk
```

For a simple access port connection to VLAN 20 only:

```
interface GigabitEthernet0/10
  description PBS-Backup-NIC
  switchport mode access
  switchport access vlan 20
  spanning-tree portfast
```

### Configuring Proxmox VE Nodes for Backup Traffic

On each PVE node, configure a network interface on the backup VLAN. In the PVE web interface:

1. Navigate to the node → **System** → **Network**
2. Add a **Linux VLAN** interface:
   - **Name:** `vmbr0.20` (or your physical bridge name with VLAN ID)
   - **VLAN ID:** `20`
   - **IP:** An address in the backup network, e.g., `10.20.0.11/24`
3. Apply the configuration

The PVE nodes will use this interface when connecting to PBS.

### Firewall Rules for PBS

Restrict access to the PBS web interface and API to authorized management hosts only. At the host firewall level (using `nftables` or `iptables`), allow:

- Port **8007/tcp** (PBS web interface and API) from management hosts only
- Port **22/tcp** (SSH) from management hosts only
- All traffic from the backup VLAN (10.20.0.0/24) to PBS for backup operations

Example `/etc/nftables.conf` additions:

```
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Allow established connections
        ct state established,related accept

        # Allow loopback
        iif lo accept

        # Allow ICMP
        ip protocol icmp accept

        # PBS web interface - management hosts only
        tcp dport 8007 ip saddr 192.168.1.0/24 accept

        # SSH - management hosts only
        tcp dport 22 ip saddr 192.168.1.0/24 accept

        # Backup traffic from PVE backup VLAN
        iifname "eno2" accept

        # Drop everything else
        drop
    }
}
```

Apply with:

```bash
systemctl enable nftables
systemctl restart nftables
nft list ruleset
```

---

## Part 5: Connecting Proxmox VE to PBS

With PBS configured, connect your Proxmox VE cluster to it.

### Add PBS as a Storage Backend in PVE

In the Proxmox VE web interface:

1. Navigate to **Datacenter** → **Storage** → **Add** → **Proxmox Backup Server**
2. Fill in:
   - **ID:** A short name for this storage, e.g., `pbs-local`
   - **Server:** The PBS backup traffic IP or hostname, e.g., `10.20.0.50`
   - **Username:** `pve-backup@pbs!pve-token` (the API token ID created earlier)
   - **Password:** The API token secret
   - **Datastore:** `local-backup` (the PBS datastore name)
   - **Fingerprint:** Paste the PBS server's TLS fingerprint (shown on the PBS dashboard under **Administration** → **Server Administration** → **Certificates**)

The fingerprint is required to verify the PBS server's identity and prevent man-in-the-middle attacks.

You can retrieve the fingerprint from the PBS command line:

```bash
proxmox-backup-manager cert info | grep Fingerprint
```

3. Optionally set **Namespace** if you want to organize backups from different PVE clusters within the same datastore.
4. Click **Add**

### Verify the Connection

After adding PBS as storage, verify that PVE can list the datastore contents:

1. Navigate to **Datacenter** → **Storage** → select your PBS storage → **Content**
2. The content tab should load without errors

If you receive a connection error, verify:
- Network connectivity from the PVE node to `10.20.0.50:8007`
- The API token ID and secret are entered correctly
- The TLS fingerprint matches

### Schedule Backup Jobs

In the Proxmox VE web interface, schedule backups for your VMs:

1. Navigate to **Datacenter** → **Backup** → **Add**
2. Configure:
   - **Storage:** `pbs-local` (your PBS storage)
   - **Schedule:** Choose an appropriate schedule (e.g., `daily`, `Mon-Fri 02:00`)
   - **Selection:** Select which VMs to include (all, or specific VMs by node)
   - **Mode:** `Snapshot` is recommended — it creates consistent backups without stopping the VM
   - **Compression:** `ZSTD` (best balance of speed and compression ratio)
   - **Encryption:** Enable and configure an encryption key if desired
   - **Prune:** Set retention policy that matches your PBS datastore prune policy
3. Click **Create**

---

## Part 6: Encryption

PBS supports client-side encryption, meaning data is encrypted before it leaves the Proxmox VE node. The PBS server stores only ciphertext — not even the backup server operator can read the backup contents without the encryption key.

### Generating an Encryption Key

On the PBS server or on a PVE node:

```bash
proxmox-backup-client key create --kdf scrypt
```

This generates a key file (typically `~/.config/proxmox-backup/encryption-key.json`) that is itself password-protected using scrypt key derivation.

### Backing Up the Encryption Key

**This is critical.** If you lose the encryption key, you permanently lose access to all backups encrypted with it. Store the key in at least two separate, secure locations:

```bash
# Export the key to a file for safekeeping
proxmox-backup-client key show-master-pubkey

# Or export the encrypted key file
cat ~/.config/proxmox-backup/encryption-key.json
```

Store this in:
- Your password manager (as a secure note)
- Offline cold storage (printed and locked away, or on an air-gapped USB drive)

### Configuring Encryption in PVE Backup Jobs

When creating or editing a backup job in PVE:

1. Under **Encryption**, select **Use a client-side encryption key**
2. Upload or paste the encryption key

All subsequent backups for that job will be encrypted before transmission.

> **Important:** If you enable encryption after backups already exist, new backups will be encrypted but old backups will not. Maintain clarity about which backups are encrypted.

---

## Part 7: Verification and Monitoring

A backup that has never been tested is an untested backup. Verification is not optional — it is part of the backup process.

### Running Backup Verification

PBS can verify the integrity of stored backups by re-reading all data and checking it against stored checksums:

**In the web interface:** Navigate to your datastore → **Verify All** to run a full integrity check.

**From the command line:**

```bash
# Verify all backups in a datastore
proxmox-backup-manager verify local-backup

# Verify a specific backup
proxmox-backup-client snapshot verify local-backup:vm/100/2026-01-15T02:00:00Z
```

Schedule automatic verification to run periodically — weekly is a reasonable starting point.

### Testing Restore

Do not wait for a disaster to discover that your backups do not restore correctly. Establish a regular restore test schedule:

1. In the PVE web interface, navigate to a VM → **Backups**
2. Select a recent backup from PBS
3. Click **Restore** and choose a different VM ID (so the original is not affected)
4. Verify that the restored VM boots and functions correctly
5. Delete the test VM after verification

A quarterly restore test for each critical VM is a minimum baseline.

### Monitoring Backup Job Status

PBS provides job status and history in the web interface under each datastore. For active monitoring, PBS exposes metrics that can be scraped by Prometheus:

```bash
# PBS has a built-in metrics endpoint
curl -k https://10.20.0.50:8007/metrics
```

A basic monitoring approach using the PBS API:

```bash
# Check last backup status via API
curl -k -H "Authorization: PBSAPIToken=pve-backup@pbs!pve-token:your-token-secret" \
  https://10.20.0.50:8007/api2/json/admin/datastore/local-backup/snapshots
```

Integrate this with your monitoring stack (Grafana, Prometheus, or a simple alerting script) to receive notifications when backup jobs fail.

### Email Notifications

Configure PBS to send email notifications for failed jobs:

```bash
# Set the notification email address
proxmox-backup-manager node-config update --email admin@yourdomain.com

# Configure an external SMTP relay if needed
proxmox-backup-manager notification config smtp set --from noreply@yourdomain.com --server smtp.yourdomain.com
```

In the web interface: **Administration** → **Server Administration** → **Notifications**.

---

## Part 8: Offsite Sync and Disaster Recovery

A local backup is not a complete backup strategy. Hardware failures, fires, theft, or ransomware can affect your backup server at the same time as your primary infrastructure. An offsite copy is essential.

### Syncing to a Remote PBS Instance

If you have access to a second location (a friend's homelab, a VPS, a colocation facility), you can run a second PBS instance and sync to it:

```bash
# On the primary PBS, create a sync job to a remote PBS
proxmox-backup-manager sync-job create offsite-sync \
  --store local-backup \
  --remote offsite-pbs \
  --remote-store backup-mirror \
  --schedule daily \
  --remove-vanished true
```

The remote PBS must be configured as a **Remote** in the primary PBS settings: **Administration** → **Remotes** → **Add**.

### Syncing to S3-Compatible Storage

For cloud offsite backup, PBS supports syncing to any S3-compatible storage provider (AWS S3, Backblaze B2, Wasabi, MinIO):

```bash
# Install the S3 sync tool (if not present)
apt install proxmox-backup-file-restore

# Configure S3 credentials
# (handled through the PBS tape/remote configuration)
```

The S3 sync capability is available through third-party tools or by mounting an S3-compatible bucket via S3FS and treating it as a second PBS datastore target.

### The 3-2-1 Backup Rule

Apply the 3-2-1 rule to your backup strategy:

- **3** copies of data (production + 2 backups)
- **2** different storage media (e.g., local disk + remote disk)
- **1** offsite copy (geographically separate)

PBS covers the local backup copy. Ensure the other two requirements are met through remote sync, cloud storage, or tape.

---

## Part 9: System Hardening

### Update Management

Keep PBS updated regularly. Security patches are delivered through the standard Debian package management system:

```bash
# Update package lists
apt update

# Review available updates
apt list --upgradable

# Apply updates
apt upgrade -y

# Apply distribution-level updates when available
apt dist-upgrade -y
```

Set up unattended security updates for the OS:

```bash
apt install unattended-upgrades apt-listchanges
dpkg-reconfigure -plow unattended-upgrades
```

Configure `/etc/apt/apt.conf.d/50unattended-upgrades` to enable security updates automatically while holding back PBS-specific packages that should be reviewed before updating.

### SSH Hardening

Edit `/etc/ssh/sshd_config` to apply these settings:

```
# Disable root login over SSH (use sudo from a non-root user, or use the web interface)
PermitRootLogin no

# Disable password authentication (require SSH keys)
PasswordAuthentication no
PubkeyAuthentication yes

# Restrict to specific users if appropriate
AllowUsers youradminuser

# Use modern crypto
Protocol 2
```

Then create a non-root admin user and add your SSH public key:

```bash
# Create admin user
useradd -m -s /bin/bash adminuser
usermod -aG sudo adminuser

# Add SSH public key
mkdir -p /home/adminuser/.ssh
echo "ssh-ed25519 AAAA... your@publickey" >> /home/adminuser/.ssh/authorized_keys
chmod 700 /home/adminuser/.ssh
chmod 600 /home/adminuser/.ssh/authorized_keys
chown -R adminuser:adminuser /home/adminuser/.ssh

# Restart SSH
systemctl restart sshd
```

### TLS Certificate Management

The default PBS installation uses a self-signed certificate. For production use, replace it with a certificate from Let's Encrypt or your internal CA:

**Using ACME (Let's Encrypt) via PBS:**

In the PBS web interface: **Administration** → **Server Administration** → **Certificates** → **ACME**.

Configure an ACME account and domain, then issue the certificate. PBS will handle automatic renewal.

**For internal CA (recommended for homelab):**

```bash
# Install your CA certificate
cp your-ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

# Replace the PBS certificate
cp your-server.crt /etc/proxmox-backup/proxy.pem
cp your-server.key /etc/proxmox-backup/proxy.key
systemctl restart proxmox-backup-proxy
```

### Disable Unnecessary Services

Review running services and disable anything not required:

```bash
# List all enabled services
systemctl list-unit-files --state=enabled

# Disable services that are not needed
# (Evaluate each one — do not blindly disable without understanding the service)
```

---

## Part 10: Operational Best Practices Summary

| Practice | Recommendation |
|----------|----------------|
| **Least privilege** | Service accounts use API tokens with minimum required role (`DatastoreBackup`). Never use root credentials for routine operations. |
| **Separation of concerns** | PBS runs on dedicated hardware, not as a VM on the cluster it backs up. |
| **Network isolation** | Backup traffic uses a dedicated VLAN, firewalled from the management and VM networks. |
| **Encryption** | Enable client-side encryption for sensitive data. Back up the encryption key separately from the backups themselves. |
| **Retention policies** | Define prune policies that match your recovery objectives. Schedule garbage collection to reclaim freed storage. |
| **Integrity verification** | Schedule weekly automatic verification. Run ad-hoc verification after any significant system event. |
| **Restore testing** | Test restores quarterly for critical VMs. Document the restore procedure so it is not being figured out during an incident. |
| **Monitoring** | Set up email notifications for job failures. Integrate with your monitoring stack. |
| **Updates** | Apply security updates promptly. Schedule update windows rather than ignoring available updates. |
| **SSH hardening** | Disable password authentication. Use SSH keys. Disable root login. |
| **TLS certificates** | Replace self-signed certificates with CA-issued or ACME-issued certificates. |
| **Offsite copy** | Maintain at least one geographically separate copy of backup data. |
| **Documentation** | Document your PBS configuration, encryption keys location, and restore procedures. Review and update documentation when configuration changes. |

---

## Conclusion

Proxmox Backup Server is a mature, capable backup solution that integrates tightly with Proxmox VE while remaining straightforward enough to operate without specialized backup expertise. The features — deduplication, compression, encryption, integrity verification, and a clean web interface — make it a natural choice for anyone already running a Proxmox-based homelab or small business infrastructure.

The technical steps are only part of the story, though. The practices matter more than the installation: keeping backups on separate hardware, isolating backup traffic, enforcing least-privilege access, verifying backup integrity regularly, and maintaining an offsite copy are what transform a working backup system into one you can actually rely on when things go wrong.

Set it up once, configured correctly. Automate the routine operations. Test restores. And then go back to breaking things — knowing the net is there.

---

### Further Reading

- [Proxmox Backup Server Documentation](https://pbs.proxmox.com/docs/index.html)
- [Proxmox Backup Server Downloads](https://www.proxmox.com/en/downloads/proxmox-backup-server)
- [ZFS on Linux Documentation](https://openzfs.github.io/openzfs-docs/)
- [PBS REST API Reference](https://pbs.proxmox.com/docs/api-viewer/index.html)
