---
title: "Building a Proxmox Cluster with Ceph Storage and High Availability"
date: 2026-02-28
draft: false
description: "A step-by-step guide to setting up multiple Proxmox VE nodes, configuring Ceph distributed storage, clustering them together, and enabling high availability for your VMs"
summary: "Learn how to build a production-grade homelab or small business cluster using Proxmox VE, Ceph storage, and high availability - with clear explanations of the concepts along the way"
tags: ["proxmox", "ceph", "high-availability", "clustering", "homelab", "storage", "virtualization"]
---

# Building a Proxmox Cluster with Ceph Storage and High Availability

Running virtual machines on a single server is convenient, but it comes with a critical weakness: if that server fails, everything goes down. By clustering multiple Proxmox servers together and backing them with Ceph distributed storage, you create a system where virtual machines can survive the failure of a physical node — automatically, without any manual intervention.

This guide walks you through the entire process, from bare-metal Proxmox installs to a fully operational high-availability cluster. Along the way, we'll explain the *why* behind each step so you understand what you're building, not just how to build it.

## What We'll Build

By the end of this guide you'll have:

- **Three Proxmox VE nodes** joined into a single cluster
- **Ceph** providing distributed, replicated storage across all nodes
- **High availability** so VMs automatically migrate to a surviving node when one fails

### Why Three Nodes?

Three is the minimum recommended count for both Proxmox clustering and Ceph. This comes down to **quorum**: a majority of nodes must agree before taking action. With three nodes:

- One can fail and the remaining two still form a majority (2 out of 3)
- Ceph keeps at least two copies of every data block, so losing one node doesn't lose data

With only two nodes, the cluster cannot determine which node failed and which is healthy (a "split-brain" scenario), so it refuses to act at all. Always use an odd number of nodes — three is the practical minimum.

## Prerequisites

Before you begin, prepare the following:

