# 03 - Networking

Network design, switch configuration, firewall rules, and DNS for the lab. The hardware behind this section is documented in [`../01 - Server Builds/Hardware-Inventory.md`](../01%20-%20Server%20Builds/Hardware-Inventory.md).

## Contents

| File / folder | What's in it |
|---------------|--------------|
| [`VLAN-Plan.md`](VLAN-Plan.md) | VLAN scheme, subnets, purpose, trunk vs access port matrix |
| [`IP-Allocation.md`](IP-Allocation.md) | Static IP / DHCP scope plan per VLAN |
| `junos/` | Juniper EX3200 configuration — committed config snapshots + rationale |
| `protectli/` | Protectli Vault (OPNsense/pfSense) firewall rules + WAN config |
| [`DNS-Plan.md`](DNS-Plan.md) | Internal DNS strategy — `lab` TLD, split horizon vs not, AdGuard Home wiring |
| [`Cloudflare-Tunnel-Mapping.md`](Cloudflare-Tunnel-Mapping.md) | Which public hostnames map to which internal services |

## How the pieces fit together

```
              Internet
                 │
                 │
        ┌────────┴────────┐
        │  Protectli      │   WAN → LAN, NAT, IDS (Suricata)
        │  (OPNsense?)    │
        └────────┬────────┘
                 │ trunk: all VLANs tagged
                 │
        ┌────────┴────────┐
        │ Juniper EX3200  │   L3 core — inter-VLAN routing
        │   (Junos)       │   ──┬───────┐
        └────┬─────────┬──┘     │       │
             │         │        │       │
             │ trunk   │ access │ access│ trunk
             │         │        │       │
     ┌───────┴──┐   ┌──┴────┐  ┌┴────┐ ┌┴────────────────┐
     │  Cisco   │   │ Mikoshi│  │ NAS │ │ OptiPlex Micro  │
     │ Catalyst │   │        │  │     │ │                 │
     │   1200   │   │        │  │     │ │                 │
     └────┬─────┘   └────────┘  └─────┘ └─────────────────┘
          │
       PoE access
       (APs, IP phones, cameras)
```

## What the lab is for (informs design)

Different homelabs need different VLAN designs. Yours is for **enterprise learning** — that means the design should look like a small enterprise's, not a flat home network. That implies:

- Servers separated from end-user devices
- Management interfaces (iRMC, switch CLIs, Proxmox web UI) on their own restricted VLAN
- IoT/guest segregation
- Inter-VLAN routing is *intentional* (every flow is a firewall decision), not implicit

The templates in this folder reflect that posture.

## Order of operations

When the rack arrives and you're building the network:

1. **Rack + cable hardware** — physical install, label every cable
2. **Bring up the Protectli on WAN** — verify internet via NAT to a single LAN port first, no VLANs yet
3. **Configure Junos** — VLAN definitions, trunk to Protectli, access ports for hosts
4. **Cisco trunked off the Juniper** — access ports for PoE devices, trunked uplink
5. **Move hosts to their VLANs one at a time** — verify each before the next
6. **Set up inter-VLAN firewall rules on Protectli** — close the open-by-default flows the Junos provides
7. **Internal DNS / AdGuard** — once VLANs are stable
8. **Cloudflare Tunnel mapping updates** — point at new internal IPs if anything moved

## Source-of-truth convention

This folder is the **plan and the record** — what the network *should* look like, and what's currently committed where:

- **Plans** (VLAN-Plan, IP-Allocation, DNS-Plan) are how you designed it. Update first, then apply.
- **Config snapshots** (under `junos/`, `protectli/`) are what's actually running. Re-export and commit after every change.

A network you can rebuild from this folder alone is a network you actually understand.
