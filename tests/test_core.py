import importlib.util
from importlib.machinery import SourceFileLoader
import json
import pathlib
import subprocess
import tarfile
import tempfile
import types
import unittest
from datetime import datetime
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_script(name, relative_path):
    path = ROOT / relative_path
    spec = importlib.util.spec_from_loader(name, SourceFileLoader(name, str(path)))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cli = load_script("disk_status_cli", "bin/disk-status")
collector = load_script("disk_status_collector", "bin/disk-status-collect")
notifier = load_script("disk_status_notifier", "bin/disk-status-notify")


class CoreTests(unittest.TestCase):
    def test_plugin_is_independent_from_the_clock(self):
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertNotIn("clonedFrom", manifest.get("omarchy", {}))

    def test_used_percent_excludes_reserved_space(self):
        stat = types.SimpleNamespace(
            f_blocks=100, f_frsize=1, f_files=10, f_bavail=10, f_bfree=20
        )
        with mock.patch.object(collector.os, "statvfs", return_value=stat):
            usage = collector.filesystem_usage(["/mount"])[0]
        self.assertEqual(usage["used_bytes"], 80)
        self.assertEqual(usage["avail_bytes"], 10)
        self.assertEqual(usage["used_pct"], 88.9)

    def test_worst_fixed_drive_controls_overall_verdict(self):
        drives = [
            {"health": {"verdict": "good", "affects_overall": True}},
            {"health": {"verdict": "bad", "affects_overall": True}},
            {"health": {"verdict": "unknown", "affects_overall": False}},
        ]
        self.assertEqual(collector.overall_verdict(drives), "bad")

    def test_redaction_removes_identity_but_keeps_diagnostics(self):
        state = {
            "host": "private-host",
            "drives": [{
                "serial": "SERIAL-1", "history_id": "SERIAL-1",
                "model": "Example Model", "capacity_bytes": 1000,
                "device": "/dev/sda", "by_id": "/dev/disk/by-id/private",
                "identity_wwn": "WWN-1", "enclosure_serial": "ENC-1",
                "mounts": ["/private"], "note": "private note",
            }],
            "removable": [],
            "events": [{"id": "event-1", "serial": "SERIAL-1",
                        "message": "private message"}],
        }
        safe, _ = cli.redacted_state(state)
        rendered = json.dumps(safe)
        for secret in ("private-host", "SERIAL-1", "/dev/sda", "WWN-1",
                       "ENC-1", "/private", "private note", "private message"):
            self.assertNotIn(secret, rendered)
        self.assertIn("Example Model", rendered)
        self.assertIn("1000", rendered)

    def test_bundle_manifest_lists_actual_members(self):
        serial = "PRIVATE-SERIAL"
        state = {"collected_at": "2026-01-01T00:00:00Z",
                 "drives": [{"serial": serial, "history_id": serial,
                             "model": "Example Model"}],
                 "removable": [], "events": []}
        with tempfile.TemporaryDirectory() as temp_dir:
            history_dir = pathlib.Path(temp_dir) / "history"
            history_dir.mkdir()
            (history_dir / f"{serial}.csv").write_text(
                "ts,temp_c\n2026-01-01T00:00:00Z,40\n", encoding="utf-8"
            )
            old_state_dir = cli.STATE_DIR
            cli.STATE_DIR = temp_dir
            try:
                bundle = pathlib.Path(temp_dir) / "bundle.tar.gz"
                cli.create_support_bundle(bundle, state, redact=True)
            finally:
                cli.STATE_DIR = old_state_dir
            with tarfile.open(bundle) as archive:
                names = set(archive.getnames())
                manifest = json.load(archive.extractfile("manifest.json"))
                history_names = [name for name in names if name.startswith("history/")]
                history_content = archive.extractfile(history_names[0]).read().decode()
        self.assertEqual(set(manifest["contents"]), names - {"manifest.json"})
        self.assertEqual(len(history_names), 1)
        self.assertNotIn(serial, history_names[0])
        self.assertNotIn(serial, history_content)

    def test_notification_body_is_markup_escaped(self):
        result = types.SimpleNamespace(returncode=0)
        with mock.patch.object(notifier.subprocess, "run", return_value=result) as run:
            self.assertTrue(notifier.notify("Disk", "<b>bad & unsafe</b>"))
        argv = run.call_args.args[0]
        self.assertEqual(argv[-1], "&lt;b&gt;bad &amp; unsafe&lt;/b&gt;")

    def test_seen_event_is_not_notified_again_after_migration(self):
        state = {
            "collected_at": datetime.now().astimezone().isoformat(),
            "config": {"thresholds": {"stale_minutes": 45}},
            "events": [{"id": "event-a", "kind": "warning", "to": "caution",
                        "message": "already delivered"}],
            "drives": [],
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            state_file = pathlib.Path(temp_dir) / "disk-status.json"
            seen_file = pathlib.Path(temp_dir) / "seen-events"
            state_file.write_text(json.dumps(state), encoding="utf-8")
            seen_file.write_text("event-a\n", encoding="utf-8")
            with mock.patch.object(notifier, "STATE_FILE", str(state_file)), \
                 mock.patch.object(notifier, "SEEN_FILE", str(seen_file)), \
                 mock.patch.object(notifier, "notify") as notify, \
                 mock.patch.object(notifier.sys, "argv", ["disk-status-notify"]):
                self.assertEqual(notifier.main(), 0)
        notify.assert_not_called()

    def test_segmented_ring_is_full_only_at_true_100_percent(self):
        source = (ROOT / "GaugeMath.js").read_text(encoding="utf-8")
        executable = source.replace(".pragma library", "") + """
console.log(JSON.stringify([
  litSegments(99.9, 42), litSegments(100, 42),
  litSegments(-1, 42), litSegments(101, 42)
]));
"""
        result = subprocess.run(
            ["node", "-e", executable], check=True, text=True,
            capture_output=True,
        )
        self.assertEqual(json.loads(result.stdout), [41, 42, 0, 42])


if __name__ == "__main__":
    unittest.main()
