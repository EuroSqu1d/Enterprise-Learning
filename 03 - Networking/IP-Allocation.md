# IP Allocation

Static IP and DHCP scope plan, organised per VLAN. Source-of-truth for "which device is at which address".

## Per-VLAN allocation convention

Within each /24, this template uses:

| Range | Use |
|-------|-----|
| `.1` | Gateway (firewall or L3 switch interface) |
| `.2` – `.9` | Network infrastructure reserved (extra gateways, redundant) |
| `.10` – `.49` | Static IPs (servers, NAS, switches, printers — anything with a permanent identity) |
| `.50` – `.99` | DHCP reservations (always-same-IP but managed by DHCP, useful for end-user devices that need a known IP) |
| `.100` – `.200` | DHCP dynamic pool |
| `.201` – `.254` | Reserved for future use / overflow |

## MGMT — `10.0.10.0/24`

| IP | Hostname | Device | Notes |
|----|----------|--------|-------|
| 10.0.10.1 | gw-mgmt | Protectli IRB | Gateway |
| 10.0.10.10 | mikoshi-irmc | Fujitsu RX1330 M3 iRMC | Out-of-band |
| 10.0.10.11 | mikoshi-pve | Proxmox web UI | https://...:8006 |
| 10.0.10.12 | optiplex-pve | Proxmox web UI | https://...:8006 |
| 10.0.10.20 | sw-juniper | Juniper EX3200 me0 (management) | Junos `me0` is the dedicated mgmt interface |
| 10.0.10.21 | sw-cisco | Cisco Catalyst 1200 management VLAN | |
| 10.0.10.30 | protectli | Protectli admin interface | OPNsense / pfSense UI |

## SERVERS — `10.0.20.0/24`

| IP | Hostname | Device | Notes |
|----|----------|--------|-------|
| 10.0.20.1 | gw-servers | Protectli IRB | Gateway |
| 10.0.20.10 | mikoshi | Proxmox host data NIC | |
| 10.0.20.11 | optiplex | Proxmox host data NIC | |
| 10.0.20.20 | nas | UGREEN NAS data | NFS + SMB targets |
| 10.0.20.30 | docker-mikoshi | Docker host VM on Mikoshi (if you split that out) | |
| 10.0.20.40 | adguard | AdGuard Home VM/container | Once deployed |

Add VMs as you build them: one IP per VM, hostname matches the service.

## CLIENTS — `10.0.30.0/24`

| IP | Hostname | Device |
|----|----------|--------|
| 10.0.30.1 | gw-clients | Protectli IRB |
| 10.0.30.50–.99 | (DHCP reservations) | Phones, laptops you want stable IPs for |
| 10.0.30.100–.200 | (DHCP pool) | Guest-of-the-household devices, anything ephemeral |

## IOT — `10.0.40.0/24`

| IP | Hostname | Device |
|----|----------|--------|
| 10.0.40.1 | gw-iot | Protectli IRB |
| 10.0.40.50–.200 | (DHCP) | Hue bridge, TVs, smart plugs, Sonos, etc. |

## GUEST — `10.0.50.0/24`

DHCP pool only. No statics — guests don't get permanent identities.

## CAMERAS — `10.0.60.0/24`

| IP | Hostname | Device |
|----|----------|--------|
| 10.0.60.1 | gw-cameras | Protectli IRB |
| 10.0.60.10–.49 | (Static or DHCP reservation) | Each camera gets a fixed IP so the NVR knows where to find them |

## TRANSIT — `10.0.99.0/30`

| IP | Device |
|----|--------|
| 10.0.99.1 | Protectli WAN-side of transit |
| 10.0.99.2 | Juniper transit interface |

(Only needed if you put L3 on the Juniper instead of on Protectli — skip if Protectli does all VLAN routing.)

## Cloudflare Tunnel public hostnames

These don't need IPs themselves — they map *to* an internal IP:Port via the tunnel. Documented in `Cloudflare-Tunnel-Mapping.md` for completeness.

## When you add a device

1. Pick a free static IP in the right VLAN (consult this file).
2. Add the row here BEFORE configuring the device — the doc is the plan.
3. Configure the device, verify it reaches its gateway.
4. Add a DNS A record (see `DNS-Plan.md`).
5. Add to AdGuard Home / `dnsmasq` / however you do local DNS.
