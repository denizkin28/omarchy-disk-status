# Omarchy Disk Status

A lightweight Omarchy bar plugin for disk health, capacity, temperature, removable-drive state, and live I/O.

## Interface

- Semantic health gauges based on the worst eligible internal drive
- Storage usage calculated as `used / (used + available)`
- Temperature and live I/O per disk
- Expandable SMART diagnostics and copyable reports
- Compact two-column popup for up to six disks
- Persistent one-column right-side status rail
- Automatic Omarchy theme and font integration

## Compatibility note

The user-facing product name is **Disk Status**. The internal plugin identifier remains `denizkin.disk-health` so existing Omarchy bar placement, settings, IPC commands, and upgrades continue to work.

The plugin reads collector output from `/var/lib/disk-health/disk-health.json`; it does not invoke SMART tools or require elevated privileges itself.
