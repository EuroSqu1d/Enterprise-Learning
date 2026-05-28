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

## Command reference

Junos has two distinct contexts. The prompt tells you which:

- `admin@ex3200>` — **operational mode**. Where you investigate. Read-only commands and a few state-touching ones (`clear`, `restart`, `request`).
- `admin@ex3200#` — **configuration mode**. Where you change the device. Nothing you type here affects running state until `commit`.

Everything is grouped below by **read-only** (safe to run on a production switch any time) vs **action** (changes something — counters, processes, state, or config).

---

### Read-only — System health & inventory

| Command | What |
|---------|------|
| `show version` | Junos version, model, serial summary |
| `show version detail` | Per-process versions, useful when troubleshooting after an upgrade |
| `show chassis hardware` | Inventory of installed FPCs, PICs, PSUs, fans |
| `show chassis hardware detail` | Same plus serial numbers + FRU part numbers |
| `show chassis environment` | Temperature / fan / PSU live readings |
| `show chassis routing-engine` | RE CPU, memory, uptime, idle % |
| `show chassis alarms` | Active alarms (red/yellow LEDs on the chassis correspond to these) |
| `show chassis power` | PSU detail — input voltage, draw, capacity headroom |
| `show chassis fpc` | Line-card status (CPU, memory, online/offline) |
| `show chassis fpc pic-status` | Sub-card (PIC) status |
| `show chassis mac-addresses` | MAC pool the chassis owns |
| `show chassis errors` | Hardware-level errors latched since boot |
| `show system uptime` | Uptime, current time, last reboot reason |
| `show system users` | Who's currently logged in |
| `show system processes extensive` | `top`-style live process view |
| `show system memory` | RE memory breakdown |
| `show system storage` | Disk usage per partition |
| `show system core-dumps` | Any saved process crash dumps |
| `show system commit` | Last 5 commit timestamps + author + comment |
| `show system rollback compare 0 1` | Diff between two rollback points (no config change made) |
| `show system services` | Which services are enabled (SSH, NETCONF, web, telnet, etc.) |
| `show system login` | Configured local users (no passwords shown) |
| `show system ntp associations` | NTP peer status — `*` is the syncing peer |
| `show system ntp status` | Stratum + offset + jitter |
| `show system syslog` | Current syslog targets + facilities |
| `show system snmp` | SNMP config + per-OID hit counters |
| `show system license` | Installed feature licences (some EX features are licensed) |

### Read-only — Interfaces

| Command | What |
|---------|------|
| `show interfaces terse` | One-line summary of every interface (up/down, address, link state) |
| `show interfaces terse \| match ge-` | Filter to physical Gigabit Ethernet ports only |
| `show interfaces terse \| match "up    up"` | Only interfaces with both admin + link up |
| `show interfaces brief` | Slightly more detail per interface |
| `show interfaces ge-0/0/0` | Single interface — speed, duplex, MAC, counters |
| `show interfaces ge-0/0/0 extensive` | Full statistics including per-queue, errors, last flap time |
| `show interfaces ge-0/0/0 detail` | Between brief and extensive |
| `show interfaces statistics` | All interfaces with packet/byte/error counters in one view |
| `show interfaces media` | SFP/SFP+ optic info — type, vendor, serial |
| `show interfaces diagnostics optics ge-0/0/0` | DOM (digital optical monitoring) — Tx/Rx power, temp, voltage |
| `show interfaces queue ge-0/0/0` | Per-CoS-queue depth, drops, transmitted bytes |
| `show interfaces descriptions` | Every interface with its configured description (good for cable trace) |
| `show interfaces filters` | Which firewall filters are bound to which interfaces |
| `show interfaces interface-set` | Membership of named interface sets |
| `show interfaces redundancy` | LAG / redundant interface state |
| `show lacp interfaces` | LACP partner info per LAG member |
| `show lacp statistics interfaces` | LACPDU counters |
| `show 802.1x interface ge-0/0/2` | 802.1x port state if dot1x is enabled |

### Read-only — VLANs & switching (L2)

