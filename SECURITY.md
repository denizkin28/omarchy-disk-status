# Security and privacy

## Privilege boundary

Only `disk-health-collect` runs as root because SMART access normally requires it. The QML plugin, CLI, and notifier are unprivileged readers of one state directory. The systemd service uses filesystem, namespace, and kernel hardening directives and can write only to `/var/lib/disk-health`.

## Local data

The state file contains hardware identifiers, drive models, mount points, filesystem usage, and optional user notes. Treat `/var/lib/disk-health` and support bundles as private system information.

Before attaching diagnostics to an issue, generate a redacted bundle:

```bash
disk-health report --bundle disk-status-support.tar.gz --redact
```

Never publish `disk-health.json`, `baselines.json`, raw SMART dumps, or an unredacted support bundle.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do not open a public issue containing an exploit, disk identifiers, mount paths, or raw SMART output.
