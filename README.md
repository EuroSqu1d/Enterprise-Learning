# Enterprise Learning

Real-world enterprise IT documentation — built from hands-on experience setting up and troubleshooting production-grade infrastructure in a homelab environment.

## What This Covers

This repo documents the processes, troubleshooting steps, and lessons learned from working with enterprise hardware and software typically found in data centres and corporate environments.

## Structure

| Folder | Contents |
|--------|----------|
| `01 - Server Builds/` | Physical server setup, BIOS config, RAID controllers, BMC/iRMC |
| `02 - Virtualisation/` | Proxmox VE setup, VM/LXC configuration |
| `03 - Networking/` | VLANs, tunnels, firewall rules, DNS |
| `04 - Security/` | Access control, Zero Trust, certificate management |
| `05 - Cloud/` | Hybrid cloud integration, Azure Arc, Cloudflare |
| `06 - Homelab/` | Install scripts and compose stacks for self-hosted services (Docker, Grafana, …) |

## Hardware in Use

Authoritative details in [`01 - Server Builds/Hardware-Inventory.md`](01%20-%20Server%20Builds/Hardware-Inventory.md).

| Device | Role |
|--------|------|
| Fujitsu PRIMERGY RX1330 M3 | Primary hypervisor (`mikoshi`) — 32 GB ECC, ~8.6 TB, iRMC |
| Dell OptiPlex Micro | Secondary Proxmox node — i5, 32 GB, 256 GB SSD |
| UGREEN 2-bay NAS | Shared storage — 8 TB raw / 4 TB usable (RAID 1, WD Red) |
| Protectli Vault (4-port) | Edge firewall / router |
| Cisco Catalyst 1200 (8-port PoE) | Access switch |
| Juniper EX3200-24T | Core / L3 switch — full Junos |
| 12U open-frame rack + PDU | Housing & power (rack arriving — depth TBC) |
