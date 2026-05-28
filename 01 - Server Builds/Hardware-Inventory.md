# Hardware Inventory

Authoritative list of physical kit in the homelab. Reconciled from build notes and recent conversations.

> Open items / things to confirm are flagged with **(TBC)** — fill them in once verified.

---

## Compute

### Mikoshi — Fujitsu PRIMERGY RX1330 M3 (Primary hypervisor)

| Attribute | Value |
|-----------|-------|
| Form factor | 1U rack server |
| CPU | Intel Xeon E3-12xx v5 / v6 (LGA1151, Skylake / Kaby Lake) |
| RAM | 32 GB DDR4 ECC |
| Storage | ~8.6 TB total (LSI SAS3 MPT + onboard SATA AHCI) |
| BMC | iRMC (Integrated Remote Management Controller) |
| PSU | Dual redundant — **both bays must be populated** |
| Network | 2× onboard GbE + dedicated iRMC port |
| Chassis depth | ~700 mm — rack accommodation required |
| OS | Proxmox VE |
| Hostname | `mikoshi.corp` |
| Management URL | `https://192.168.1.100:8006` (Proxmox), iRMC on dedicated port |

Build notes: `Fujitsu-RX1330-M3.md` in this folder.

### Secondary — Dell OptiPlex Micro (Always-on second Proxmox node)

| Attribute | Value |
|-----------|-------|
| Form factor | Mini desktop / SFF |
| CPU | Intel Core i5 (generation **TBC**) |
| RAM | 32 GB |
| Storage | 256 GB SSD |
| Network | 1× GbE |
| OS | Proxmox VE |
| Role | Always-on second cluster node — suitable for HA quorum, light VM workloads, services that need to survive Mikoshi reboots |

---

## Storage

### UGREEN 2-bay NAS

| Attribute | Value |
|-----------|-------|
| Drives | 2× WD Red |
| Raw capacity | 8 TB |
| Configuration | RAID 1 (mirror) |
| Usable capacity | 4 TB |
| Role | Shared storage tier; NFS/SMB target for Proxmox; NAS-side rsync destination for Docker volume backups (`06 - Homelab/backups/`) |

---

## Network

### Protectli Vault — Edge firewall / router

| Attribute | Value |
|-----------|-------|
| Ports | 4× GbE |
| OS | **TBC** — OPNsense vs pfSense vs other |
| Role | WAN edge, NAT, VLAN inter-routing, IPS (if Suricata enabled) |

### Cisco Catalyst 1200 (8-port PoE) — Access switch

| Attribute | Value |
|-----------|-------|
| Ports | 8× GbE, all PoE |
| Management | Web UI + CLI (smart-managed, not full IOS) |
| Role | End-device access ports (APs, IP phones, PoE cameras, workstations) |

### Juniper EX3200-24T — Core / L3 switch

| Attribute | Value |
|-----------|-------|
| Ports | 24× GbE, 8 with PoE |
| Software | Full Junos (industry-standard CLI; commit-confirm, hierarchical config) |
| Role | L3 backbone — inter-VLAN routing, trunking to Protectli + Cisco, learning platform for Junos |

The Cisco/Juniper combination is the standout piece of this lab for network-engineering learning — two different vendor CLIs, real configuration drift to manage between them.

---

## Power & housing

### PDU

| Attribute | Value |
|-----------|-------|
| Model | **TBC** — manufacturer / rack-mount form / outlet count / monitored vs basic |
| Role | Rack power distribution |

### 12U open-frame rack

| Attribute | Value |
|-----------|-------|
| Status | Arriving in a few days |
| Internal depth | **TBC — must be ≥ 800 mm or Mikoshi overhangs** |
| Form | Open-frame (no doors / panels) |

> ⚠️ **Rack depth check before mounting Mikoshi.** Fujitsu RX1330 M3 chassis is ~700 mm deep. Common open-frame rack depths are 450 mm (short — won't fit), 600 mm (still short), and 800 mm+ (fine). Confirm the rack spec before arrival; if it's short-depth, options are rear support rails, a shelf for the RX1330, or a deeper rack.

---

## Topology (current intent)

```
        Internet
            │
   ┌────────┴────────┐
   │ Protectli Vault │  edge firewall / router
   └────────┬────────┘
            │ trunk
   ┌────────┴────────┐
   │ Juniper EX3200  │  L3 core, inter-VLAN routing
   └─┬─────────────┬─┘
     │             │
     │ trunk       │ access ports
     │             │
┌────┴─────┐  ┌────┴──────────────────┐
│  Cisco   │  │  Mikoshi (RX1330 M3)  │
│ Catalyst │  │  OptiPlex Micro       │
│   1200   │  │  UGREEN NAS           │
└──────────┘  └───────────────────────┘
PoE APs/cams         Compute + storage tier
```

VLAN plan, IP allocation, and Junos/Protectli config live (or will live) in `03 - Networking/` once that folder is built out.

---

## What this hardware unlocks

A summary of capability you can build *on* this kit — for cross-reference when picking what to deploy.

| Capability | Hardware that enables it |
|------------|--------------------------|
| ECC-safe Postgres / ZFS workloads | 32 GB ECC on Mikoshi |
| Hardware video transcoding (Jellyfin, Immich) | Xeon iGPU via `/dev/dri` |
| Out-of-band remote management | iRMC on Mikoshi |
| 3-node Proxmox cluster | Mikoshi + OptiPlex Micro + (third node TBD) |
| HA / live migration of VMs | Cluster + shared storage on UGREEN NAS |
| ZFS on bare metal | RX1330 has 3 empty bays + ECC RAM |
| Real VLAN segmentation | Junos L3 core + Protectli firewall |
| PoE for cameras / APs | Cisco Catalyst + Juniper 8 PoE ports |
| SNMP monitoring into Prometheus | Both switches expose SNMP |
| Junos learning (commit-confirm, CLI hierarchy) | EX3200 |
| Cisco IOS-light learning | Catalyst 1200 web UI + CLI |
| Production-style power resilience | Dual PSU on Mikoshi |

---

## Open items to settle

| Item | What's needed |
|------|---------------|
| Mikoshi storage layout | Current drive map — `lsblk` output. Build doc says `sda` 1.8 TB + 3 empty bays; current total is now ~8.6 TB. Was the layout changed? |
| OptiPlex Micro CPU generation | `cat /proc/cpuinfo` on the OptiPlex |
| Protectli Vault OS | OPNsense / pfSense / other |
| PDU model | Manufacturer, outlet count, monitored or not |
| Rack depth | Internal depth of the 12U open frame |
| Third Proxmox node | The "HP Proxmox" mentioned earlier — is that retired now or a third box? Hostname / specs if active. |
