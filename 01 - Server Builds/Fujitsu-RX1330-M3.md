# Fujitsu PRIMERGY RX1330 M3 — Full Setup & Troubleshooting

## Hardware Overview

| Component | Detail |
|-----------|--------|
| Model | Fujitsu PRIMERGY RX1330 M3 |
| CPU | Intel Xeon (socket LGA1151) |
| RAM | 32GB DDR4 ECC |
| Storage Controller | LSI SAS3 MPT (onboard) + SATA AHCI |
| BMC | iRMC (Integrated Remote Management Controller) |
| PSUs | Dual redundant (both required to prevent CSS fault) |
| OS Target | Proxmox VE |
| Hostname | mikoshi.corp |

---

## Initial Issues on Acquisition

On receiving the server, the following faults were present:

- VGA output not working (console redirected to SOL/serial in BIOS)
- CSS (Customer Self Service) indicator light amber
- Red light near ethernet ports
- iRMC web GUI unreachable

**Root cause chain discovered during troubleshooting:**
1. Previous owner had drives in a RAID array
2. `shred` was run to wipe drives, destroying RAID metadata
3. LSI RAID controller raised a CSS fault (can't find valid arrays)
4. iRMC web service crashed due to continuous RAID controller fault assertion
5. Only one PSU installed — Fujitsu requires dual PSUs to suppress the CSS power fault

---

## Troubleshooting Timeline

### Phase 1 — iRMC Access
- Confirmed Proxmox was installed via iRMC before the shred
- After shred: iRMC became unreachable at 10.42.0.17
- Ran `ip neigh` on connected laptop — found server MAC at DELAY state
- Port check with `nc -zv 10.42.0.17 443` returned "no route to host"
- Pressing CSS front panel button caused flash but light returned — confirmed active fault, not historical

### Phase 2 — Hardware Recovery Attempts
- CMOS battery removed for 30 seconds (reset BIOS defaults, accidentally fixed VGA)
- RCVR jumper on motherboard moved briefly (iRMC firmware recovery mode) — not needed
- PWD-CLR jumper identified and left alone (password reset only)
- CSS button held — acknowledged but light persisted (active fault still present)

### Phase 3 — BIOS Configuration
Accessed BIOS via VGA (now working after CMOS reset cleared console redirection):

1. **Advanced → SATA Configuration**: Changed mode from RAID to AHCI
2. **Advanced → LSI SAS3 MPT Controller → Clear Config**: Cleared broken RAID arrays
3. **Advanced → LSI SAS3 MPT Controller → Create Virtual Drive**: Created single-drive RAID-0 to expose drive to UEFI bootloader
4. Confirmed Boot Option Priorities populated with Proxmox EFI entry

### Phase 4 — PSU Discovery
POST screen showed `WARNING - PSU1` — Fujitsu RX1330 M3 requires both PSU bays populated.
Installing second PSU immediately cleared the CSS amber light.

---

## BIOS Settings Reference

| Setting | Location | Value |
|---------|----------|-------|
| SATA Mode | Advanced → SATA Configuration | AHCI |
| Console Redirection | Advanced → Console Redirection | Disabled |
| RAID Config | Advanced → LSI SAS3 MPT Controller | Cleared + JBOD/single VD |
| CSM | Advanced | Leave default (do not change) |

---

## iRMC Notes

- Default factory IP: **192.168.1.1** (after RCVR jumper reset)
- DHCP assigned IP visible in `ip neigh` on connected host
- iRMC port is the **dedicated iRMC ethernet port** (labelled on rear), not standard LAN ports
- iRMC crashes when RAID controller continuously asserts CSS faults
- After clearing RAID config and installing second PSU, iRMC recovers on next boot

---

## Proxmox VE Installation

### Network Configuration
Proxmox installer sets a static IP. Default subnet was 192.168.100.0/24, which conflicted with home LAN (192.168.1.0/24).

Fix:
```bash
nano /etc/network/interfaces
# Change vmbr0 address from 192.168.100.2/24 to 192.168.1.100/24
# Change gateway from 192.168.100.1 to 192.168.1.1
systemctl restart networking
```

Web UI: **https://192.168.1.100:8006**

### Storage Layout
```
sda  1.8T  (Proxmox OS — LSI SAS virtual drive)
  sda1  1007K  (BIOS boot)
  sda2  1G     /boot/efi
  sda3  1.8T   LVM
    pve-swap  968M   [SWAP]
    pve-root  15.9G  /
    pve-data  447G   VM storage

sdb  (empty — additional storage)
sdc  (empty — additional storage)
sdd  (empty — additional storage)
```

---

## Cloudflare Tunnel Setup

To expose Proxmox and services without port forwarding:

1. In Cloudflare Zero Trust → Networks → Tunnels → Create tunnel
2. Name: `mikoshi`
3. Install cloudflared on Proxmox using the provided token command
4. Add public hostname: `proxmox.yourdomain.com` → `https://192.168.1.100:8006`
5. Enable Cloudflare Access policy for additional authentication

---

## Lessons Learned

| Lesson | Detail |
|--------|--------|
| Dual PSU requirement | Fujitsu enterprise servers expect both PSU bays populated. Missing PSU = CSS fault. |
| RAID metadata wipe = controller fault | Running `shred` on RAID drives destroys array metadata. Controller faults until config is cleared. |
| iRMC fault dependency | iRMC web service will not run cleanly while the RAID controller continuously asserts CSS faults |
| CMOS reset clears console redirection | A useful side effect — restored VGA output without needing iRMC |
| UEFI boot entries require virtual drive | LSI SAS controller needs a virtual drive (even single-disk RAID-0) for UEFI to enumerate a bootable device |
| Static IP vs home LAN | Proxmox always sets a static IP at install — verify it matches your target network before assuming inaccessibility is a service fault |

---

## Enterprise Concepts Demonstrated

- BMC/iRMC (Baseboard Management Controller) for out-of-band management
- Hardware RAID controller configuration and fault recovery
- UEFI vs Legacy boot, EFI partitions, BIOS boot entries
- LVM (Logical Volume Manager) storage layout
- Redundant PSU configuration in rack servers
- Network bridge configuration (vmbr0) in Proxmox
- Zero Trust remote access via Cloudflare Tunnel
- Serial-over-LAN (SOL) console redirection
