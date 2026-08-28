# Contributing

Issues and focused pull requests are welcome.

Before submitting a change:

```bash
omarchy plugin validate .
qmllint Panel.qml BarWidget.qml RadialGauge.qml
python -m py_compile bin/disk-health bin/disk-health-collect bin/disk-health-notify
bash -n install.sh
```

Do not commit real collector state, SMART dumps, disk serials, WWNs, hostnames, mount paths, or personal notes. Use `disk-health report --redact` when preparing fixtures or bug reports.

Preserve these interface rules:

- segmented radial gauges represent health only;
- capacity is `used / (used + available)` and uses a horizontal bar;
- removable disks never affect the overall score;
- unknown or stale data never appears healthy;
- derived health values carry `*`;
- pinned mode remains a one-column right rail.
