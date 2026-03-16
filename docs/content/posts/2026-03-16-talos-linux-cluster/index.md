---
title: "Deploying a Talos Linux Kubernetes Cluster with a Shared Control-Plane VIP"
date: 2026-03-16
draft: false
description: "Step-by-step guide to quickly bootstrapping a production-ready Talos Linux cluster with 3 control-plane nodes sharing a Virtual IP and 1 worker node"
summary: "Learn how to spin up a minimal but highly available Talos Linux Kubernetes cluster — 3 control-plane nodes sharing a VIP and 1 worker node — using talosctl from Sidero Labs"
tags: ["talos", "kubernetes", "homelab", "sidero", "infrastructure", "cluster"]
---

# Deploying a Talos Linux Kubernetes Cluster with a Shared Control-Plane VIP

[Talos Linux](https://www.talos.dev/) by [Sidero Labs](https://www.siderolabs.com/) is an immutable, minimal operating system purpose-built for running Kubernetes. It replaces the traditional Linux userspace with a gRPC API, has no SSH, no shell, and no package manager — making it extremely secure and easy to maintain at scale.

In this post we will bootstrap a small but highly available cluster:

| Role | Count | Details |
|---|---|---|
| Control Plane | 3 | Shares a single Virtual IP (VIP) |
| Worker | 1 | Regular workload node |

The three control-plane nodes will all advertise the same **Virtual IP (VIP)**. Talos handles VIP natively through a built-in leader-election mechanism using the etcd cluster, so you get a stable API server endpoint without needing an external load balancer.

## Architecture Overview

```
         ┌──────────────────────────────────────────────────┐
         │              VIP: 192.168.1.50                   │
         │        (Kubernetes API Server endpoint)           │
         └──────┬──────────────┬──────────────┬─────────────┘
                │              │              │
         ┌──────┴──────┐ ┌─────┴──────┐ ┌────┴───────┐
         │  cp-01      │ │  cp-02     │ │  cp-03     │
         │ 192.168.1.51│ │192.168.1.52│ │192.168.1.53│
         │ Control     │ │ Control    │ │ Control    │
         │ Plane       │ │ Plane      │ │ Plane      │
         └─────────────┘ └────────────┘ └────────────┘

         ┌─────────────────────────┐
         │  worker-01              │
         │  192.168.1.61           │
         │  Worker                 │
         └─────────────────────────┘
```

### Network Plan

| Node | IP Address | Role |
|---|---|---|
| VIP | `192.168.1.50` | Kubernetes API Server (shared) |
| cp-01 | `192.168.1.51` | Control Plane |
| cp-02 | `192.168.1.52` | Control Plane |
| cp-03 | `192.168.1.53` | Control Plane |
| worker-01 | `192.168.1.61` | Worker |

*Adjust these addresses to match your own network.*

---

## Prerequisites

- A machine running Linux or macOS with internet access (your workstation)
- `talosctl` installed (see below)
- `kubectl` installed
- Four bare-metal machines, VMs (Proxmox, VMware, Hyper-V), or cloud instances booted from the Talos ISO
- A free IP on your LAN to act as the VIP (`192.168.1.50` in this guide)

### Install talosctl

```bash
# Latest release
curl -sL https://talos.dev/install | sh

# Verify
talosctl version --client
```

Or install a specific version:

```bash
TALOS_VERSION=v1.9.4
curl -Lo /usr/local/bin/talosctl \
  "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-$(uname -s | tr '[:upper:]' '[:lower:]')-amd64"
chmod +x /usr/local/bin/talosctl
```

---

## Step 1 — Boot the Nodes from the Talos ISO

Download the Talos ISO for your platform from the [Talos Image Factory](https://factory.talos.dev/) or directly from GitHub releases:

```bash
TALOS_VERSION=v1.9.4
curl -LO "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talos-amd64.iso"
```

Boot all four machines from this ISO. They will start in **maintenance mode** — a minimal state where they wait for configuration to be applied. No installation happens yet.

Once booted, each node will display its IP address on the console. You can also discover them with:

```bash
talosctl disks --insecure --nodes 192.168.1.51
```

---

## Step 2 — Generate Machine Configurations

Use `talosctl gen config` to create the base configuration for the cluster. The `--config-patch` flags are used inline here; alternatively you can maintain separate patch files.

```bash
talosctl gen config my-cluster https://192.168.1.50:6443 \
  --output-dir ./clusterconfig
```

This creates three files:

- `clusterconfig/controlplane.yaml` — base config for all control-plane nodes
- `clusterconfig/worker.yaml` — base config for all worker nodes
- `clusterconfig/talosconfig` — client config for `talosctl`

---

## Step 3 — Configure the VIP and Per-Node IPs

Talos supports VIP natively via the `vip` field in the network interface configuration. We will create a **patch file for each node** that sets the node's static IP, and a **shared control-plane patch** that adds the VIP.

### Shared control-plane VIP patch

Create `patch-cp-vip.yaml`:

```yaml
machine:
  network:
    interfaces:
      - interface: eth0
        vip:
          ip: 192.168.1.50
```

> **How VIP works in Talos**: when a control-plane node holds the etcd leadership it also holds the VIP. If the leader fails, another node wins the etcd election and takes over the VIP within seconds — no external keepalived or VRRP daemon required.

### Per-node static IP patches

**`patch-cp-01.yaml`**:

```yaml
machine:
  network:
    hostname: cp-01
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.51/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
        vip:
          ip: 192.168.1.50
  install:
    disk: /dev/sda
```

**`patch-cp-02.yaml`**:

```yaml
machine:
  network:
    hostname: cp-02
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.52/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
        vip:
          ip: 192.168.1.50
  install:
    disk: /dev/sda
```

**`patch-cp-03.yaml`**:

```yaml
machine:
  network:
    hostname: cp-03
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.53/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
        vip:
          ip: 192.168.1.50
  install:
    disk: /dev/sda
```

**`patch-worker-01.yaml`**:

```yaml
machine:
  network:
    hostname: worker-01
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.61/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
  install:
    disk: /dev/sda
```

> **Tip**: set `install.disk` to the correct block device for your nodes. Use `talosctl disks --insecure --nodes <ip>` to list available disks while a node is in maintenance mode.

---

## Step 4 — Apply Configuration to Each Node

Apply the base control-plane config merged with each node's patch while the nodes are in maintenance mode (`--insecure` is needed before certificates are established):

```bash
# Control-plane node 1
talosctl apply-config --insecure \
  --nodes 192.168.1.51 \
  --file clusterconfig/controlplane.yaml \
  --config-patch @patch-cp-01.yaml

# Control-plane node 2
talosctl apply-config --insecure \
  --nodes 192.168.1.52 \
  --file clusterconfig/controlplane.yaml \
  --config-patch @patch-cp-02.yaml

# Control-plane node 3
talosctl apply-config --insecure \
  --nodes 192.168.1.53 \
  --file clusterconfig/controlplane.yaml \
  --config-patch @patch-cp-03.yaml

# Worker node
talosctl apply-config --insecure \
  --nodes 192.168.1.61 \
  --file clusterconfig/worker.yaml \
  --config-patch @patch-worker-01.yaml
```

After receiving the configuration each node will:

1. Write the config to disk
2. Install Talos to the configured disk
3. Reboot into the installed system

You can watch the installation progress:

```bash
talosctl dmesg --nodes 192.168.1.51 --follow
```

---

## Step 5 — Configure talosctl Endpoint

Tell `talosctl` to use the generated client credentials and target the cluster through the VIP:

```bash
export TALOSCONFIG=./clusterconfig/talosconfig

talosctl config endpoint 192.168.1.50
talosctl config node 192.168.1.51 192.168.1.52 192.168.1.53
```

You can also point to one of the real control-plane IPs initially (before the VIP is live):

```bash
talosctl config endpoint 192.168.1.51
```

---

## Step 6 — Bootstrap the Cluster

Once all three control-plane nodes have finished installing and rebooted, bootstrap etcd on **exactly one** control-plane node (run this command only once):

```bash
talosctl bootstrap --nodes 192.168.1.51
```

After a few moments etcd starts, the API server comes online, and the VIP (`192.168.1.50`) becomes active on whichever node wins the leadership election.

Watch the nodes come up:

```bash
talosctl health --nodes 192.168.1.51,192.168.1.52,192.168.1.53,192.168.1.61 \
  --control-plane-nodes 192.168.1.51,192.168.1.52,192.168.1.53 \
  --worker-nodes 192.168.1.61
```

---

## Step 7 — Retrieve the kubeconfig

```bash
talosctl kubeconfig --nodes 192.168.1.51 ./kubeconfig
export KUBECONFIG=./kubeconfig
```

Verify the cluster is healthy:

```bash
kubectl get nodes -o wide
```

Expected output:

```
NAME        STATUS   ROLES           AGE   VERSION   INTERNAL-IP    OS-IMAGE   KERNEL-VERSION   CONTAINER-RUNTIME
cp-01       Ready    control-plane   5m    v1.32.x   192.168.1.51   Talos      ...              containerd://...
cp-02       Ready    control-plane   5m    v1.32.x   192.168.1.52   Talos      ...              containerd://...
cp-03       Ready    control-plane   5m    v1.32.x   192.168.1.53   Talos      ...              containerd://...
worker-01   Ready    <none>          4m    v1.32.x   192.168.1.61   Talos      ...              containerd://...
```

```bash
kubectl get pods -A
```

All system pods in `kube-system` should reach `Running` or `Completed` state.

---

## Step 8 — Install a CNI Plugin

Talos does not ship a CNI. Install one before pods can schedule. [Cilium](https://cilium.io/) is a popular choice:

```bash
# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -Lo /usr/local/bin/cilium \
  "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64"
chmod +x /usr/local/bin/cilium

# Deploy Cilium
cilium install --version 1.17.2

# Wait for Cilium to be ready
cilium status --wait
```

Alternatively, install [Flannel](https://github.com/flannel-io/flannel) or [Calico](https://www.tigera.io/project-calico/) — any CNI compatible with Kubernetes works.

---

## Verifying VIP Failover

Simulate a control-plane failure to verify that the VIP migrates:

```bash
# Gracefully shut down cp-01 (the current VIP holder)
talosctl shutdown --nodes 192.168.1.51

# Immediately poll the API server through the VIP
kubectl --server=https://192.168.1.50:6443 get nodes
```

Within a few seconds the VIP is claimed by one of the remaining control-plane nodes and API calls continue to succeed. Bring cp-01 back:

```bash
# Power cp-01 back on physically/via your hypervisor, then
talosctl health --nodes 192.168.1.52
```

cp-01 will rejoin the etcd cluster automatically.

---

## Useful talosctl Commands

```bash
# List services on a node
talosctl services --nodes 192.168.1.51

# Read node logs
talosctl logs --nodes 192.168.1.51 kubelet

# Show disk usage
talosctl df --nodes 192.168.1.51

# Get etcd members
talosctl etcd members --nodes 192.168.1.51

# Upgrade Talos on a node (rolling)
talosctl upgrade --nodes 192.168.1.51 \
  --image ghcr.io/siderolabs/installer:v1.9.4

# Upgrade Kubernetes
talosctl upgrade-k8s --to 1.33.0 \
  --nodes 192.168.1.51
```

---

## Conclusion

You now have a minimal yet highly available Kubernetes cluster powered by Talos Linux:

✅ **Immutable OS** — no SSH, no shell, attack surface drastically reduced  
✅ **3 control-plane nodes** — survives the loss of any single control-plane node  
✅ **Shared VIP** — single stable endpoint for `kubectl` and workloads  
✅ **API-driven management** — all changes go through `talosctl`  
✅ **Easy upgrades** — Talos and Kubernetes upgraded with one command per node  

### Next Steps

- **GitOps**: manage cluster state with [Flux](https://fluxcd.io/) or [ArgoCD](https://argo-cd.readthedocs.io/)
- **Storage**: add [Longhorn](https://longhorn.io/) or [Rook-Ceph](https://rook.io/) for persistent volumes
- **Ingress**: deploy [Traefik](https://traefik.io/) or [ingress-nginx](https://kubernetes.github.io/ingress-nginx/)
- **Secrets**: integrate [External Secrets Operator](https://external-secrets.io/) with a vault backend
- **Observability**: set up the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) for metrics and alerting

### Additional Resources

- [Talos Linux Documentation](https://www.talos.dev/latest/)
- [Talos Image Factory](https://factory.talos.dev/)
- [Sidero Labs GitHub](https://github.com/siderolabs)
- [Talos VIP documentation](https://www.talos.dev/latest/talos-guides/network/vip/)
- [talosctl CLI reference](https://www.talos.dev/latest/reference/cli/)

---

*Have questions or feedback? Drop a comment below or reach out — always happy to discuss homelab adventures!*
