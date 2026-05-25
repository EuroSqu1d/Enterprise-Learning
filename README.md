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

## Hardware in Use

| Device | Role |
|--------|------|
| Fujitsu PRIMERGY RX1330 M3 | Primary hypervisor (mikoshi) |
| Dell OptiPlex 3070 | Secondary hypervisor |
