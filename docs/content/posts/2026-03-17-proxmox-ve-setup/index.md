---
title: "Proxmox VE: Installation, Best Practices, Clustering, and High Availability"
date: 2026-03-17
draft: true
description: "A comprehensive guide to installing Proxmox Virtual Environment on bare-metal nodes, applying security and networking best practices, building a cluster, and enabling high availability"
summary: "From bare-metal to production-grade virtualisation: this guide walks through Proxmox VE installation, user and account management, VLAN networking, cluster formation, HA configuration, and the operational recommendations that separate a hobbyist setup from a resilient homelab or small-business infrastructure."
tags: ["proxmox", "homelab", "virtualization", "clustering", "high-availability", "networking", "vlan", "security", "linux", "infrastructure"]
---

Proxmox Virtual Environment (PVE) is an open-source, enterprise-grade virtualisation platform built on Debian Linux. It bundles KVM (full hardware virtualisation), LXC (lightweight Linux containers), software-defined networking, and a polished web interface into a single cohesive stack. The result is a platform that is genuinely capable of running production workloads while remaining accessible to homelab operators who want to learn infrastructure the right way.

This guide takes you from an empty server to a fully configured, clustered, high-availability Proxmox deployment — with the best-practice configuration decisions that are easy to skip but important to get right from the start.

## Prerequisites

Before you touch a server, gather the following:

- **Hardware**: at minimum three physical nodes for a proper cluster with quorum. Each node should have at least 16 GB RAM, a dedicated OS disk (SSD recommended), and at least one additional disk or set of disks for VM storage. Two network interfaces per node is strongly recommended — one for management and VM traffic, one for cluster/storage replication.
- **Network**: a managed switch that supports 802.1Q VLANs. Unmanaged switches can work for a basic setup, but VLAN support opens up critical isolation capabilities.
- **A planned IP scheme**: know your management network subnet, your storage/cluster network subnet, and your VLAN ranges before you begin. Changing these after the fact is painful.
- **A USB drive** (8 GB or larger) to write the installer image.
- **DNS**: hostnames should resolve. Either a local DNS server or entries in `/etc/hosts` on each node will do.

### Planned Network Layout

The examples in this guide use the following layout — adjust to match your own environment:

| Node  | Hostname              | Management IP    | Cluster/Storage IP |
|-------|-----------------------|------------------|--------------------|
| pve1  | pve1.lab.internal     | 192.168.10.11/24 | 10.10.10.11/24     |
| pve2  | pve2.lab.internal     | 192.168.10.12/24 | 10.10.10.12/24     |
| pve3  | pve3.lab.internal     | 192.168.10.13/24 | 10.10.10.13/24     |

- `192.168.10.0/24` — management network, accessible from your workstation
- `10.10.10.0/24` — dedicated cluster heartbeat and storage replication network, isolated from everything else

---

## Part 1: Installing Proxmox VE

### Download and Write the ISO

