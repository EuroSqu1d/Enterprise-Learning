# Junos configuration (Juniper EX3200-24T)

## Workflow

Junos config is hierarchical text. Export from the switch periodically and commit the file here — so the repo is the record of what's running.

### Export current config

From a session on the switch:

```
show configuration | display set | no-more
```

Save the output. Or, in a single SSH+pipe from a workstation:

```bash
ssh admin@sw-juniper.lab "show configuration | display set | no-more" \
  > ex3200-$(date +%F).set
```

Commit it here: `junos/ex3200-<date>.set`. Keeping multiple dated versions lets you `diff` between them when troubleshooting "what changed last Tuesday".

### Apply changes

Junos workflow is `configure` → make edits → `commit confirmed 5` → verify → `commit` (or do nothing, and at 5 minutes it auto-rolls-back). Pattern:

```
admin@ex3200> configure
admin@ex3200# set vlans servers vlan-id 20
admin@ex3200# set vlans servers l3-interface irb.20
admin@ex3200# commit confirmed 5
# verify everything still works
admin@ex3200# commit
```

If the change locks you out, the rollback fires automatically. This is *the* killer Junos feature for learning — practice using it on every change.

## Files in this folder

- `ex3200-baseline.set` — initial known-good configuration (create after you finish the initial setup)
- `ex3200-<date>.set` — dated snapshots, one per "interesting" config change
- `snippets/` — reusable config blocks (VLAN + IRB, trunk port, PoE-enabled access port) that you copy-paste into new switches

## What to include in the baseline

A minimal known-good config will define:

1. **System** — hostname, root password (hashed), DNS, NTP, timezone
2. **Users** — yourself with `super-user` class, SSH key
3. **Management** — `me0` interface IP (MGMT VLAN), no inet on data ports until VLANs configured
4. **VLANs** — definitions from `../VLAN-Plan.md`
5. **IRB interfaces** — one per VLAN that the EX routes for (skip if Protectli does all L3)
6. **Routing instances** — usually just `default`; you don't need VRFs here
7. **Firewall filters** — basic rate limiting on management interface, RA guard on access ports
8. **Protocols** — STP/RSTP, LLDP, optionally IGMP snooping if you have multicast (Sonos etc.)
9. **Class-of-service** — usually default unless you have VoIP
10. **SNMP** — read-only community for Prometheus / LibreNMS to scrape

## Useful Junos commands to know

| Command | What |
|---------|------|
| `show configuration` | Active running config (hierarchical) |
| `show configuration \| display set` | Same as set-style (easier to grep / commit) |
| `show interfaces terse` | One-line summary per interface |
| `show vlans` | VLAN membership |
| `show ethernet-switching table` | MAC address table |
| `show route` | Routing table (this switch is L3) |
| `show system commit` | Commit history — see who changed what when |
| `rollback 1` | Restore previous committed config (in configure mode) |
| `request system zeroize` | Factory reset (don't run by accident) |

## Why Junos is worth learning

Real-world enterprise networking is dominated by Cisco and Juniper. JNCIA-Junos is a credential that comes from this hands-on experience — running this switch in your lab teaches the concepts the cert validates. The free Juniper "Open Learning" courses (`learningportal.juniper.net`) map onto exactly the commands you'll run here.