| Command | What |
|---------|------|
| `show vlans` | All VLANs with member ports |
| `show vlans brief` | Summary table |
| `show vlans detail` | Per-VLAN counters and membership |
| `show vlans extensive` | Adds per-MAC learning state and STP info |
| `show vlans servers` | Just the `servers` VLAN's detail |
| `show vlans extensive \| match irb` | Quickly find which VLANs have an L3 (IRB) interface |
| `show ethernet-switching table` | MAC address table |
| `show ethernet-switching table extensive` | Adds aging timer per entry |
| `show ethernet-switching table vlan servers` | MACs in one VLAN |
| `show ethernet-switching table interface ge-0/0/2` | MACs learned on one port |
| `show ethernet-switching mac-learning-log` | Recent MAC moves and learn/age events |
| `show ethernet-switching interfaces` | Per-port VLAN membership + STP state |
| `show ethernet-switching interfaces brief` | Same, summary form |
| `show ethernet-switching statistics` | Per-port L2 packet/byte/error counters |
| `show ethernet-switching mcrb` | Multi-chassis L2 bridge state (for VC) |
| `show virtual-chassis` | VC member status if EX is stacked |

### Read-only — Routing & L3

| Command | What |
|---------|------|
| `show route` | Full routing table |
| `show route brief` | Summarised output |
| `show route summary` | Routes count per protocol |
| `show route 10.0.20.0/24` | Lookup a specific prefix |
| `show route 10.0.20.30` | Lookup which route covers a host IP |
| `show route protocol direct` | Just connected interfaces |
| `show route protocol static` | Static routes |
| `show route protocol ospf` | OSPF-learned routes |
| `show route protocol bgp` | BGP-learned routes |
| `show route receive-protocol bgp 1.2.3.4` | What we received from a BGP peer |
| `show route advertising-protocol bgp 1.2.3.4` | What we're advertising to that peer |
| `show route forwarding-table` | The FIB — what the hardware actually uses to forward |
| `show route resolution` | Recursive next-hop chain |
| `show arp` | ARP table |
| `show arp no-resolve` | Same, skip reverse DNS (faster on big tables) |
| `show ipv6 neighbors` | IPv6 NDP cache |
| `show ospf neighbor` | OSPF adjacency state |
| `show ospf interface` | Per-interface OSPF parameters |
| `show ospf database` | Link-state database |
| `show bgp summary` | BGP peer status one-liner per peer |
| `show bgp neighbor 1.2.3.4` | Detail on one peer |
| `show ip rip neighbor` | RIP peers (you probably won't run RIP) |

### Read-only — Spanning tree

| Command | What |
|---------|------|
| `show spanning-tree bridge` | Per-VLAN root bridge ID + this switch's role |
| `show spanning-tree interface` | Per-port STP state (forwarding / blocking / etc.) |
| `show spanning-tree statistics interface` | Per-port BPDU counters |
| `show spanning-tree mstp configuration` | MSTP config check (region name, revision, instance map) |
| `show vstp bridge` | VSTP per-VLAN STP (Juniper-specific) |
| `show vstp interface` | VSTP per-port state |

### Read-only — PoE

| Command | What |
|---------|------|
| `show poe controller` | Total PoE budget, used, free, faults |
| `show poe interface` | Per-port PoE state, class, power draw |
| `show poe interface ge-0/0/2` | One port |
| `show poe interface detail` | Per-port with negotiation history |

### Read-only — LLDP / neighbour discovery

| Command | What |
|---------|------|
| `show lldp neighbors` | Devices discovered via LLDP, per local port |
| `show lldp neighbors interface ge-0/0/0` | Single port's neighbour detail |
| `show lldp statistics` | LLDPDU send/receive counters |
| `show lldp local-information` | What this switch is advertising about itself |

### Read-only — Logs & live monitoring

| Command | What |
|---------|------|
| `show log` | List available log files |
| `show log messages` | The main system log (cat-style; newest at the bottom) |
| `show log messages \| last 100` | Just the last 100 lines |
| `show log messages \| match error` | Filter to lines containing "error" |
| `show log messages \| except "cron\|sshd"` | Exclude cron + sshd noise |
| `show log messages \| match "$(show system uptime \| match started \| trim)"` | Lines since boot (rough) |
| `show log interactive-commands` | Every command users have typed in the CLI |
| `show log chassisd` | Chassis daemon log |
| `show log dcd` | Device control daemon log |
| `show log mgd` | Management daemon log |
| `monitor start messages` | Live tail of the messages log (Ctrl-C to stop) |
| `monitor stop messages` | Explicitly stop a named monitor |
| `monitor list` | What live tails are currently running in this session |
| `monitor interface ge-0/0/0` | Refresh-the-screen view of counters for one interface |
| `monitor interface traffic` | Same for all interfaces — bandwidth heatmap |
| `monitor traffic interface ge-0/0/0` | `tcpdump`-style packet capture on an interface |
| `monitor traffic interface ge-0/0/0 detail` | Same, with full decoded packet bodies |
| `monitor traffic interface ge-0/0/0 matching "host 1.2.3.4"` | BPF filter |
| `monitor traffic interface ge-0/0/0 size 1500 count 100` | Capture 100 packets up to 1500 bytes |

### Read-only — Diagnostics

| Command | What |
|---------|------|
| `ping 1.1.1.1` | ICMP — Ctrl-C to stop |
| `ping 1.1.1.1 count 5` | Five pings then stop |
| `ping 1.1.1.1 rapid count 100` | 100 pings, one dot per response, fast |
| `ping 1.1.1.1 source 10.0.10.20` | From a specific source IP |
| `ping 1.1.1.1 size 1472 do-not-fragment` | Path-MTU test (1472 + 28 = 1500) |
| `ping 1.1.1.1 routing-instance VR1` | From a VRF if you've made one |
| `traceroute 1.1.1.1` | Hop-by-hop path |
| `traceroute 1.1.1.1 no-resolve` | Skip reverse DNS at each hop |
| `traceroute 1.1.1.1 source 10.0.10.20` | From specific source |
| `traceroute monitor 1.1.1.1` | mtr-style continuous traceroute |
| `telnet 1.2.3.4 port 443` | Cheap TCP-port-reachability check (just connects, doesn't talk telnet) |
| `ssh user@host` | SSH from the switch to somewhere else |
| `show host www.google.com` | DNS lookup using the switch's resolver |

### Read-only — Files & software

| Command | What |
|---------|------|
| `file list` | List files in the current directory (default `/var/home/<user>`) |
| `file list /var/log/` | Specific directory |
| `file list detail /var/log/` | With sizes + timestamps |
| `file show /var/log/messages` | View a file |
| `file compare files A B` | Unified diff between two files |
| `file checksum md5 /path/file` | MD5 hash |
| `file checksum sha-256 /path/file` | SHA-256 hash |
| `show system software` | Installed Junos packages and versions |
| `show system snapshot media internal` | Saved OS snapshots on internal storage |

### Read-only — Authentication & remote services

| Command | What |
|---------|------|
| `show system services netconf` | NETCONF status (machine-friendly API) |
| `show system services ssh` | SSH config + active connections |
| `show system services web-management` | Web UI status |
| `show system connections` | All current TCP/UDP listeners + established connections |
| `show system connections inet` | IPv4 only |

### Read-only — SNMP

| Command | What |
|---------|------|
| `show snmp statistics` | Protocol counters |
| `show snmp v3` | SNMPv3 user / VACM stats |
| `show snmp mib walk system` | Walk a named MIB subtree |
| `show snmp mib walk 1.3.6.1.2.1.2.2.1` | Walk a specific OID (here: interface table) |
| `show snmp mib get sysName.0` | Get one scalar OID |

---

### Action — Clear (reset counters / state, NOT config)

These touch live state but don't change config and don't drop the device.

| Command | What |
|---------|------|
| `clear interfaces statistics all` | Zero all per-interface counters — useful before a test run |
| `clear interfaces statistics ge-0/0/0` | Zero one interface |
| `clear arp` | Flush ARP table; entries re-learn on next traffic |
| `clear arp hostname 10.0.10.20` | Flush one ARP entry |
| `clear ipv6 neighbors` | Same for IPv6 |
| `clear ethernet-switching table` | Flush MAC address table; re-learns immediately |
| `clear ethernet-switching table interface ge-0/0/0` | Flush MACs learned on one port |
| `clear ethernet-switching mac-learning-log` | Reset the MAC-move log |
| `clear ospf neighbor` | Tear down all OSPF adjacencies (they re-form) |
| `clear ospf neighbor 1.2.3.4` | One adjacency |
| `clear bgp neighbor 1.2.3.4` | Hard BGP reset — session drops |
| `clear bgp neighbor 1.2.3.4 soft` | Soft reset — re-send routes without dropping the TCP session |
| `clear bgp neighbor 1.2.3.4 soft-inbound` | Re-evaluate received routes against current inbound policy |
| `clear firewall filter <name>` | Reset firewall counters for a named filter |
| `clear lldp neighbor` | Clear LLDP-learned neighbours |
| `clear log messages` | Rotate the messages log (old becomes `messages.0.gz`) |
| `clear poe interface ge-0/0/2` | Power-cycle PoE on one port (gentle reset for an unresponsive PoE device) |
| `clear system services dhcp client interface ge-0/0/0` | Force a DHCP renew on a client interface |

### Action — Restart (cycle a daemon)

These restart software processes on the switch. Some are gentle (`routing soft`); others briefly affect traffic.

| Command | What | Caution |
|---------|------|---------|
| `restart routing` | Restart the routing protocol daemon (`rpd`) | Adjacencies drop and re-form — traffic continues during the gap |
| `restart routing soft` | Re-read routing policy without dropping protocols | Safe — preferred when changing policy |
| `restart ethernet-switching` | Restart the L2 daemon | MAC table flushes; brief L2 disruption |
| `restart chassisd` | Restart chassis management daemon | Don't do this lightly — touches FPC state |
| `restart class-of-service` | Restart CoS daemon | CoS classifications re-apply |
| `restart dhcp-service` | Restart DHCP relay/server | DHCP clients eventually re-request |
| `restart snmp` | Restart SNMP daemon | Polling gaps until back up |
| `restart syslog` | Restart syslog daemon | Brief gap in log shipping |
| `restart mgd` | Restart the management daemon | **Drops your CLI session** |
| `restart pfem` | Restart packet forwarding engine manager | **Standalone EX: drops all traffic. Don't.** |

### Action — `request` (state changes, reboots, installs)

The `request` family runs operations. Read carefully before running — some are irreversible.

| Command | What |
|---------|------|
| `request system reboot` | Reboot the switch (asks for confirmation) |
| `request system reboot at "10:00"` | Schedule a reboot at a specific time |
| `request system reboot in 5` | Reboot in 5 minutes |
| `request system reboot reason "kernel panic recovery"` | Reboot with a logged reason |
| `request system halt` | Shut down without rebooting — needs physical access to bring back |
| `request system power-off` | Same as halt but signals the PSU to drop power (where supported) |
| `request system snapshot` | Save the running system image to the alternate boot slice — recovery insurance |
| `request system snapshot recovery` | Save to the recovery slice instead |
| `request system software add /var/tmp/jinstall-ex.tgz` | Install a Junos package |
| `request system software add /var/tmp/jinstall-ex.tgz reboot` | Install + reboot in one step |
| `request system software validate /var/tmp/jinstall-ex.tgz` | Check a package signature without installing |
| `request system software rollback` | Revert to the previously installed Junos version |
| `request system software delete jinstall-ex` | Delete a previously-installed package |
| `request system configuration rescue save` | Save current running config as the rescue config |
| `request system configuration rescue delete` | Clear the saved rescue config |
| `request system zeroize` | **Factory reset**. Erases config and SSH keys. The device boots with default Junos and is reachable only via console afterwards. **Run only if you mean it.** |
| `request chassis pic offline fpc-slot 0 pic-slot 0` | Take a PIC offline (links go down) |
| `request chassis pic online fpc-slot 0 pic-slot 0` | Bring it back |
| `request chassis fpc restart slot 0` | Restart a Forwarding Plane Card (=hot-reboot a line card) |
| `request poe interface ge-0/0/2 enable` | Turn PoE on for one port |
| `request poe interface ge-0/0/2 disable` | Turn PoE off — useful to power-cycle attached PoE device |

### Action — File operations (delete / move / copy)

| Command | What |
|---------|------|
| `file copy <src> <dst>` | Copy a file (paths can be local or `user@host:/path`) |
| `file copy /var/log/messages user@10.0.10.20:/tmp/` | SCP a log off the switch |
| `file copy ftp://10.0.10.20/jinstall-ex.tgz /var/tmp/` | Fetch via FTP |
| `file copy scp://user@10.0.10.20//tmp/file /var/tmp/` | Fetch via SCP |
| `file delete /var/tmp/old.tgz` | Delete a file |
| `file delete /var/tmp/*.tgz` | Glob delete (careful) |
| `file rename A B` | Rename / move |
| `file archive source /var/log destination /var/tmp/logs.tgz` | tar+gzip a directory |
| `file compare files A B` | Diff two files (read-only but listed here for completeness) |

---

### Configuration mode — Entering

| Command | What |
|---------|------|
| `configure` | Enter shared candidate config (default) |
| `configure exclusive` | Lock the candidate so no one else can edit while you are |
| `configure private` | Get your own private candidate — multi-admin safe; commit merges your changes |
| `exit` | Leave config mode (only if no uncommitted changes; otherwise prompts) |
| `exit configuration-mode` | Force-leave config mode (loses uncommitted changes — Junos asks "are you sure") |
| `quit` | Same as `exit` |

### Configuration mode — Navigation

| Command | What |
|---------|------|
| `edit interfaces ge-0/0/0` | Move *into* that subhierarchy — all subsequent commands relative to it |
| `edit vlans servers` | Move into the `servers` VLAN definition |
| `up` | Move one level up |
| `up 2` | Move two levels up |
| `top` | Jump to the root of the hierarchy |
| `top edit interfaces ge-0/0/1` | Jump to root, then descend somewhere else |

### Configuration mode — Editing

| Command | What |
|---------|------|
| `set <hierarchy> <value>` | Add / set config (e.g. `set vlans servers vlan-id 20`) |
| `set interfaces ge-0/0/2 unit 0 family ethernet-switching vlan members servers` | Add port to a VLAN |
| `delete <hierarchy>` | Remove config — specify enough to be unambiguous |
| `delete interfaces ge-0/0/2 unit 0 family ethernet-switching vlan members servers` | Remove just that membership |
| `rename interfaces-old to interfaces-new` | Rename a stanza |
| `copy vlans servers to vlans servers-copy` | Duplicate a stanza |
| `replace pattern "old-string" with "new-string"` | sed-like search-and-replace across the candidate |
| `insert ge-0/0/3 before ge-0/0/2` | Reorder ordered config (rare on a switch — common on filters) |
| `activate <hierarchy>` | Re-enable a previously `deactivate`d block |
| `deactivate <hierarchy>` | Mark a block as inactive without deleting it (it's wrapped in `inactive:` markers) |
| `annotate <hierarchy> "reason for this stanza"` | Add an inline comment |
| `load merge terminal` | Paste a block of config to merge into candidate (end with `^D`) |
| `load merge terminal relative` | Paste relative to current edit position |
| `load override terminal` | **Replace** the entire candidate with what you paste (use with care) |
| `load set terminal` | Paste set-style config (the format we export to git) |

### Configuration mode — Viewing your pending changes

| Command | What |
|---------|------|
| `show` | Show candidate config from current hierarchy down |
| `show \| compare` | Diff candidate vs running config — **always run this before commit** |
| `show \| compare rollback 1` | Diff candidate vs one commit ago |
| `show \| display set` | Show as set-style commands (easier to read than the hierarchy form) |
| `show \| display set \| match vlans` | Filter |
| `show \| display inheritance` | Show inherited config from `groups` |
| `show interfaces ge-0/0/0` | Show just one interface's candidate config |

### Configuration mode — Committing

| Command | What |
|---------|------|
| `commit check` | Validate the candidate without applying it — catches syntax / semantic errors |
| `commit` | Apply candidate → running config |
| `commit confirmed` | Apply, with automatic rollback in 10 minutes unless you `commit` again to confirm |
| `commit confirmed 5` | Same, 5-minute auto-rollback window |
| `commit comment "added VLAN 60 for cameras"` | Tag this commit with a message (shows in `show system commit`) |
| `commit at "10:00"` | Schedule a commit at a future time |
| `commit at "10:00" comment "maintenance window apply"` | Scheduled + tagged |
| `commit and-quit` | Commit then immediately exit configuration mode |
| `commit synchronize` | In a routing-engine cluster, sync the commit to the other RE |
| `commit force` | Override soft-warnings (don't override hard errors) |

### Configuration mode — Rolling back

| Command | What |
|---------|------|
| `rollback` | Discard candidate, revert to running config (= `rollback 0`) |
| `rollback 1` | Revert candidate to the running config from one commit ago |
| `rollback 5` | Revert candidate to five commits ago |
| `rollback rescue` | Revert candidate to the saved rescue config |
| `show system rollback 1` | View the config that `rollback 1` would load |
| `show system rollback compare 0 1` | Diff between two rollback points without loading them |
| `show system commit revision detail` | Per-commit user + timestamp + comment |

Junos retains 49 rollbacks (`rollback 0` through `rollback 49`). Rollback files live under `/var/db/config/`.

---

### Pipes, modifiers & CLI tricks

Junos pipes work on almost every command. The most useful ones:

| Suffix | What |
|--------|------|
| `\| no-more` | Disable the screen-pager — useful when piping to file or grep |
| `\| count` | Count lines |
| `\| match <regex>` | Grep-like filter |
| `\| except <regex>` | Inverse grep |
| `\| last <N>` | Last N lines |
| `\| find <regex>` | Skip until match, then print from there |
| `\| display set` | Render hierarchy config as set commands |
| `\| display json` | Render output as JSON (machine-readable) |
| `\| display xml` | XML output (also machine-readable, what NETCONF speaks) |
| `\| display set \| save /var/tmp/snapshot.set` | Pipe to file |
| `\| trim N` | Trim leading whitespace |
| `\| save /var/tmp/output.txt` | Save the output |
| `\| append /var/tmp/output.txt` | Append instead of overwrite |
| `\| compare /var/tmp/baseline.set` | Compare current output with a saved file |

### CLI shortcuts

| Keys | What |
|------|------|
| `Tab` | Autocomplete the current word |
| `Space` | Same in many positions |
| `?` | Show what's valid at the cursor position (try `set ?` at any depth) |
| `Ctrl-A` / `Ctrl-E` | Beginning / end of line (Emacs-style — works through the CLI) |
| `Ctrl-W` | Delete previous word |
| `Ctrl-U` | Delete to start of line |
| `Ctrl-R` | Reverse-i-search through history |
| `Ctrl-L` | Redraw screen |
| `Up` / `Down` | Command history |
| `set cli ?` | Per-session CLI tweaks (screen length, idle timeout) |
| `set cli screen-length 0` | Disable paging for this session |
| `set cli timestamp` | Prefix every command output with a timestamp |

### Worked example — building a tagged VLAN and IRB

The whole point of the above is to enable confident sessions like this. To define VLAN 20 (`servers`), assign it to one access port, and create an L3 interface for it:

```
admin@ex3200> configure
admin@ex3200# set vlans servers vlan-id 20
admin@ex3200# set vlans servers l3-interface irb.20
admin@ex3200# set interfaces irb unit 20 family inet address 10.0.20.1/24
admin@ex3200# set interfaces ge-0/0/3 unit 0 family ethernet-switching port-mode access
admin@ex3200# set interfaces ge-0/0/3 unit 0 family ethernet-switching vlan members servers
admin@ex3200# show | compare
[edit vlans]
+   servers {
+       vlan-id 20;
+       l3-interface irb.20;
+   }
[edit interfaces]
+   irb {
+       unit 20 {
+           family inet {
+               address 10.0.20.1/24;
+           }
+       }
+   }
[edit interfaces ge-0/0/3 unit 0 family ethernet-switching]
+   port-mode access;
+   vlan {
+       members servers;
+   }
admin@ex3200# commit confirmed 5 comment "VLAN 20 + IRB"
commit confirmed will be automatically rolled back in 5 minutes unless confirmed
commit complete
# verify L3 reachability from another box
admin@ex3200# run ping 10.0.20.1 count 3
admin@ex3200# commit comment "VLAN 20 + IRB confirmed"
commit complete
admin@ex3200# exit
admin@ex3200>
```

Note `run` inside configure mode — lets you run operational commands without leaving the candidate config.

---

### Commands you should never run without a console open

Anything in this list can either drop you out of remote access permanently or wipe state. Keep a serial console / iRMC equivalent connected before any of them:

- `request system zeroize` — factory reset
- `restart mgd` — restarts the daemon serving your SSH session
- `restart pfem` — stops forwarding (standalone EX)
- `request system software add … reboot` — reboot during upgrade
- `delete system services ssh` followed by `commit` — disable SSH (use `commit confirmed` so it rolls back)
- `delete interfaces me0` followed by `commit` — kill the dedicated management interface
- `delete system root-authentication` followed by `commit` — remove root password

For all of these, `commit confirmed 5` is your friend: if it locks you out, Junos undoes the change automatically.

## Why Junos is worth learning

Real-world enterprise networking is dominated by Cisco and Juniper. JNCIA-Junos is a credential that comes from this hands-on experience — running this switch in your lab teaches the concepts the cert validates. The free Juniper "Open Learning" courses (`learningportal.juniper.net`) map onto exactly the commands you'll run here.
