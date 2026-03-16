---
title: "Deploying a Talos Linux Kubernetes Cluster with a Shared Control-Plane VIP"
date: 2026-03-16
draft: true
description: "Step-by-step guide to building a small Talos Linux cluster with 3 control-plane nodes, a shared API VIP, and 1 worker node"
summary: "Build a practical Talos Linux 1.12 cluster with a highly available control plane, a shared VIP, static node networking, and a simple post-bootstrap CNI install"
tags: ["talos", "kubernetes", "homelab", "sidero", "infrastructure", "cluster"]
---

[Talos Linux](https://docs.siderolabs.com/talos/v1.12/overview/what-is-talos) by [Sidero Labs](https://www.siderolabs.com/) is an immutable operating system built specifically for Kubernetes. It replaces the traditional Linux userspace with an API-driven management model: no SSH, no shell, and no package manager on the host.  This post walks through how to deploy a small footprint kubernetes cluster for testing and homelabbing.

## Architecture Overview

The three control-plane nodes share a single **Virtual IP (VIP)** for the Kubernetes API. Talos manages that VIP natively, so you get one stable endpoint for `kubectl` and automation without standing up a separate load balancer first.

In practice, I recommend using both a DNS name and the raw VIP address:

- DNS name for day-to-day access, bookmarks, and kubeconfig readability
- VIP address for bootstrap, troubleshooting, and as the backing target for that DNS record

This version of the guide is aligned with **Talos 1.12.5** and **Kubernetes 1.35.2**.

{{< mermaid >}}
flowchart TB
  vip["API Endpoint<br/>talos-api.lab.example<br/>192.168.1.50"]

  subgraph cp["Control Plane"]
    cp1["cp-01.lab.example<br/>192.168.1.51"]
    cp2["cp-02.lab.example<br/>192.168.1.52"]
    cp3["cp-03.lab.example<br/>192.168.1.53"]
  end

  worker["worker-01.lab.example<br/>192.168.1.61"]

  vip --> cp1
  vip --> cp2
  vip --> cp3
  cp1 --> worker
  cp2 --> worker
  cp3 --> worker
{{< /mermaid >}}

Publish `talos-api.lab.example` in your DNS so it resolves to the VIP address. The per-node records are optional, but they make troubleshooting easier.

*Adjust these names and IP addresses to match your own network.*

## Prerequisites

- A machine running workstation (Linux)
- `talosctl` installed
- `kubectl` installed
- A DNS record for the Kubernetes API such as `talos-api.lab.example` pointing to the VIP

### Install talosctl

For other platforms, use the official [talosctl installation guide](https://docs.siderolabs.com/talos/v1.12/getting-started/talosctl).  On Linux, install a known-good release explicitly:

```bash
TALOS_VERSION=v1.12.5
curl -Lo /usr/local/bin/talosctl \
  "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-$(uname -s | tr '[:upper:]' '[:lower:]')-amd64"
chmod +x /usr/local/bin/talosctl
talosctl version --client --short
```

## Step 1 - Boot the Nodes from a Current Talos Image

```bash
TALOS_VERSION=v1.12.5
curl -LO "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-amd64.iso"
```

You can also build a customized image from the [Talos Image Factory](https://factory.talos.dev/) if you need extra drivers or system extensions.

Boot all four machines from the image. They will start in **maintenance mode**. Nothing is installed to disk until you apply machine configuration.

Once booted, each node will display its IP address on the console. You can also discover them with:

```bash
talosctl get disks --insecure --nodes 192.168.1.51
```

## Step 2 - Generate Machine Configurations

Generate a base control plane config, a worker config, and a `talosconfig` file for your client:

```bash
TALOS_VERSION=v1.12.5
KUBERNETES_VERSION=1.35.2
API_VIP=192.168.1.50
API_ENDPOINT=talos-api.lab.example

talosctl gen config my-cluster https://${API_ENDPOINT}:6443 \
  --talos-version "${TALOS_VERSION}" \
  --kubernetes-version "${KUBERNETES_VERSION}" \
  -o ./clusterconfig
```

Talos will embed that endpoint in the generated kubeconfig, so using the DNS name here keeps your client config readable. The VIP itself still stays numeric in the machine network configuration.

This creates three files:

- `clusterconfig/controlplane.yaml` — base config for all control-plane nodes
- `clusterconfig/worker.yaml` — base config for all worker nodes
- `clusterconfig/talosconfig` — client config for `talosctl`

## Optional - Encrypt Sensitive Files with SOPS and age

Generated Talos files can contain sensitive material (cluster PKI, bootstrap secrets, and client credentials). If you keep these files in Git, encrypt them first.

### 1. Install `sops` and `age`

```bash
# Ubuntu/Debian example
sudo apt-get update
sudo apt-get install -y sops age
```

### 2. Create an age key pair

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Export public recipient for sops rules
AGE_RECIPIENT="$(age-keygen -y ~/.config/sops/age/keys.txt)"
echo "$AGE_RECIPIENT"
```

Keep `~/.config/sops/age/keys.txt` private. Back it up securely: if you lose this key, you lose access to encrypted files.

### 3. Add repository encryption rules

Create `.sops.yaml` at the repository root:

```yaml
creation_rules:
  - path_regex: docs/content/posts/.*/(clusterconfig/.*|kubeconfig|.*secrets.*\.ya?ml)$
    age: age1replace_with_your_public_recipient
```

Replace `age1replace_with_your_public_recipient` with the value printed in step 2.

### 4. Encrypt in place

```bash
sops --encrypt --in-place clusterconfig/controlplane.yaml
sops --encrypt --in-place clusterconfig/worker.yaml
sops --encrypt --in-place clusterconfig/talosconfig
```

If you exported kubeconfig to a file, encrypt that too:

```bash
sops --encrypt --in-place kubeconfig
```

### 5. Work with encrypted files safely

```bash
# Edit decrypted content in a temporary buffer, then re-encrypt on save
sops clusterconfig/talosconfig

# Decrypt for one command without writing plaintext to disk
sops --decrypt clusterconfig/talosconfig | head -n 20
```

### 6. CI/CD decryption pattern

In CI, store the private age key in a secret (for example `SOPS_AGE_KEY`) and restore it at runtime:

```bash
mkdir -p ~/.config/sops/age
printf '%s\n' "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

sops --decrypt clusterconfig/talosconfig > /tmp/talosconfig
```

Only decrypt files in jobs that truly need them, and avoid uploading decrypted artifacts.

## Step 3 - Configure the VIP and Per-Node IPs

Talos supports VIP natively through the interface configuration. In this guide we will use:

- One shared control-plane patch for the VIP
- One patch per node for hostname, static IP, routes, DNS, and install disk

Talos 1.12 introduces newer networking documentation and multiple config sources, but machine config patches like these remain supported and are still the shortest path to a reproducible lab cluster.

If you configure any interface explicitly, Talos stops relying on DHCP for that link. That means you should provide **addresses, routes, and nameservers** in your patch.

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

Replace `eth0` with the actual interface name on your nodes if needed.

How the VIP behaves: one control-plane node advertises it at a time, and Talos will move it automatically when leadership changes. Your DNS record should point at this VIP, not at any single control-plane node.

### Per-node static IP patches

**`patch-cp-01.yaml`**:

```yaml
machine:
  network:
    hostname: cp-01
    nameservers:
      - 1.1.1.1
      - 9.9.9.9
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.51/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
  install:
    disk: /dev/sda
```

**`patch-cp-02.yaml`**:

```yaml
machine:
  network:
    hostname: cp-02
    nameservers:
      - 1.1.1.1
      - 9.9.9.9
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.52/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
  install:
    disk: /dev/sda
```

**`patch-cp-03.yaml`**:

```yaml
machine:
  network:
    hostname: cp-03
    nameservers:
      - 1.1.1.1
      - 9.9.9.9
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.53/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
  install:
    disk: /dev/sda
```

**`patch-worker-01.yaml`**:

```yaml
machine:
  network:
    hostname: worker-01
    nameservers:
      - 1.1.1.1
      - 9.9.9.9
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

Tip: set `install.disk` to the correct block device for your nodes. Use `talosctl get disks --insecure --nodes <ip>` while a node is still in maintenance mode.

## Step 4 - Apply Configuration to Each Node

Apply configuration while the nodes are still in maintenance mode. For control-plane nodes, layer the shared VIP patch together with the per-node patch:

```bash
# Control-plane node 1
talosctl apply-config --insecure \
  --nodes 192.168.1.51 \
  --file clusterconfig/controlplane.yaml \
  --config-patch @patch-cp-vip.yaml \
  --config-patch @patch-cp-01.yaml

# Control-plane node 2
talosctl apply-config --insecure \
  --nodes 192.168.1.52 \
  --file clusterconfig/controlplane.yaml \
  --config-patch @patch-cp-vip.yaml \
  --config-patch @patch-cp-02.yaml

# Control-plane node 3
talosctl apply-config --insecure \
  --nodes 192.168.1.53 \
  --file clusterconfig/controlplane.yaml \
  --config-patch @patch-cp-vip.yaml \
  --config-patch @patch-cp-03.yaml

# Worker node
talosctl apply-config --insecure \
  --nodes 192.168.1.61 \
  --file clusterconfig/worker.yaml \
  --config-patch @patch-worker-01.yaml
```

After receiving the configuration each node will:

1. Write the configuration to disk
2. Install Talos to the target disk
3. Reboot into the installed system

You can watch the installation progress:

```bash
talosctl dmesg --nodes 192.168.1.51 --follow
```

## Step 5 - Configure talosctl for the First Bootstrap

Point `talosctl` at the generated client config and use one real control-plane IP first. That avoids depending on the VIP before the cluster is bootstrapped.

```bash
export TALOSCONFIG="$PWD/clusterconfig/talosconfig"

talosctl config endpoint 192.168.1.51
talosctl config node 192.168.1.51 192.168.1.52 192.168.1.53
```

If you want to inspect the generated client context before proceeding:

```bash
talosctl config info
```

## Step 6 - Bootstrap the Cluster

Once all three control-plane nodes have finished installing and rebooted, bootstrap etcd on **exactly one** control-plane node (run this command only once):

```bash
talosctl bootstrap --nodes 192.168.1.51
```

After a short wait, etcd starts, the Kubernetes API comes online, and the VIP becomes reachable.

Check cluster health:

```bash
talosctl health --nodes 192.168.1.51,192.168.1.52,192.168.1.53,192.168.1.61 \
  --control-plane-nodes 192.168.1.51,192.168.1.52,192.168.1.53 \
  --worker-nodes 192.168.1.61
```

Once the VIP is live, switch the client endpoint to the shared address. I like to keep both the DNS name and the raw VIP configured:

```bash
talosctl config endpoint talos-api.lab.example 192.168.1.50
```


## Step 7 - Retrieve kubeconfig and Verify the Cluster

```bash
talosctl kubeconfig ./kubeconfig --nodes 192.168.1.51 --force --merge=false
export KUBECONFIG=./kubeconfig
```

Verify the cluster is healthy:

```bash
kubectl get nodes -o wide
```

Expected output:

```
NAME        STATUS   ROLES           AGE   VERSION   INTERNAL-IP    OS-IMAGE   KERNEL-VERSION   CONTAINER-RUNTIME
cp-01       Ready    control-plane   5m    v1.35.x   192.168.1.51   Talos      ...              containerd://...
cp-02       Ready    control-plane   5m    v1.35.x   192.168.1.52   Talos      ...              containerd://...
cp-03       Ready    control-plane   5m    v1.35.x   192.168.1.53   Talos      ...              containerd://...
worker-01   Ready    <none>          4m    v1.35.x   192.168.1.61   Talos      ...              containerd://...
```

```bash
kubectl get pods -A
```

At this point the nodes should be registered, but your workload networking is still incomplete until you install a CNI.

## Securely Manage kubeconfig

`kubeconfig` is effectively an access token bundle for your cluster. Treat it like a secret.

### 1. Keep permissions tight

```bash
chmod 600 ./kubeconfig
```

If you merge this cluster into `~/.kube/config`, protect that file too:

```bash
chmod 600 ~/.kube/config
```

### 2. Use dedicated files per environment

Avoid one giant shared kubeconfig for all environments. Keep cluster-specific files and select them explicitly:

```bash
export KUBECONFIG="$PWD/kubeconfig"
kubectl config current-context
```

This reduces accidental commands against the wrong cluster.

### 3. Avoid committing kubeconfig to Git

Add it to `.gitignore` or keep it encrypted with `sops` and `age` if it must live in the repository.

```gitignore
kubeconfig
*.kubeconfig
```

### 4. Do not copy kubeconfig into CI unless needed

Prefer short-lived runtime decryption and ephemeral paths in CI jobs:

```bash
sops --decrypt kubeconfig > /tmp/kubeconfig
export KUBECONFIG=/tmp/kubeconfig
```

Delete it at the end of the job:

```bash
shred -u /tmp/kubeconfig 2>/dev/null || rm -f /tmp/kubeconfig
```

### 5. Rotate credentials when sharing risk exists

If a kubeconfig is exposed (chat paste, screen share, logs, or accidental commit), rotate credentials immediately by regenerating client access with `talosctl kubeconfig` and replacing old copies.

### 6. Share kubeconfig across multiple workstations securely

If you use more than one workstation (for example laptop plus desktop), share only an encrypted kubeconfig, never the plaintext file.

Recommended pattern:

1. Generate one `age` key pair per workstation.
2. Add all workstation public recipients to `.sops.yaml`.
3. Encrypt `kubeconfig` once with `sops`.
4. Sync only encrypted files (Git/private storage).
5. Decrypt locally on each workstation.

Example `.sops.yaml` rule with two workstations:

```yaml
creation_rules:
  - path_regex: kubeconfig
    age: age1workstation1publickey,age1workstation2publickey
```

Encrypt and sync:

```bash
sops --encrypt --in-place kubeconfig
git add kubeconfig .sops.yaml
git commit -m "Store kubeconfig encrypted with sops"
```

On each workstation:

```bash
mkdir -p ~/.kube
sops --decrypt kubeconfig > ~/.kube/lab-config
chmod 600 ~/.kube/lab-config
export KUBECONFIG=~/.kube/lab-config
```

If one workstation is lost or compromised, remove its `age` recipient from `.sops.yaml`, re-encrypt, and regenerate cluster access material.


## Step 8 - Install a CNI Plugin

Talos does not install a general-purpose CNI for you in this flow. Install one before expecting normal pod-to-pod networking. [Cilium](https://cilium.io/) is a strong default for homelab and production clusters alike:

```bash
# Install Cilium CLI
CILIUM_CLI_VERSION=v0.19.2
curl -L --fail \
  "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz" \
  | tar -xz cilium
install -m 0755 cilium /usr/local/bin/cilium
rm -f cilium

# Deploy Cilium
CILIUM_VERSION=1.19.1
cilium install --version "${CILIUM_VERSION}"

# Wait for Cilium to be ready
cilium status --wait
```

Alternatively, install [Flannel](https://github.com/flannel-io/flannel) or [Calico](https://www.tigera.io/project-calico/) — any CNI compatible with Kubernetes works.


## Verifying VIP Failover

Simulate a control-plane failure to verify that the VIP migrates:

```bash
# Gracefully shut down cp-01 (the current VIP holder)
talosctl shutdown --nodes 192.168.1.51

# Immediately poll the API server through the VIP
kubectl --server=https://192.168.1.50:6443 get nodes
```

If you want to prove that DNS works too, run the same check against the hostname:

```bash
kubectl --server=https://talos-api.lab.example:6443 get nodes
```

Within a few seconds, one of the remaining control-plane nodes should take over the VIP and API calls should continue to work.

Bring `cp-01` back through your hypervisor or by powering the machine back on, then confirm the cluster settles:

```bash
talosctl health --nodes 192.168.1.51,192.168.1.52,192.168.1.53,192.168.1.61 \
  --control-plane-nodes 192.168.1.51,192.168.1.52,192.168.1.53 \
  --worker-nodes 192.168.1.61
```

The node should rejoin automatically.


## Useful talosctl Commands

```bash
# List services on a node
talosctl service --nodes 192.168.1.51

# Read node logs
talosctl logs kubelet --nodes 192.168.1.51

# Show disk usage
talosctl usage / --nodes 192.168.1.51

# Get etcd members
talosctl etcd members --nodes 192.168.1.51

# Upgrade Talos on a node (rolling)
talosctl upgrade --nodes 192.168.1.51 \
  --image ghcr.io/siderolabs/installer:v1.12.5

# Upgrade Kubernetes
talosctl upgrade-k8s --to 1.35.2 \
  --nodes 192.168.1.51
```


## Conclusion

You now have a compact Talos cluster with:

- An immutable, API-managed OS
- Three control-plane nodes for quorum and failover
- One stable Kubernetes API endpoint through the VIP
- A simple static-IP layout that works well on Proxmox and similar hypervisors
- Straightforward upgrade paths for both Talos and Kubernetes

This is a solid starting point for a lab, homelab, or small internal platform. It is not a full platform by itself: you still need storage, ingress, observability, backups, and workload policy choices.

### Next Steps

- **GitOps**: manage cluster state with [Flux](https://fluxcd.io/) or [ArgoCD](https://argo-cd.readthedocs.io/)
- **Storage**: add [Longhorn](https://longhorn.io/) or [Rook-Ceph](https://rook.io/) for persistent volumes
- **Ingress**: deploy [Traefik](https://traefik.io/) or [ingress-nginx](https://kubernetes.github.io/ingress-nginx/)
- **Secrets**: integrate [External Secrets Operator](https://external-secrets.io/) with a vault backend
- **Observability**: set up the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) for metrics and alerting

### Additional Resources

- [Talos Linux Documentation](https://docs.siderolabs.com/talos/v1.12/overview/what-is-talos)
- [Talos Getting Started](https://docs.siderolabs.com/talos/v1.12/getting-started/getting-started)
- [Talos Production Notes](https://docs.siderolabs.com/talos/v1.12/getting-started/prodnotes)
- [Talos Image Factory](https://factory.talos.dev/)
- [Sidero Labs GitHub](https://github.com/siderolabs)
- [Talos VIP documentation](https://docs.siderolabs.com/talos/v1.12/networking/vip/)
- [talosctl CLI reference](https://docs.siderolabs.com/talos/v1.12/reference/cli)

Have questions or feedback? Leave a comment or compare notes with other Talos users in the Sidero community channels.
