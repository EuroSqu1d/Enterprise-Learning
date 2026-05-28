# VLAN Plan

Logical network design. Fill in or adjust to match what you actually build — this template reflects a sensible small-enterprise pattern given your hardware.

## VLAN map

| VLAN ID | Name | Subnet (proposed) | Gateway | Purpose | Trust level |
|---------|------|-------------------|---------|---------|-------------|
| 1 | NATIVE / management | (do not use for traffic) | n/a | Default native VLAN — should carry no production traffic; reserve for switch-to-switch control |
| 10 | MGMT | 10.0.10.0/24 | 10.0.10.1 | iRMC, Proxmox web UIs, switch CLIs, Protectli admin, IPMI | Highest |
| 20 | SERVERS | 10.0.20.0/24 | 10.0.20.1 | Proxmox host data NICs, VMs hosting services (Docker stacks), NAS data plane | High |
| 30 | CLIENTS | 10.0.30.0/24 | 10.0.30.1 | Trusted user devices — your laptop, desktop, work-iPad if personal-use | Medium |
| 40 | IOT | 10.0.40.0/24 | 10.0.40.1 | Smart-home gear, anything that "phones home" — TVs, Hue, Sonos, smart plugs | Low |
| 50 | GUEST | 10.0.50.0/24 | 10.0.50.1 | Visitors' Wi-Fi — no access to anything else | None |
| 60 | CAMERAS | 10.0.60.0/24 | 10.0.60.1 | IP cameras + NVR — explicitly NO internet access | None (egress-blocked) |
| 99 | TRANSIT | 10.0.99.0/30 | n/a | Point-to-point between Juniper and Protectli (no hosts) | n/a |

## Inter-VLAN policy

The Juniper EX3200 will route between VLANs by default (it's L3). Restrict that on the Protectli (or on the EX itself with firewall filters) — every cross-VLAN flow is explicit.

| Source → Dest | Policy |
|---------------|--------|
| MGMT → any | Allow (you need to manage everything) |
| any → MGMT | Deny — except specific service ports from CLIENTS (e.g. iRMC HTTPS 443) |
| CLIENTS → SERVERS | Allow specific service ports (3000, 8096, 8200, 2283, etc.) |
| CLIENTS → IOT | Allow (so you can control smart-home stuff from your laptop) |
| IOT → CLIENTS | Deny (no reverse reach — IoT cannot probe your laptop) |
| IOT → Internet | Allow (most IoT needs cloud) |
| IOT → MGMT/SERVERS | Deny — IoT is the most-likely-compromised segment |
| GUEST → anywhere internal | Deny |
| GUEST → Internet | Allow |
| CAMERAS → NVR (one specific IP in SERVERS) | Allow |
| CAMERAS → Internet | **Deny** (cameras leaking footage to the manufacturer's cloud is the threat model) |
| SERVERS → Internet | Allow (Docker pulls, CF Tunnel egress) |

## Port assignment matrix

Fill in actual port numbers when you cable it up.

### Juniper EX3200-24T

| Port | Mode | VLAN(s) | Connected to | Notes |
|------|------|---------|--------------|-------|
| ge-0/0/0 | Trunk | 10, 20, 30, 40, 50, 60 + transit | Protectli LAN | Single uplink, all VLANs tagged |
| ge-0/0/1 | Access | 20 | Mikoshi eth0 (data) | |
| ge-0/0/2 | Access | 10 | Mikoshi iRMC | |
| ge-0/0/3 | Access | 20 | OptiPlex Micro | |
| ge-0/0/4 | Access | 20 | UGREEN NAS | |
| ge-0/0/5 | Trunk | 30, 40, 50 + PoE-only VLANs | Cisco Catalyst uplink | |
| ge-0/0/6 | Access | 30 | Your desktop / patch | |
| ... | | | | Fill in as cabled |

### Cisco Catalyst 1200 (PoE)

| Port | Mode | VLAN(s) | Connected to | PoE | Notes |
|------|------|---------|--------------|-----|-------|
| 1 | Trunk | 30, 40, 50, 60 | Juniper ge-0/0/5 | n/a | Uplink |
| 2 | Access | 30 | Living room AP | Yes | Trusted Wi-Fi SSID |
| 3 | Access | 50 | Guest AP / same AP, different SSID | Yes | |
| 4 | Access | 60 | Front door camera | Yes | |
| ... | | | | | Fill in as cabled |

## Things to decide before applying

- **Subnet scheme** — `10.0.x.0/24` is what's templated. `192.168.x.0/24` works too. Don't use `172.16.x` unless you know your VPN won't overlap.
- **Native VLAN policy** — most enterprises set a non-default native VLAN on every trunk (VLAN 999 unused) so accidental access-mode plugs go nowhere. Worth doing for Junos learning.
- **DHCP location** — Protectli serves DHCP for end-user VLANs (CLIENTS, IOT, GUEST). MGMT and SERVERS use static IPs. CAMERAS can be DHCP with reservations.
- **L3 location** — VLAN gateways live on the Juniper (`irb.X` interfaces) or on the Protectli (one interface per VLAN). Juniper-as-router is faster L3; Protectli-as-router gives you firewall on every flow. Common practice is Protectli-as-router for the security benefit, Juniper purely for L2 + maybe transit VLAN.

## Open questions

- Will you ever need to physically split the cameras onto a different switch for true PoE budget + isolation, or is logical VLAN enough?
- Are any IoT devices (Sonos, Chromecast) going to need mDNS reflection across VLANs? If yes, plan for `avahi-daemon` on the Protectli or a similar reflector.
- Does your ISP hand off via DHCP, PPPoE, or static? Affects Protectli WAN config.
