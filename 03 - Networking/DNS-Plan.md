# DNS Plan

How internal name resolution works once AdGuard Home is deployed.

## Internal TLD

Use **`.lab`** for internal hostnames. Reasons:

- Short and easy to type — `grafana.lab` beats `grafana.internal.yourdomain.com`.
- Not a real public TLD — won't ever conflict with a real domain you might buy later.
- Avoids `.local` (which mDNS / Bonjour already uses on macOS) and `.home.arpa` (RFC reserved but ugly).
- Some warn against fake TLDs that ICANN might delegate one day — that risk is minimal for `.lab`, but if it bothers you, use a real domain you own with a subdomain like `lab.yourdomain.com`.

## Split-horizon design

Public services (`grafana.yourdomain.com`, `vault.yourdomain.com`) keep their *real* domains — they're reachable via Cloudflare Tunnel from anywhere. Internal-only services use `.lab`.

When you're inside the LAN, `grafana.yourdomain.com` *also* resolves to the internal IP (split-horizon) so traffic doesn't tromboning out to Cloudflare and back. AdGuard Home handles this with a "rewrite" rule.

## Resolver order

```
your device → AdGuard Home (10.0.20.40) → upstream (1.1.1.1 / 9.9.9.9 etc.)
```

AdGuard Home is the only DNS server every VLAN points at. It:

1. Serves internal A records (`grafana.lab → 10.0.20.30`).
2. Serves split-horizon overrides for public hostnames that should resolve internally.
3. Filters ads/trackers from upstream queries.
4. Forwards anything it doesn't know to a real upstream over DoT or DoH.

## Records to create when AdGuard Home is up

Internal `.lab` entries — one per service:

| Hostname | A record | Notes |
|----------|----------|-------|
| `pve.lab` | `10.0.10.11` | Proxmox web UI on Mikoshi |
| `pve2.lab` | `10.0.10.12` | Proxmox web UI on OptiPlex |
| `irmc.lab` | `10.0.10.10` | iRMC |
| `sw-juniper.lab` | `10.0.10.20` | Junos CLI |
| `sw-cisco.lab` | `10.0.10.21` | Cisco web UI |
| `fw.lab` | `10.0.10.30` | Protectli admin |
| `nas.lab` | `10.0.20.20` | UGREEN web UI |
| `grafana.lab` | `10.0.20.30` | Grafana, internal |
| `auth.lab` | `10.0.20.30` | Authentik, internal |
| (etc.) | | Add per service as deployed |

Split-horizon rewrites — public hostname → internal IP when queried from the LAN:

| Public name | Resolves to (internal) |
|-------------|-----------------------|
| `grafana.yourdomain.com` | `10.0.20.30` |
| `vault.yourdomain.com` | `10.0.20.30` |
| `photos.yourdomain.com` | `10.0.20.30` |
| `auth.yourdomain.com` | `10.0.20.30` |
| `jellyfin.yourdomain.com` | `10.0.20.30` |
| `matrix.yourdomain.com` | `10.0.20.30` |
| (etc.) | |

(All to the same IP because they all live on the same Docker host — adjust if you spread services across hosts.)

## Upstream DNS

AdGuard Home → one of:

- **Cloudflare**: `https://1.1.1.1/dns-query` (DoH)
- **Quad9**: `https://9.9.9.9/dns-query` (DoH, slightly more privacy-focused)
- **NextDNS**: a privately-configured profile (more filtering options)

Pick one. DoH or DoT, not plain DNS to a public resolver.

## DHCP option 6 (DNS server)

Set on the Protectli per-VLAN DHCP scope:

- All VLANs: hand out **AdGuard Home's IP** (10.0.20.40 in this plan) as the only DNS server.

This is critical — if devices fall back to public DNS (1.1.1.1 directly), they bypass your filtering. Some IoT devices hardcode DNS to 8.8.8.8 anyway; block UDP/TCP 53 outbound from the IOT VLAN except to AdGuard.

## Resilience

AdGuard Home is now a single point of failure for LAN name resolution. Options:

- **Accept it**, document a procedure for switching the DHCP option to a public resolver if AdGuard dies (you'll lose internal naming but keep working internet).
- **Run a secondary AdGuard** on the OptiPlex Micro, sync config via the official sync feature. Hand out both IPs as DHCP option 6.

Most homelabs go with option 1 until they get burned once.

## When you add a service

1. Pick its internal hostname (`<service>.lab`).
2. Add the A record to AdGuard Home.
3. If it's also publicly exposed via CF Tunnel, add the split-horizon rewrite for the public name too.
4. Update this file.