Download the latest stable Proxmox VE ISO from [proxmox.com/en/downloads](https://www.proxmox.com/en/downloads). At the time of writing the current release is Proxmox VE 8.x, built on Debian 12 (Bookworm).

Write the ISO to a USB drive:

```bash
# On Linux/macOS — replace /dev/sdX with your USB device
dd if=proxmox-ve_*.iso of=/dev/sdX bs=4M status=progress && sync
```

On Windows, use [Rufus](https://rufus.ie) or [balenaEtcher](https://www.balena.io/etcher/) in DD mode.

### Run the Installer

Boot each node from the USB drive. The Proxmox installer is graphical and straightforward, but pay close attention to a few settings:

1. **Target disk**: select only the OS disk. If you have dedicated storage or Ceph disks, leave them untouched.
2. **Filesystem**: ZFS RAID-1 (mirrored) is a good choice if you have two disks you want to use as an OS mirror. Otherwise, `ext4` on a single disk is fine for the OS — you can use ZFS on your data disks separately.
3. **Hostname**: set a fully-qualified hostname that matches your plan — `pve1.lab.internal`. This is used for cluster membership and is annoying to change later.
4. **Management IP**: set a static IP on the management interface. The installer will configure this for you; confirm the address, gateway, and DNS server are correct.
5. **Root password and email**: set a strong root password. The email address is used for system alerts from `pvemailforward`.

After installation, each node is accessible at `https://<management-ip>:8006`.

### First Login and Initial Checks

Log in to the web interface using `root` and the password you set during installation. You will see a "no valid subscription" banner — this is expected for the free/community tier. We address this below.

Verify the node is healthy:

```bash
# Check PVE version and kernel
pveversion -v

# Check storage status
pvesm status

# Check services
systemctl list-units --state=failed
```

---

## Part 2: Post-Installation Best Practices

These steps should be applied to every node before clustering. Taking shortcuts here produces technical debt that compounds as the environment grows.

### Configure the Package Repositories

Proxmox ships with an enterprise repository configured by default. If you are not a paying subscriber, this repository will produce errors during updates. Switch to the community (no-subscription) repository:

```bash
# Disable the enterprise repository
echo "# disabled enterprise repo" > /etc/apt/sources.list.d/pve-enterprise.list

# Add the no-subscription (community) repository
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list

# Also disable the Ceph enterprise repo if you do not subscribe
echo "# disabled enterprise ceph repo" > /etc/apt/sources.list.d/ceph.list
```

Then update and upgrade:

```bash
apt update && apt full-upgrade -y
```

Reboot if the kernel was updated:

```bash
reboot
```

### Remove the Subscription Nag (Optional)

The web UI shows a modal "no valid subscription" dialog on every login. Remove it with:

```bash
sed -i.bak "s/data.status !== 'Active'/false/g" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy
```

This patches the client-side JavaScript check. The patch survives until the next `proxmox-widget-toolkit` package update, at which point you need to reapply it.

### Install Useful Tools

```bash
apt install -y \
  htop \
  iotop \
  iftop \
  lsof \
  tmux \
  curl \
  wget \
  vim \
  nmap \
  ethtool \
  net-tools \
  dnsutils \
  qemu-guest-agent
```

The `qemu-guest-agent` package is important: install it inside guest VMs as well so Proxmox can communicate with them for clean shutdown, IP reporting, and file system freeze during snapshots.

---

## Part 3: User and Account Management

Running your entire environment as `root` is both a security risk and an operational hazard — one errant command away from something catastrophic. Proxmox has a proper permissions model; use it.

### Understand the Permission Model

Proxmox uses a role-based access control (RBAC) system with the following concepts:

- **Users**: individual accounts. Proxmox supports both local PAM accounts (`user@pam`) and its own internal accounts (`user@pve`). PAM accounts map to Linux system users; PVE accounts exist only in the Proxmox database.
- **Groups**: collections of users that share permissions. Assign roles to groups rather than individual users.
- **Roles**: named bundles of privileges (e.g., `Administrator`, `PVEVMUser`, `PVEAuditor`).
- **Permissions**: a triple of (path, role, propagation) — who can do what on which resource.
- **API Tokens**: scoped credentials for automation, with their own permission assignments, independent of user sessions.

### Create an Administrative Account

Create a dedicated administrator account rather than using `root`:

```bash
# Create a PVE user for your personal admin account
pveum user add admin@pve --comment "Primary administrator" --email "you@example.com"

# Set a strong password
pveum passwd admin@pve

# Create an admin group
pveum group add administrators --comment "Full administrators"

# Assign the built-in Administrator role to the group at the root path
pveum acl modify / --group administrators --role Administrator

# Add the admin user to the group
pveum user modify admin@pve --group administrators
```

After creating this account, verify you can log in as `admin@pve` via the web UI before locking down `root`.

### Create Operational Groups and Roles

Segment access based on responsibility:

```bash
# Group for users who can only view the cluster
pveum group add auditors --comment "Read-only auditors"
pveum acl modify / --group auditors --role PVEAuditor

# Group for users who can manage VMs but not cluster configuration
pveum group add vm-operators --comment "VM operators"
pveum acl modify /vms --group vm-operators --role PVEVMAdmin
pveum acl modify /storage --group vm-operators --role PVEDatastoreUser
```

Create users and assign them to groups:

```bash
pveum user add alice@pve --comment "Alice - VM operator"
pveum passwd alice@pve
pveum user modify alice@pve --group vm-operators
```

### Use API Tokens for Automation

Never use a root password or personal user credentials in automation scripts, Terraform providers, or CI/CD pipelines. Use API tokens with the minimum required permissions.

Create a dedicated user for automation, then create a token for it:

```bash
# Create a dedicated automation user
pveum user add automation@pve --comment "Terraform/automation account"

# Create a custom role with only the permissions needed
pveum role add TerraformProvisioner \
  --privs "Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,Pool.Allocate,Sys.Audit,Sys.Console,Sys.Modify,VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Migrate,VM.Monitor,VM.PowerMgmt,SDN.Use"

# Assign the role
pveum acl modify / --user automation@pve --role TerraformProvisioner

# Create an API token — note the secret is shown only once
pveum user token add automation@pve terraform --privsep 1
```

The `--privsep 1` flag enables privilege separation, meaning the token cannot have more permissions than the user, even if the user's permissions change. Store the token secret in a secrets manager (Vault, Bitwarden, GitHub Actions secrets) immediately — it is not retrievable later.

### Enable Two-Factor Authentication (TOTP)

For all human accounts, require TOTP as a second factor. Each user can configure this themselves through the web UI under **Datacenter** → **Permissions** → **Two Factor**. As an administrator, you can also enforce a 2FA policy:

```bash
# Require 2FA for all users (Proxmox VE 7.2+)
pveum tfa policy set --require-2fa true
```

Users will be prompted to enrol a TOTP app on next login.

---

## Part 4: Network Configuration

Proxmox manages network configuration through `/etc/network/interfaces`. The web UI provides a network editor, but understanding the underlying configuration is essential.

### Network Concepts in Proxmox

- **Linux Bridge (`vmbr`)**: a virtual switch that VMs and containers connect to. At minimum you need one (`vmbr0`) bridging to your physical interface.
- **VLAN-aware bridge**: a single bridge that carries multiple VLANs, with VLAN tagging handled by the guest or by the bridge itself.
- **Bond**: combines two physical interfaces into one logical interface for redundancy or additional throughput.
- **VLAN interface**: a sub-interface on a physical or bond interface tagged with a specific VLAN ID.

### Basic Bridge Configuration

A minimal `/etc/network/interfaces` for `pve1` with a management bridge and a separate cluster/storage interface:

```
auto lo
iface lo inet loopback

# Physical uplink — no IP, passes all traffic to the bridge
auto ens18
iface ens18 inet manual

# Management bridge — VMs and management traffic
auto vmbr0
iface vmbr0 inet static
    address 192.168.10.11/24
    gateway 192.168.10.1
    bridge-ports ens18
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094

# Dedicated cluster/storage network — no gateway
auto ens19
iface ens19 inet static
    address 10.10.10.11/24
```

The `bridge-vlan-aware yes` and `bridge-vids 2-4094` lines make `vmbr0` VLAN-aware, so you can assign VMs to specific VLANs without creating separate bridges for each one.

Apply changes:

```bash
systemctl restart networking
# or use the safer ifreload from ifupdown2
ifreload -a
```

### Bond Configuration for Redundancy

If each node has two physical uplinks, bond them for failover:

```
auto bond0
iface bond0 inet manual
    bond-slaves ens18 ens19
    bond-miimon 100
    bond-mode active-backup
    bond-primary ens18

auto vmbr0
iface vmbr0 inet static
    address 192.168.10.11/24
    gateway 192.168.10.1
    bridge-ports bond0
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
```

`active-backup` mode uses one interface at a time and switches to the backup if the primary fails — no switch-side LACP configuration needed.

### VLAN Configuration

With a VLAN-aware bridge, assign VMs to VLANs by setting the VLAN tag in the VM's network device configuration. For example, VM 100 on VLAN 20:

- In the VM's **Hardware** tab, select the network device
- Set **VLAN Tag** to `20`

The bridge handles the tagging. The VM itself sees untagged traffic on its network interface.

For services that need to span multiple VLANs (e.g., a firewall VM acting as a router), assign multiple network devices to the VM, each with a different VLAN tag.

### Software-Defined Networking (SDN)

Proxmox 7.0+ includes an SDN subsystem under **Datacenter** → **SDN** that allows you to create virtual networks (VNets) backed by VXLAN or EVPN, with centrally managed IPAM. This is the direction Proxmox networking is heading for multi-node setups.

To enable SDN:

```bash
apt install -y libpve-network-perl ifupdown2
```

Then configure VNets and zones through the web UI. SDN is particularly powerful for multi-tenant environments where you need isolated networks per project or team without pre-configuring VLANs on every switch.

---

## Part 5: Storage Configuration

### Storage Types

Proxmox supports multiple storage backends:

| Type         | Use Case                                  | Multi-node |
|--------------|-------------------------------------------|------------|
| `dir`        | Local directory — simple, default         | No         |
| `lvm`        | Local LVM volume group                    | No         |
| `lvmthin`    | Local thin-provisioned LVM                | No         |
| `zfspool`    | Local ZFS dataset — snapshots, checksums  | No         |
| `nfs`        | Shared NFS mount                          | Yes        |
| `ceph/rbd`   | Distributed Ceph block storage            | Yes        |
| `cephfs`     | Distributed Ceph file system              | Yes        |
| `pbs`        | Proxmox Backup Server                     | Yes        |

For a single node, ZFS thin pools are an excellent local storage choice — they support snapshots, self-healing checksums, compression, and efficient cloning.

For a cluster with shared storage, Ceph (installed and managed directly within Proxmox) is the recommended choice. See the companion post [Building a Proxmox Cluster with Ceph Storage and High Availability](/posts/2026-02-28-proxmox-cluster-ceph-ha/) for a full Ceph walkthrough.

### Create a ZFS Pool

If your node has one or more data disks separate from the OS disk, create a ZFS pool:

```bash
# Single disk — no redundancy, maximum capacity
zpool create -f -o ashift=12 data /dev/sdb

# Mirror — redundancy across two disks
zpool create -f -o ashift=12 data mirror /dev/sdb /dev/sdc

# RAIDZ1 — one parity disk across three or more
zpool create -f -o ashift=12 data raidz1 /dev/sdb /dev/sdc /dev/sdd
```

Enable compression (nearly always a win with modern CPUs):

```bash
zfs set compression=lz4 data
```

Add the pool to Proxmox:

- **Datacenter** → **Storage** → **Add** → **ZFS**
- Select your pool and set **Content** to include `Disk image` and `Container`.

---

## Part 6: Security Hardening

### Restrict SSH Access

The root SSH login that was enabled during installation should be locked down:

```bash
# Create a dedicated SSH key pair on your workstation
ssh-keygen -t ed25519 -C "pve-admin"

# Copy the public key to each node
ssh-copy-id -i ~/.ssh/pve-admin.pub root@192.168.10.11
```

Then edit `/etc/ssh/sshd_config` on each node:

```
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
AllowUsers root
MaxAuthTries 3
```

Restart sshd:

```bash
systemctl restart sshd
```

If you have created a non-root admin user that can `sudo`, you can go further and set `PermitRootLogin no`.

### Configure the Firewall

Proxmox has a built-in, cluster-aware firewall. Enable it at the datacenter level and define rules centrally:

1. **Datacenter** → **Firewall** → **Options** → set **Enable** to `Yes`
2. Add input rules to allow only what is needed on the management interface:
   - SSH (port 22) from your management VLAN only
   - HTTPS (port 8006) from your management VLAN only
   - Cluster traffic (ports 5404–5405 UDP for Corosync) between nodes
3. Set the default policy to **DROP** for input once your allow rules are in place.

Via CLI on each node:

```bash
# Enable the host firewall
pvesh set /nodes/pve1/firewall/options --enable 1

# Allow SSH from the management network
pvesh create /nodes/pve1/firewall/rules \
  --action ACCEPT --type in --proto tcp --dport 22 \
  --source 192.168.10.0/24 --comment "SSH from management"

# Allow PVE web UI
pvesh create /nodes/pve1/firewall/rules \
  --action ACCEPT --type in --proto tcp --dport 8006 \
  --source 192.168.10.0/24 --comment "PVE web UI from management"
```

### Limit Datacenter-Level API Access

Under **Datacenter** → **Options**, set:

- **Keyboard Layout**: match your keyboard to avoid lockout issues.
- **Console Viewer**: `xterm.js` works reliably over HTTPS without additional ports.
- **HTTP Proxy**: if your nodes route internet traffic through a proxy, set it here for package updates.

### Audit Logs

Proxmox logs all API and user actions. Review them:

```bash
# Recent task history
pvesh get /cluster/tasks

# Authentication log
journalctl -u pvedaemon --since "1 hour ago"

# General syslog
journalctl --since "1 hour ago" | grep -i "pve\|proxmox"
```

---

## Part 7: Building the Cluster

A Proxmox cluster connects multiple nodes under a single management interface and enables live migration and high availability. Clusters require an odd number of nodes (minimum three) for quorum.

### Network Considerations Before Clustering

Cluster communication runs over Corosync, which uses ports **5404 and 5405 UDP**. This traffic should ideally use the dedicated cluster network (`10.10.10.0/24` in our example), not the management network.

Ensure all nodes can reach each other on both networks:

```bash
# From pve1, test connectivity to pve2 and pve3
ping -c 3 10.10.10.12
ping -c 3 10.10.10.13

# Verify hostnames resolve (add to /etc/hosts if not using local DNS)
echo "10.10.10.11 pve1.lab.internal pve1" >> /etc/hosts
echo "10.10.10.12 pve2.lab.internal pve2" >> /etc/hosts
echo "10.10.10.13 pve3.lab.internal pve3" >> /etc/hosts
```

### Create the Cluster on the First Node

On `pve1`, create the cluster with the cluster network as the Corosync link:

```bash
pvecm create homelab-cluster --link0 10.10.10.11
```

Verify:

```bash
pvecm status
```

You should see the cluster name, one node, and quorum status `Yes`.

### Join Additional Nodes

On `pve2`, join the cluster:

```bash
pvecm add 192.168.10.11 --link0 10.10.10.12
```

You will be prompted for `pve1`'s root password. Repeat on `pve3`:

```bash
pvecm add 192.168.10.11 --link0 10.10.10.13
```

After all three nodes join, verify from any node:

```bash
pvecm nodes
```

Output should list all three nodes. The web UI on any node will now show the full cluster.

### Two Corosync Links (Recommended)

Using two separate network paths for Corosync increases resilience. Configure a second link using the management network as a fallback:

```bash
# When creating the cluster (pve1)
pvecm create homelab-cluster --link0 10.10.10.11 --link1 192.168.10.11

# When joining (pve2)
pvecm add 192.168.10.11 --link0 10.10.10.12 --link1 192.168.10.12
```

Corosync uses `link0` as the primary and falls back to `link1` if it loses connectivity.

---

## Part 8: High Availability

High Availability (HA) in Proxmox means that if a node fails, the VMs running on it are automatically started on a surviving node. HA requires shared storage (so the surviving node can access the VM's disk) and quorum (so the cluster can agree on what happened).

### How HA Works

1. Corosync detects that a node has stopped responding (missed heartbeats).
2. The cluster reaches quorum (majority of nodes agree the node is gone).
3. The HA manager fences the failed node (if configured) to guarantee it is truly offline.
4. The HA manager starts the VM on another node using the shared storage.

**Fencing** is the process of forcibly powering off or resetting a node to prevent it from accidentally writing to shared storage while the cluster thinks it is dead (the "split-brain" scenario). Without fencing, data corruption is possible. For homelab use, fencing is often skipped, but the trade-off is that HA may refuse to act if it cannot be certain the failed node is offline.

### Enable HA on a VM

Once the cluster has shared storage, enable HA for a VM through the web UI:

1. Select the VM in the cluster view.
2. Go to **More** → **Manage HA**.
3. Set **State** to `started` and choose the **HA Group** (if you have created one).
4. Click **Add**.

Via CLI:

```bash
ha-manager add vm:100 --state started --max_restart 3 --max_relocate 1
```

- `--state started`: the VM should always be running
- `--max_restart 3`: try to restart the VM up to 3 times before giving up
- `--max_relocate 1`: try to migrate to another node once before declaring failure

Check HA status:

```bash
ha-manager status
```

### HA Groups

HA groups let you control which nodes are preferred or permitted for a VM's failover:

```bash
# Create an HA group that prefers pve1 and pve2 over pve3
ha-manager groupadd group-web \
  --nodes "pve1:2,pve2:2,pve3:1" \
  --comment "Web VMs — prefer pve1 and pve2"

# Assign a VM to the group
ha-manager set vm:100 --group group-web
```

The number after the colon is the priority (higher = more preferred). Nodes not in the list will not host the VM at all.

### Watchdog Configuration

Proxmox uses a software watchdog by default (`softdog`). If your hardware supports an IPMI/hardware watchdog, configure it:

```bash
# Check for hardware watchdog
ls /dev/watchdog*

# If a hardware watchdog exists, load its module (varies by hardware)
modprobe iTCO_wdt
echo "iTCO_wdt" >> /etc/modules
```

Edit `/etc/default/pve-ha-manager`:

```
WATCHDOG_MODULE=iTCO_wdt
```

Restart the HA services:

```bash
systemctl restart pve-ha-crm pve-ha-lrm
```

---

## Part 9: Additional Recommendations

### Backups with Proxmox Backup Server

Proxmox Backup Server (PBS) is a dedicated backup appliance (also open-source) that integrates natively with PVE. It supports incremental, deduplicated, compressed backups and allows individual file restoration from VM images without restoring the entire VM.

Run PBS as a VM on a separate node (or a separate machine entirely) to ensure backups survive node failures. Avoid backing up to the same node the VMs run on.

Set up a scheduled backup policy under **Datacenter** → **Backup** → **Add**:

- **Schedule**: `daily` at a low-traffic time
- **Selection**: all VMs, or specific pools
- **Storage**: your PBS datastore
- **Mode**: `snapshot` (no downtime) for VMs with quiesced filesystems; `suspend` if your guest does not support snapshots cleanly
- **Retention**: set daily, weekly, and monthly limits to control disk usage

### Monitoring with Prometheus and Grafana

Proxmox does not ship with a monitoring stack, but it exposes metrics in several ways:

- **Built-in metrics server**: under **Datacenter** → **Metric Server**, configure push to InfluxDB or Graphite.
- **Prometheus via PVE exporter**: install [prometheus-pve-exporter](https://github.com/prometheus-pve/prometheus-pve-exporter) on a monitoring host and scrape it with Prometheus.

A basic Grafana dashboard for Proxmox is available in the Grafana dashboard library (search for "Proxmox VE").

### Automate with Ansible

Managing configuration across three or more nodes by hand is error-prone and slow. Use Ansible to enforce consistent configuration:

```yaml
# Example play: ensure all nodes have the no-subscription repo
- name: Configure Proxmox community repository
  hosts: proxmox_nodes
  become: true
  tasks:
    - name: Disable enterprise repository
      copy:
        content: "# disabled"
        dest: /etc/apt/sources.list.d/pve-enterprise.list

    - name: Enable no-subscription repository
      apt_repository:
        repo: "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription"
        filename: pve-no-subscription
        state: present

    - name: Upgrade all packages
      apt:
        update_cache: yes
        upgrade: full
```

A community Ansible role, [lae.proxmox](https://github.com/lae/ansible-role-proxmox), handles many common configuration tasks including cluster formation and user management.

### Infrastructure as Code with OpenTofu/Terraform

For provisioning VMs reproducibly, use the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox) OpenTofu/Terraform provider. See the companion post [Deploying Virtual Machines on Proxmox with OpenTofu](/posts/2026-02-07-opentofu-proxmox/) for a full guide.

### Resource Management and Overcommit

Proxmox allows memory and CPU overcommit — assigning more vCPUs or RAM to VMs than physically exists. This is normal and expected for development environments but requires monitoring in production:

- **CPU**: overcommit is common. A 4-core host can safely run eight 2-vCPU VMs if they are not all CPU-bound simultaneously.
- **Memory**: overcommit is risky. Enable KSM (Kernel Same-page Merging) to reduce actual memory consumption:

  ```bash
  echo 1 > /sys/kernel/mm/ksm/run
  echo 1000 > /sys/kernel/mm/ksm/sleep_millisecs
  ```

  Add to `/etc/rc.local` or a systemd unit to persist across reboots.

- **Storage**: thin provisioning allows overcommit of disk space. Monitor actual usage with `pvesm status` and `zpool list`.

### Keep Nodes in Maintenance Mode When Updating

Before applying updates to a node in a running cluster, place it in maintenance mode to migrate VMs off first:

```bash
# Migrate all VMs away from pve1 before updating
for vm in $(qm list | awk 'NR>1 {print $1}'); do
  qm migrate $vm pve2 --online
done

# Then update and reboot
apt update && apt full-upgrade -y
reboot
```

For a proper zero-downtime upgrade flow, use the **Node** → **Shell** → migrate, then update, then return the node to service.

### Regularly Test Your HA and Backups

HA and backups are only useful if they actually work when needed. Test them:

```bash
# Simulate a node failure by stopping the HA daemon and watching failover
systemctl stop pve-ha-crm
# Watch another node pick up the VM within a few minutes

# Test a backup restore by restoring a non-critical VM to a different ID
pvesm restore vm 9999 /path/to/backup.vma.zst \
  --storage local-zfs --unique 1
```

Schedule backup restore tests quarterly. Document the results.

---

## Conclusion

A well-configured Proxmox environment is a genuinely capable platform — one that handles production-grade workloads while remaining transparent and manageable. The investment in getting the foundation right pays dividends every time you add a new VM, expand the cluster, or need to recover from a failure.

The decisions that matter most come early: proper hostnames and IP planning, a dedicated cluster network, RBAC from day one, and VLAN-aware networking. Everything else — HA tuning, backup schedules, monitoring integration — can be refined over time.

Build it right the first time, document what you built, and then push the environment further than you expect it to go. That is when you learn the most.

---

*For deeper coverage of Ceph storage and distributed HA, see [Building a Proxmox Cluster with Ceph Storage and High Availability](/posts/2026-02-28-proxmox-cluster-ceph-ha/). For automating VM provisioning with Infrastructure as Code, see [Deploying Virtual Machines on Proxmox with OpenTofu](/posts/2026-02-07-opentofu-proxmox/).*
