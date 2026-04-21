---
title: "VLAN-Aware Networking with the TP-Link Omada Ecosystem"
date: 2026-03-17
draft: false
description: "A step-by-step guide to building a properly segmented, VLAN-aware home or small-office network using TP-Link Omada routers, managed switches, and access points"
summary: "Learn how to design and deploy a VLAN-segmented network with TP-Link Omada. This guide walks through the Omada SDN Controller, gateway configuration, managed switch trunk/access ports, SSID-to-VLAN mapping, inter-VLAN routing, and ACL rules — from concept to verified connectivity."
tags: ["homelab", "networking", "vlan", "omada", "tp-link", "infrastructure", "self-hosted"]
---

Network segmentation is one of those fundamentals that is easy to skip when you are setting up a home or small-office network for the first time — and difficult to add cleanly later. A flat network where every device can talk to every other device is fine when you have three laptops and a printer. It becomes a liability once you add IoT devices, a guest Wi-Fi, a homelab, and services you actually care about protecting.

VLANs (Virtual Local Area Networks) solve this cleanly. They let you carve a single physical network into multiple logically isolated broadcast domains. Combined with a firewall, you can precisely control which segments are allowed to communicate with each other.

The [TP-Link Omada](https://www.tp-link.com/en/omada-sdn/) ecosystem is a particularly good choice for this use-case. It combines a software-defined networking (SDN) controller with a range of routers, managed switches, and access points that all share the same management plane. You configure VLANs once in the controller and they propagate automatically across every compatible device in the network.

## What We Are Building

This guide sets up the following network segments:

| VLAN ID | Name        | Subnet            | Purpose                              |
|---------|-------------|-------------------|--------------------------------------|
| 10      | Management  | 192.168.10.0/24   | Network infrastructure (APs, switches, controller) |
| 20      | Trusted     | 192.168.20.0/24   | Personal devices, laptops, phones    |
| 30      | IoT         | 192.168.30.0/24   | Smart home devices, cameras          |
| 40      | Guest       | 192.168.40.0/24   | Guest Wi-Fi, temporary access        |
| 50      | Homelab     | 192.168.50.0/24   | Servers, VMs, self-hosted services   |

The gateway sits between these segments and the internet. Inter-VLAN communication is explicitly allowed or denied via ACL rules.

```
Internet
    │
┌───▼──────────────────────────────┐
│  Gateway / Router (ER605/ER7206) │  ← VLAN-aware, runs DHCP per segment
│  192.168.x.1 per VLAN            │
└───────────────┬──────────────────┘
                │ Tagged trunk (all VLANs)
┌───────────────▼──────────────────┐
│  Core Managed Switch (TL-SG3428) │  ← VLAN trunk uplink + access ports
└──────┬──────────────┬────────────┘
       │ Trunk        │ Trunk
┌──────▼──────┐  ┌────▼────────────┐
│  AP (EAP)   │  │  Edge Switch    │
│  SSID→VLAN  │  │  (access ports) │
└─────────────┘  └─────────────────┘
```

## Prerequisites

**Hardware:**

- TP-Link Omada gateway: ER605 or ER7206 (or similar with VLAN support)
- TP-Link Omada managed switch: TL-SG2008P, TL-SG3428, or similar (must be Omada-managed)
- TP-Link Omada access point: EAP225, EAP245, EAP670, or any current EAP series

**Software:**

- Omada Software Controller (OC) v5.x or later — can run on Docker, a Raspberry Pi, or any Linux host
- Alternatively: Omada Hardware Controller (OC200/OC300), which requires no separate server

**Networking prerequisites:**

- The controller must be reachable from all Omada devices during initial adoption
- A basic untagged management network to bootstrap from (you will convert it to VLAN 10 afterward)

## Setting Up the Omada SDN Controller

The Omada Software Controller manages the entire fleet from a single interface. If you already have it running and your devices are adopted, skip ahead to [Defining VLANs](#defining-vlans-networks).

### Running the Controller with Docker

The easiest way to deploy the controller in a homelab is via the community Docker image:

```yaml
# compose.yml
services:
  omada-controller:
    image: mbentley/omada-controller:latest
    container_name: omada-controller
    network_mode: host
    restart: unless-stopped
    environment:
      - PUID=508
      - PGID=508
      - MANAGE_HTTP_PORT=8088
      - MANAGE_HTTPS_PORT=8043
      - PORTAL_HTTP_PORT=8888
      - PORTAL_HTTPS_PORT=8843
      - SHOW_SERVER_LOGS=true
      - SHOW_MONGODB_LOGS=false
    volumes:
      - omada-data:/opt/tplink/EAPController/data
      - omada-logs:/opt/tplink/EAPController/logs

volumes:
  omada-data:
  omada-logs:
```

```bash
docker compose up -d
```

The controller UI is available at `https://<host-ip>:8043`. Accept the self-signed certificate warning and complete the initial setup wizard.

> **Note:** The controller uses `network_mode: host` because Omada device discovery relies on broadcast UDP packets (port 29810). Bridge networking will prevent automatic device discovery.

### Adopting Devices

Once the controller is running, Omada devices on the same L2 segment will appear in **Devices → Pending** automatically. Click **Adopt** on each one. After adoption, they receive the controller's configuration and can be managed centrally.

If a device does not appear, you can manually point it to the controller:

- For EAPs: use the Omada app or log into the AP's local web UI and enter the controller URL
- For the gateway and switches: navigate to **Settings → Controller** on their local admin pages

## Defining VLANs (Networks)

In Omada, VLANs are defined as **Networks**. Each network has a VLAN ID, a subnet, and a DHCP configuration. The gateway handles DHCP for all VLANs by default.

Navigate to **Settings → Wired Networks → Networks** and click **Create New Network** for each segment:

### Example: IoT Network (VLAN 30)

| Field              | Value                  |
|--------------------|------------------------|
| Name               | IoT                    |
| Purpose            | Corporate (LAN)        |
| VLAN               | 30                     |
| Gateway/Subnet     | 192.168.30.1 / 24      |
| DHCP Server        | Enabled                |
| DHCP Range         | 192.168.30.100 – .200  |
| DNS                | 192.168.30.1 (gateway) |

Repeat this for each VLAN in your plan (Management/10, Trusted/20, IoT/30, Guest/40, Homelab/50).

> **Management VLAN (10):** Make this the native/untagged VLAN on management interfaces. Assign your controller host a static address in this subnet (e.g., `192.168.10.10`) and keep it reachable by all infrastructure devices.

## Configuring the Gateway

The Omada gateway acts as the inter-VLAN router, internet gateway, and DHCP server for all segments. In the controller, navigate to **Devices**, click your gateway, and then open **Config**.

### WAN

Configure your internet-facing interface (WAN1 or WAN2) as usual — DHCP, PPPoE, or static, depending on your ISP.

### LAN / VLAN Interfaces

The gateway's LAN port carries a **tagged trunk** to the core switch. Each VLAN defined in the previous step automatically creates a sub-interface on the gateway. You should see one interface per VLAN listed under **Settings → Wired Networks → Networks** once the gateway is adopted.

The gateway's LAN physical port (or LAG) must be configured to carry all your VLANs tagged. In most Omada deployments this happens automatically when you adopt the gateway and define networks through the controller — the gateway's LAN port becomes a trunk by default.

### DHCP

The DHCP server is configured per-network (as shown above). Verify under **Settings → Wired Networks → Networks** that each network shows **DHCP Server: Enabled** and has a valid IP range.

## Configuring the Managed Switch

The switch connects the gateway to your access points and end devices. It needs:

- A **tagged trunk uplink** to the gateway (carries all VLANs)
- **Tagged trunk downlinks** to access points (carry all VLANs the AP needs to serve)
- **Untagged access ports** for wired devices that belong to a specific VLAN

Navigate to **Devices**, select your switch, open **Config → Port Config**.

### Trunk Port (Uplink to Gateway)

For the port connecting to the gateway:

| Setting        | Value               |
|----------------|---------------------|
| Port Profile   | All (or custom)     |
| Native VLAN    | 10 (Management)     |
| Tagged VLANs   | 10, 20, 30, 40, 50  |

This port carries all VLANs tagged, with VLAN 10 untagged so that the switch's own management traffic is on the correct segment.

### Trunk Port (Downlink to Access Point)

For ports connecting to EAP access points:

| Setting        | Value               |
|----------------|---------------------|
| Port Profile   | All (or custom)     |
| Native VLAN    | 10 (Management)     |
| Tagged VLANs   | 20, 30, 40          |

The AP uses VLAN 10 untagged for its own management communication with the controller. Tagged VLANs match whichever SSIDs you plan to broadcast from that AP.

### Access Port (Wired Device on Trusted VLAN)

For a port where you plug in a trusted device:

| Setting        | Value       |
|----------------|-------------|
| Port Profile   | Trusted     |
| Native VLAN    | 20          |
| Tagged VLANs   | none        |

Traffic enters untagged, the switch adds VLAN 20 tag internally, and frames are forwarded to the gateway on the trunk.

### Using Port Profiles

Rather than configuring each port individually, create **Port Profiles** under **Settings → Profiles → Switch Port Profiles**:

| Profile Name | Native VLAN | Tagged VLANs   |
|--------------|-------------|----------------|
| Trunk-All    | 10          | 10,20,30,40,50 |
| AP-Trunk     | 10          | 20,30,40       |
| VLAN-Trusted | 20          | —              |
| VLAN-IoT     | 30          | —              |
| VLAN-Homelab | 50          | —              |

Apply the appropriate profile to each port. This makes bulk changes significantly easier when you add more switches.

## Configuring Wireless Networks (SSIDs → VLANs)

Each SSID can be bound to a specific VLAN. Devices that connect to that SSID receive DHCP from the corresponding VLAN subnet and are isolated to that segment.

Navigate to **Settings → Wireless Networks** and create or edit an SSID:

### Example: IoT SSID

| Field           | Value              |
|-----------------|--------------------|
| SSID            | Home-IoT           |
| Security        | WPA2-Personal      |
| Password        | (strong passphrase)|
| VLAN            | 30                 |
| Band Steering   | Enabled (if 5GHz supported) |
| Fast Roaming    | Disabled (most IoT devices do not support 802.11r) |

### Recommended SSID Layout

| SSID        | VLAN | Notes                                      |
|-------------|------|--------------------------------------------|
| Home        | 20   | Trusted devices, full internal access      |
| Home-IoT    | 30   | Isolated; internet only, no internal reach |
| Home-Guest  | 40   | Portal or open; internet only              |

You do not need an SSID for the Management or Homelab VLANs — those are wired-only in most setups.

> **Guest Network:** For the Guest SSID, enable **Guest Network** mode under the SSID settings. This activates client isolation and blocks access to the gateway's other interfaces automatically.

## Inter-VLAN Routing and Firewall Rules

By default, the Omada gateway will route traffic between all VLANs because they all share the same routing table. You almost certainly do not want this.

Navigate to **Settings → Network Security → ACL** (Access Control List).

### Design Principles

- **Trusted (VLAN 20)** can reach **Homelab (VLAN 50)** — for managing self-hosted services
- **Homelab (VLAN 50)** can reach **Management (VLAN 10)** — for provisioning and monitoring infrastructure
- **IoT (VLAN 30)** can reach the internet, nothing else internally
- **Guest (VLAN 40)** can reach the internet, nothing else internally
- **Management (VLAN 10)** can reach all VLANs — for controller and infrastructure management

### Example ACL Rules (Gateway ACL)

Create **Gateway ACL** rules under **Settings → Network Security → ACL → Gateway**:

**Rule 1 — Allow Trusted → Homelab:**

| Field       | Value                    |
|-------------|--------------------------|
| Name        | Allow-Trusted-to-Homelab |
| Action      | Permit                   |
| Source      | Network: Trusted (VLAN 20) |
| Destination | Network: Homelab (VLAN 50)|
| Protocol    | All                      |

**Rule 2 — Allow Homelab → Management:**

| Field       | Value                      |
|-------------|----------------------------|
| Name        | Allow-Homelab-to-Mgmt      |
| Action      | Permit                     |
| Source      | Network: Homelab (VLAN 50) |
| Destination | Network: Management (VLAN 10)|
| Protocol    | All                        |

**Rule 3 — Allow Management → All:**

| Field       | Value                        |
|-------------|------------------------------|
| Name        | Allow-Mgmt-to-All            |
| Action      | Permit                       |
| Source      | Network: Management (VLAN 10)|
| Destination | Any                          |
| Protocol    | All                          |

**Rule 4 — Block IoT inter-VLAN:**

| Field       | Value                     |
|-------------|---------------------------|
| Name        | Block-IoT-to-Internal     |
| Action      | Deny                      |
| Source      | Network: IoT (VLAN 30)    |
| Destination | Network Group: All-Private |
| Protocol    | All                       |

**Rule 5 — Block Guest inter-VLAN:**

| Field       | Value                      |
|-------------|----------------------------|
| Name        | Block-Guest-to-Internal    |
| Action      | Deny                       |
| Source      | Network: Guest (VLAN 40)   |
| Destination | Network Group: All-Private |
| Protocol    | All                        |

**Rule 6 — Default Permit WAN (internet access):**

Omada allows internet traffic by default. The Deny rules above apply only to internal routing. Verify that each VLAN can reach the internet after applying your deny rules.

> **Ordering matters.** Omada evaluates ACL rules top-down and stops at the first match. Place Permit rules before Deny rules when needed, and place broad Deny rules at the bottom.

### Network Group for Private Ranges

Create a **Network Group** called `All-Private` under **Settings → Profiles → IP Groups**:

| Entry             |
|-------------------|
| 192.168.10.0/24   |
| 192.168.20.0/24   |
| 192.168.30.0/24   |
| 192.168.40.0/24   |
| 192.168.50.0/24   |
| 10.0.0.0/8        |
| 172.16.0.0/12     |

Reference this group in your Deny rules so you catch all RFC 1918 space, not just the VLANs you have defined today.

## Testing and Verification

After pushing configuration from the controller, validate each segment independently.

### Check DHCP Assignment

Connect a device to each VLAN (via SSID or wired port) and confirm it receives the correct address:

```bash
# Linux / macOS
ip addr show
# or
ipconfig getifaddr en0    # macOS
```

Confirm the assigned address falls within the expected subnet (e.g., `192.168.30.x` for VLAN 30).

### Verify Internet Connectivity

```bash
ping -c 4 1.1.1.1
curl -s https://ifconfig.me
```

Every VLAN should have internet access unless you have explicitly denied it.

### Verify VLAN Isolation

From an IoT or Guest device, attempt to reach an address on the Trusted or Homelab subnet:

```bash
ping -c 3 192.168.20.1    # Should fail from IoT / Guest
ping -c 3 192.168.50.1    # Should fail from IoT / Guest
```

From a Trusted device, confirm you can reach Homelab services:

```bash
ping -c 3 192.168.50.10   # Should succeed from Trusted
```

### Check the Gateway Routing Table

In the Omada controller, navigate to **Devices → Gateway → Details → Routing**. You should see one connected route per VLAN interface.

### Use the Built-In Diagnostic Tools

The Omada controller includes a **Diagnostics** panel under **Settings → Maintenance → Diagnostics**. You can run ping and traceroute directly from the gateway to verify paths without needing physical access to the device.

## Common Issues and Fixes

**Devices on the same SSID can see each other:**
Enable **Client Isolation** on the SSID. This is particularly important for Guest and IoT networks.

**Controller loses connection to APs after VLAN change:**
The controller and APs must share a routable path. Confirm VLAN 10 (Management) is the native VLAN on all trunk ports and that the controller's IP is reachable on that subnet.

**DHCP not assigning addresses:**
Verify the VLAN ID on the SSID or switch port profile matches the VLAN ID of the network definition in the controller. A mismatch means the DHCP request arrives on the wrong VLAN and is silently dropped.

**ACL rules not taking effect:**
After saving ACL changes, force a **provision** of the gateway: select the device in the controller and click **Force Provision**. ACL rules on the ER-series are pushed to the device and applied at that point.

**Tagged frames on an access port:**
If a wired device connected to an access port is not getting an IP from the expected VLAN, check that the Port Profile has the correct Native VLAN set and that no Tagged VLANs are configured for that port. A device sending untagged traffic on an access port should have the switch tag it with the Native VLAN automatically.

## Wrapping Up

A well-segmented network built on the Omada ecosystem gives you:

- **Isolated broadcast domains** — IoT and Guest devices cannot probe your personal or homelab machines
- **Centralized management** — one controller to update SSIDs, ACLs, and port profiles across the entire fleet
- **Scalability** — adding a new VLAN is a matter of creating a Network in the controller and assigning it to the right port profiles and SSIDs

The initial setup takes a few hours, mostly because you need to think carefully about which segments need to talk to each other before you write the ACL rules. Once it is done, the configuration propagates automatically and you rarely need to touch individual devices again.

---

## Resources

- [TP-Link Omada SDN Documentation](https://www.tp-link.com/en/support/download/omada-software-controller/)
- [Omada SDN Controller User Guide](https://static.tp-link.com/upload/software/2023/202307/20230718/1910013430-Omada%20SDN%20Controller%205.12%20User%20Guide.pdf)
- [Community Docker Image for Omada Controller](https://hub.docker.com/r/mbentley/omada-controller)
- [IEEE 802.1Q VLAN Standard](https://en.wikipedia.org/wiki/IEEE_802.1Q)
- [RFC 1918 — Address Allocation for Private Internets](https://datatracker.ietf.org/doc/html/rfc1918)