- **Three physical servers** (or three powerful VMs if you're testing — though nested virtualization reduces performance and is not recommended for production)
- Each server should have:
  - At minimum **8 GB RAM** (16 GB+ recommended for production)
  - At minimum **two disks**: one for the Proxmox OS, one or more dedicated to Ceph (SSDs strongly recommended for Ceph)
  - **Two network interfaces** recommended: one for management/VM traffic, one dedicated to Ceph storage replication
- A **switch** connecting all three nodes (ideally two switches for redundancy, but one works for a homelab)
- A **DHCP server** or planned static IPs for each node

### Planned Network Layout

| Node     | Management IP   | Ceph/Storage IP   |
|----------|-----------------|-------------------|
| pve1     | 192.168.1.11/24 | 10.10.10.11/24    |
| pve2     | 192.168.1.12/24 | 10.10.10.12/24    |
| pve3     | 192.168.1.13/24 | 10.10.10.13/24    |

*Adjust these ranges to suit your network. The Ceph network is a dedicated private network used only for storage replication traffic — keeping it separate from VM traffic is strongly recommended.*

## Part 1: Installing Proxmox VE on Each Node

### What Is Proxmox VE?

Proxmox Virtual Environment (PVE) is an open-source server virtualisation platform built on Debian Linux. It supports two types of virtualisation:

- **KVM (Kernel-based Virtual Machine)**: full hardware virtualisation for running any operating system
- **LXC (Linux Containers)**: lightweight containers that share the host kernel, great for Linux-only workloads

The web interface makes managing virtual machines, containers, storage, and networking straightforward, while the underlying tools give you full control via the command line.

### Install Proxmox VE

1. Download the latest Proxmox VE ISO from [https://www.proxmox.com/en/downloads](https://www.proxmox.com/en/downloads)
2. Write it to a USB drive (use Balena Etcher or `dd`)
3. Boot from the USB on each server and follow the installer

During installation on each node:
- Set a **hostname** that matches your plan: `pve1.yourdomain.local`, `pve2.yourdomain.local`, `pve3.yourdomain.local`
- Set a **static IP** on the management interface
- Use the OS disk only for the Proxmox install — leave your Ceph disks untouched

Once installed, access the web interface at `https://<node-ip>:8006`.

### Remove the Subscription Nag (Optional)

Proxmox is free to use but shows a "no valid subscription" warning by default. To remove it on each node:

```bash
sed -i.bak "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy
```

### Configure the Network

Proxmox manages network configuration through `/etc/network/interfaces`. On each node, confirm you have a bridge interface (`vmbr0`) for VMs and, if using a separate Ceph network, add a second interface:

```bash
# /etc/network/interfaces on pve1
auto lo
iface lo inet loopback

auto ens18
iface ens18 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.1.11/24
    gateway 192.168.1.1
    bridge-ports ens18
    bridge-stp off
    bridge-fd 0

# Dedicated Ceph/storage network
auto ens19
iface ens19 inet static
    address 10.10.10.11/24
```

Apply changes with:

```bash
systemctl restart networking
```

Repeat this on `pve2` (using `.12`) and `pve3` (using `.13`), adjusting the addresses accordingly.

### Update Each Node

Before clustering, bring all nodes up to date:

```bash
apt update && apt full-upgrade -y
```

---

## Part 2: Creating the Proxmox Cluster

### What Is a Proxmox Cluster?

A Proxmox cluster is a group of Proxmox nodes that share a common configuration and communicate through a dedicated cluster network. Once clustered:

- You manage all nodes from a **single web interface**
- VMs and containers can be **live-migrated** between nodes
- The cluster can automatically **restart VMs** on another node if one node fails (high availability)
- **Shared storage** (like Ceph) becomes available across all nodes

The cluster communication uses **Corosync**, a messaging layer that keeps all nodes in sync and tracks which nodes are alive (the "heartbeat"). Corosync is what enforces quorum — without a majority of nodes agreeing, the cluster takes no action that could cause a split-brain.

### Create the Cluster on the First Node

Log in to `pve1` via SSH or the web shell and create the cluster:

```bash
pvecm create my-proxmox-cluster
```

Verify it was created:

```bash
pvecm status
```

You should see:

```text
Cluster information
-------------------
Name:             my-proxmox-cluster
Config Version:   1
Transport:        knet
Secure auth:      on

Quorum information
------------------
Date:             ...
Quorum provider:  corosync_votequorum
Nodes:            1
Node ID:          0x00000001
Ring ID:          1.1
Quorate:          Yes

Votequorum information
----------------------
Expected votes:   1
Highest expected: 1
Total votes:      1
Quorum:           1
Flags:            Quorate
```

The cluster currently has only one node and thus has quorum (1/1). Adding more nodes will change this.

### Join pve2 and pve3 to the Cluster

On `pve2`, join the cluster by pointing at `pve1`:

```bash
pvecm add 192.168.1.11
```

You'll be prompted for pve1's root password. After joining, repeat on `pve3`:

```bash
# On pve3
pvecm add 192.168.1.11
```

After both nodes have joined, verify the cluster status from any node:

```bash
pvecm status
```

Expected output:

```text
Cluster information
-------------------
Name:             my-proxmox-cluster
Config Version:   3
Transport:        knet
Secure auth:      on

Quorum information
------------------
Nodes:            3
Quorate:          Yes

Votequorum information
----------------------
Expected votes:   3
Highest expected: 3
Total votes:      3
Quorum:           2
Flags:            Quorate
```

The cluster now requires **2 out of 3 votes** to be quorate (have quorum). If pve2 goes offline, pve1 and pve3 still have 2 votes and remain functional. If two nodes go offline simultaneously, the remaining node loses quorum and stops making decisions.

You can also verify from the web interface — open `https://192.168.1.11:8006` and in the left-hand tree you'll see all three nodes under your cluster name.

---

## Part 3: Configuring Ceph Storage

### What Is Ceph?

Ceph is an open-source, software-defined storage system designed to provide excellent performance, reliability, and scalability. In the context of a Proxmox cluster it gives you:

- **Distributed storage**: data is spread across all nodes, so there's no single storage box that becomes a bottleneck or point of failure
- **Automatic replication**: Ceph keeps multiple copies of every data block (typically 3). If one node's disk dies, Ceph reconstructs the lost copy on another disk — automatically
- **No single point of failure**: losing one node or one disk does not cause data loss or downtime
- **Shared storage without a SAN**: VMs stored on Ceph can be live-migrated between nodes because all nodes can read and write the same storage pool

Ceph has several key components:

| Component | Role |
|-----------|------|
| **MON (Monitor)** | Tracks the cluster map — which OSDs exist, which are up, and where data lives. Needs an odd number (3 recommended). |
| **OSD (Object Storage Daemon)** | One per disk. Actually stores the data. OSDs replicate data among themselves. |
| **MGR (Manager)** | Provides additional monitoring, metrics, and the dashboard. |
| **MDS (Metadata Server)** | Only needed for CephFS (shared filesystems). Not required for block storage. |

Proxmox integrates Ceph directly — you can deploy and manage it entirely through the web interface or command line.

### Install Ceph on All Nodes

Run this on **each node** (or use the Proxmox web UI under **Node → Ceph → Install Ceph**):

```bash
pveceph install --repository no-subscription
```

> **Note**: The `no-subscription` repository is suitable for testing and home labs but does **not** receive security patches as promptly as the enterprise repository and carries no official support SLA. For production environments with a valid Proxmox subscription, replace `no-subscription` with `enterprise` and ensure your subscription key is configured in `/etc/apt/auth.conf.d/`.

Verify the installation:

```bash
ceph --version
```

### Initialise Ceph on the First Node

On `pve1`, initialise Ceph and specify the network to use for Ceph replication traffic:

```bash
pveceph init --network 10.10.10.0/24
```

This creates the initial Ceph configuration file at `/etc/ceph/ceph.conf` and sets up the dedicated storage network. Using a separate network for Ceph traffic keeps storage replication from competing with your VM network traffic.

### Create Monitors

Monitors track the cluster map. Create one on each node:

```bash
# On pve1
pveceph mon create

# On pve2
pveceph mon create

# On pve3
pveceph mon create
```

Check monitor status:

```bash
ceph mon stat
```

Expected output:

```text
e3: 3 mons at {pve1=10.10.10.11:6789/0,pve2=10.10.10.12:6789/0,pve3=10.10.10.13:6789/0}, election epoch 6, leader pve1, quorum pve1,pve2,pve3
```

### Create Managers

The Manager daemon provides additional metrics and the Ceph dashboard. Create one on each node for redundancy:

```bash
# On pve1
pveceph mgr create

# On pve2
pveceph mgr create

# On pve3
pveceph mgr create
```

Verify:

```bash
ceph mgr stat
```

### Add OSDs (Object Storage Daemons)

Each OSD corresponds to one physical disk. This is where your actual data will live. Identify the disks you want to use for Ceph on each node — **do not use the disk running Proxmox**.

List available disks on a node:

```bash
lsblk
```

For this example, assume each node has a dedicated SSD at `/dev/sdb`.

**On each node**, create an OSD for each Ceph disk:

```bash
# Replace /dev/sdb with your actual disk path
pveceph osd create /dev/sdb
```

If you have multiple disks per node (e.g., `/dev/sdb`, `/dev/sdc`, `/dev/sdd`), repeat for each:

```bash
pveceph osd create /dev/sdc
pveceph osd create /dev/sdd
```

More OSDs mean more storage capacity and better performance — Ceph stripes data across all OSDs.

Check OSD status:

```bash
ceph osd stat
```

You should see something like:

```text
9 osds: 9 up, 9 in
```

(9 OSDs = 3 nodes × 3 disks each)

Also check overall health:

```bash
ceph health detail
```

A healthy cluster reports `HEALTH_OK`. If you see `HEALTH_WARN`, read the message — the most common early warning is too few placement groups, which Ceph typically resolves automatically.

### Create a Ceph Storage Pool

A **pool** is a logical partition within Ceph. VMs store their disk images in pools. Create a pool named `vm-storage`:

```bash
pveceph pool create vm-storage --add_storages true
```

The `--add_storages true` flag automatically registers this pool as a storage backend in Proxmox, making it available immediately for VM disk images.

Set the replication size (default is 3, meaning 3 copies of every block):

```bash
ceph osd pool set vm-storage size 3
ceph osd pool set vm-storage min_size 2
```

- **size 3**: three copies of every object (one per node in a 3-node cluster)
- **min_size 2**: the cluster remains writable as long as at least 2 copies are available, ensuring you can survive one node failure without losing write access

Verify the pool:

```bash
ceph osd lspools
```

### Understanding Placement Groups

Proxmox and Ceph will automatically manage placement groups (PGs) in modern versions (Ceph Nautilus and later). If you're running an older version, you may need to set PG counts manually. For modern installations, the auto-scaler handles this for you.

Confirm the auto-scaler is running:

```bash
ceph osd pool autoscale-status
```

### Verify Ceph Health

At this point your Ceph cluster should be healthy:

```bash
ceph -s
```

Expected output:

```text
  cluster:
    id:     <uuid>
    health: HEALTH_OK

  services:
    mon: 3 daemons, quorum pve1,pve2,pve3 (age 10m)
    mgr: pve1(active, since 5m), standbys: pve2, pve3
    osd: 9 osds: 9 up (since 3m), 9 in (since 3m)

  data:
    pools:   1 pools, 1 pgs
    objects: 0 objects, 0 B
    usage:   700 MiB used, 2.7 TiB / 2.7 TiB avail
    pgs:     1 active+clean
```

---

## Part 4: Configuring High Availability

### What Is High Availability?

High Availability (HA) means that if a Proxmox node fails, the virtual machines running on it are automatically started on another node in the cluster. From the user's perspective, the VMs simply restart (there is typically a brief outage while the new node detects the failure and boots the VM) — no manual intervention required.

Proxmox HA has two components:

- **HA Manager**: monitors which VMs should be running and where, and orchestrates migrations and restarts
- **Fencing**: before restarting a VM on another node, Proxmox must ensure the original node is truly down. Without fencing, a VM could end up running on two nodes simultaneously, corrupting its data. Fencing "shoots the other node in the head" (STONITH — Shoot The Other Node In The Head) to guarantee it cannot access shared storage

Ceph is what makes HA practical: because all VMs are stored on Ceph (shared across all nodes), any node can immediately access the VM's disk image and start it.

### Configure Fencing (Watchdog)

Proxmox uses a **hardware watchdog** or a **software watchdog** for fencing. The simplest approach for a homelab is the software watchdog built into Linux (`/dev/watchdog`):

On **each node**, load the watchdog module and configure it:

```bash
echo "softdog" >> /etc/modules-load.d/softdog.conf
modprobe softdog
```

Verify the watchdog device is available:

```bash
ls -la /dev/watchdog
```

In a production environment, use **IPMI/iDRAC/iLO** (hardware management interfaces) for fencing instead. This ensures that even if the OS is unresponsive, the management interface can hard-power-cycle the failed node. Configure this in the Proxmox datacenter fencing options under **Datacenter → Options → HA Settings**.

### Create an HA Group

An **HA group** defines which nodes can run a VM and in what priority order. Create a group that includes all three nodes:

In the Proxmox web interface:

1. Navigate to **Datacenter → HA → Groups**
2. Click **Create**
3. Set the **Group ID** to `ha-group`
4. Add `pve1`, `pve2`, and `pve3` as members
5. Optionally set priorities (higher number = higher priority; the HA manager prefers to run VMs on higher-priority nodes)

Via the command line:

```bash
ha-manager groupadd ha-group --nodes pve1:100,pve2:90,pve3:80
```

The numbers after the colon are priorities. When multiple nodes are available, the HA manager picks the one with the highest priority. This lets you control where VMs prefer to run.

### Enable HA for a VM

For each VM you want to protect with HA:

1. In the web interface, select the VM
2. Navigate to **More → Manage HA**
3. Set **State** to `started`
4. Select your **HA Group** (`ha-group`)
5. Set **Max Restart** (how many times the HA manager should try restarting the VM)
6. Set **Max Relocate** (how many times it should try migrating before declaring a failure)

Via the command line (replace `100` with your VM ID):

```bash
ha-manager add vm:100 --group ha-group --state started --max_restart 3 --max_relocate 1
```

List all HA-managed resources:

```bash
ha-manager status
```

### Understanding HA States

The HA manager tracks several states for each resource:

| State | Meaning |
|-------|---------|
| `started` | VM should be running; HA will start/restart it if it's not |
| `stopped` | VM should be stopped; HA will not start it automatically |
| `enabled` | HA manages the VM but follows the VM's current power state |
| `disabled` | HA is configured but currently ignoring the VM |
| `error` | HA attempted the configured number of restarts and failed |

### Test Failover

Before relying on HA in production, test it:

1. Create a test VM stored on your Ceph pool (`vm-storage`)
2. Enable HA for it
3. Verify it's running on one of the nodes (e.g., pve1)
4. Simulate a node failure by cutting power to pve1, or by running:

   > ⚠️ **WARNING — DESTRUCTIVE COMMAND**: The command below immediately crashes the kernel with no warning or graceful shutdown. It will corrupt any writes in-flight on the local OS disk and terminate all running processes on pve1 instantly. Only run this on a dedicated test node that you are willing to hard-reboot, and **never** on a node holding data that is not replicated elsewhere.

   ```bash
   # On pve1 — forces a kernel panic, simulating a hard crash
   echo 1 > /proc/sys/kernel/sysrq
   echo c > /proc/sysrq-trigger
   ```

5. Watch the HA manager react:

   ```bash
   # From pve2 or pve3
   ha-manager status
   # Watch the HA log
   journalctl -fu pve-ha-lrm
   ```

6. After a short period (typically 1–2 minutes while the cluster detects the failure and fences the node), the VM should appear running on pve2 or pve3

7. Power pve1 back on — it will rejoin the cluster automatically

### Monitor the Cluster

Proxmox provides several ways to monitor cluster and HA health:

```bash
# Overall cluster status
pvecm status

# HA manager status
ha-manager status

# Ceph health
ceph -s

# Check which node each VM is running on
qm list   # For VMs
pct list  # For containers
```

In the web interface, the **Datacenter** view shows cluster health at a glance, and each node's **Summary** tab shows resource usage.

---

## Part 5: Storage Best Practices and Tuning

### Use SSDs for Ceph OSDs

Spinning hard drives work with Ceph, but performance suffers significantly because Ceph's random I/O patterns are hard on HDDs. For a homelab or production cluster, use SSDs or NVMe drives as OSDs.

If you have a mix of fast (NVMe) and slow (HDD) drives, you can configure Ceph to use the fast drives as a **write-ahead log (WAL)** and **database (DB)** cache for the slow OSDs, improving performance significantly:

```bash
# Create OSD using /dev/sdb (HDD) with /dev/nvme0n1 as WAL/DB
pveceph osd create /dev/sdb --db-dev /dev/nvme0n1 --wal-dev /dev/nvme0n1
```

### Dedicated Ceph Network

Always use a separate network interface for Ceph replication traffic. Ceph can be very chatty — every write to a VM disk triggers replication across all three nodes. Without a dedicated network, Ceph traffic can saturate your management/VM network.

A dedicated 10 Gbps network for Ceph is ideal. Even a separate 1 Gbps network helps significantly compared to sharing with VM traffic.

### Ceph Replication Factor

The default replication factor of 3 (one copy per node) is appropriate for a 3-node cluster. If you add nodes later, you can increase this for even more redundancy, or create pools with different replication factors for different use cases (e.g., a pool with replication 2 for less-critical data, saving space).

---

## Part 6: Networking for High Availability

For true high availability, your network itself should not be a single point of failure. Consider:

- **Link aggregation (bonding)**: combine two physical network interfaces into one logical interface for redundancy and/or increased throughput

  ```bash
  # /etc/network/interfaces — bonding example
  auto bond0
  iface bond0 inet manual
      bond-slaves ens18 ens19
      bond-mode active-backup
      bond-miimon 100

  auto vmbr0
  iface vmbr0 inet static
      address 192.168.1.11/24
      gateway 192.168.1.1
      bridge-ports bond0
      bridge-stp off
      bridge-fd 0
  ```

- **Multiple switches**: connect each node to two different switches so a switch failure doesn't isolate a node

- **Corosync on a dedicated interface**: keep cluster heartbeat traffic on a separate network from VM traffic and Ceph traffic

---

## Part 7: Backup Strategy

HA protects against node failure but is not a substitute for backups. A VM can still be lost due to data corruption, accidental deletion, or application errors — all of which Ceph will faithfully replicate across all copies.

### Configure Proxmox Backup Server (PBS)

Proxmox Backup Server is a dedicated backup solution that integrates tightly with Proxmox VE. It supports:

- **Incremental backups**: only changed data is transferred after the first full backup
- **Deduplication**: identical blocks are stored once across all backups
- **Encryption**: backups can be encrypted client-side

Install PBS on a separate server (not on the cluster nodes themselves, so a node failure doesn't take out your backups), then add it as a storage backend in Proxmox:

1. In the Proxmox web interface, go to **Datacenter → Storage → Add → Proxmox Backup Server**
2. Enter the PBS server address, credentials, and datastore name

Then create a backup schedule:

1. Go to **Datacenter → Backup**
2. Click **Add**
3. Select the storage (your PBS instance)
4. Set the schedule (e.g., daily at 02:00)
5. Select the VMs to back up (or select all)
6. Set the retention policy (how many backups to keep)

---

## Troubleshooting Common Issues

### Cluster Loses Quorum

**Symptom**: VMs stop, web interface becomes unresponsive or read-only

**Cause**: Fewer than 2 nodes can communicate with each other

**Resolution**:

```bash
# Check which nodes are reachable
pvecm nodes

# If a node is permanently gone and you need to remove it:
pvecm delnode pve3

# After removing a dead node, re-establish quorum if needed.
# CAUTION: Only run this when you are 100% certain the missing node(s) are
# permanently offline and cannot rejoin the cluster. Lowering expected votes
# while a "missing" node is still alive and can access shared storage risks a
# split-brain condition — two nodes independently believing they are the sole
# active master and making conflicting changes to your VMs and Ceph data.
pvecm expected 2   # Temporarily lower expected votes (use with caution)
```

### Ceph Health Warnings

**HEALTH_WARN: nn pg(s) degraded**

This means Ceph is missing some data copies, usually because an OSD is down. Check OSD status:

```bash
ceph osd stat
ceph osd tree
```

If an OSD is `down`, try restarting it:

```bash
systemctl restart ceph-osd@<osd-id>
```

**HEALTH_WARN: clock skew detected**

Ceph requires all nodes to have closely synchronised clocks. Ensure NTP is running:

```bash
timedatectl status
systemctl enable --now systemd-timesyncd
```

### HA VM Not Migrating

If a VM is not automatically migrating after a node failure:

1. Check the HA manager logs: `journalctl -fu pve-ha-crm`
2. Verify the watchdog is functional: `ls -la /dev/watchdog`
3. Confirm the VM is stored on Ceph (not on local node storage)
4. Ensure the HA resource is in `started` state: `ha-manager status`

A common mistake is creating a VM on local storage (`local-lvm`) instead of Ceph. Local storage cannot be accessed by other nodes, so HA cannot migrate the VM. Always store HA-protected VMs on Ceph or another shared storage backend.

### Node Cannot Rejoin Cluster

If a node was offline and cannot rejoin:

```bash
# On the node trying to rejoin, restart cluster services
systemctl restart corosync
systemctl restart pve-cluster

# Check corosync log for errors
journalctl -u corosync -n 50
```

---

## Summary

Here's what you've built:

| Layer | Technology | What It Does |
|-------|-----------|--------------|
| Virtualisation | Proxmox VE | Runs VMs and containers |
| Clustering | Corosync + pvecm | Keeps nodes in sync, enforces quorum |
| Shared Storage | Ceph | Distributed, replicated block storage |
| High Availability | Proxmox HA Manager | Automatically restarts VMs after node failure |
| Fencing | Watchdog / IPMI | Prevents split-brain by ensuring failed nodes cannot access storage |

With this stack, you can:

- **Lose any single node** without losing access to your VMs (they restart on surviving nodes)
- **Lose any single disk** without losing data (Ceph replicates across nodes)
- **Perform maintenance** on a node without downtime (live-migrate VMs first, then work on the node)
- **Scale out** by adding more nodes to both the Proxmox cluster and the Ceph cluster

### Next Steps

Once your cluster is running smoothly, consider:

- **Adding more nodes**: Ceph and Proxmox both scale horizontally — just add a node and let Ceph rebalance data automatically
- **Monitoring**: deploy Prometheus and Grafana with the Proxmox and Ceph exporters for detailed metrics and alerting
- **Infrastructure as Code**: manage your VMs with OpenTofu/Terraform using the Proxmox provider (see our [OpenTofu on Proxmox](/posts/2026-02-07-opentofu-proxmox/) post)
- **Automated backups**: configure Proxmox Backup Server with offsite replication for disaster recovery
- **VLAN segmentation**: separate management, VM, and storage traffic onto dedicated VLANs for security and performance

### Additional Resources

- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Ceph Documentation](https://docs.ceph.com/en/latest/)
- [Proxmox Ceph Guide](https://pve.proxmox.com/wiki/Deploy_Hyper-Converged_Ceph_Cluster)
- [Proxmox High Availability](https://pve.proxmox.com/wiki/High_Availability)
- [Corosync Documentation](https://corosync.github.io/corosync/)

---

*Have questions or want to share your cluster setup? Leave a comment below or reach out — we'd love to hear what you're building.*
