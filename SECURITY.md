# Security and privacy

## Privilege boundary

Only `disk-health-collect` runs as root because SMART access normally requires it. The QML plugin, CLI, and notifier are unprivileged readers of one state directory. The systemd service uses filesystem, namespace, and kernel hardening directives and can write only to `/var/lib/disk-health`.

## Local data

The state file contains hardware identifiers, drive models, mount points, filesystem usage, and optional user notes. Treat `/var/lib/disk-health` and support bundles as private system information.

Before attaching diagnostics to an issue, generate a redacted bundle:

```bash
disk-health report --bundle disk-status-support.tar.gz --redact
```

Redaction retains drive models and capacity/usage figures for diagnosis. It removes hostnames, serials, WWNs, device and mount paths, notes, and identity-bearing event details.

Never publish `disk-health.json`, `baselines.json`, raw SMART dumps, or an unredacted support bundle.

## Reporting a vulnerability

After public release, use GitHub's **Report a vulnerability** button when it is available. If it is unavailable, contact the maintainer through the GitHub profile without including sensitive details and request a private reporting channel. Do not open a public issue containing an exploit, disk identifiers, mount paths, or raw SMART output.
