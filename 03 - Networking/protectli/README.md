# Protectli Vault — Edge firewall / router

## Pick the OS first

The Protectli Vault is a hardware appliance; the OS is up to you. Decision matrix:

| | OPNsense | pfSense CE | VyOS |
|---|---|---|---|
| UI | Web | Web | CLI-first |
| Plugin ecosystem | Big — Suricata, Zenarmor, HAProxy etc. | Big, older | Smaller |
| Community / docs | Active, modern | Active, more legacy | Smaller |
| Learning value | High — used in many SMBs | High — used in many SMBs | High if you want Junos-style CLI experience |
| Maintenance | Easy | Easy | Steeper |

**Recommended: OPNsense** for this lab. Modern UI, active community, the Suricata + CrowdSec integration plays nicely with the existing security stack, and you'll see it in actual small-business deployments.

## Workflow

Like the Junos folder, this folder is **the record**, not the source. Export configs from OPNsense periodically:

- **OPNsense**: System → Configuration → Backups → Download
- Save as `protectli-<date>.xml` here

The XML is verbose but version-controllable. Commit one after every change.

## What to define

Once OPNsense is installed:

1. **WAN interface** — ISP handoff (DHCP, PPPoE, or static)
2. **LAN interfaces / VLAN parents** — the four GbE ports, marked as VLAN parents
3. **VLAN interfaces** — one per VLAN from `../VLAN-Plan.md`, with IPv4 address = the gateway listed in `../IP-Allocation.md`
4. **DHCP scopes** per VLAN that needs them (CLIENTS, IOT, GUEST, CAMERAS-with-reservations)
5. **DNS resolver** — point at AdGuard Home as the upstream once it's deployed; resolver still runs on Protectli as a fallback
6. **Firewall rules** — implement the inter-VLAN policy from `../VLAN-Plan.md`
7. **NAT** — outbound on WAN (default), plus any port forwards if you need them (probably none — CF Tunnel covers public access)
8. **Suricata** (intrusion detection) — enable on the WAN interface, subscribe to the ET Open ruleset
9. **CrowdSec** plugin — links your edge firewall to the CrowdSec agent in `../../06 - Homelab/crowdsec/`

## Files in this folder

- `protectli-baseline.xml` — initial known-good full config export
- `protectli-<date>.xml` — dated snapshots
- `firewall-rules.md` — human-readable explanation of the rule layout (since XML is hard to read by eye)

## Why this matters for the "Enterprise Learning" theme

OPNsense / pfSense is what a lot of small businesses actually run as their primary firewall. The skills transfer directly:

- Stateful firewalls + rule ordering
- NAT modes (outbound, inbound, port forwarding, 1:1)
- IPSec / OpenVPN / WireGuard site-to-site
- Suricata IPS rule tuning
- HA pairs with CARP (later — needs a second Protectli)
- Captive portal for guest Wi-Fi

Every concept you implement here is one you'll recognise in a real SMB site survey.
