#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
stub_dir="${test_root}/stubs"
mkdir -p "${stub_dir}"

for command in systemctl udevadm smartctl lsblk; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"${stub_dir}/${command}"
  chmod +x "${stub_dir}/${command}"
done
printf '#!/usr/bin/env bash\nexec "$@"\n' >"${stub_dir}/sudo"
chmod +x "${stub_dir}/sudo"

run_installer() {
  local root="$1" home="$2"
  PATH="${stub_dir}:${PATH}" \
    DISK_STATUS_TESTING=1 \
    DISK_STATUS_INSTALL_ROOT="${root}" \
    DISK_STATUS_TARGET_HOME="${home}" \
    ./install.sh >/dev/null
}

# Ordinary preview migration plus reinstall idempotency.
ordinary_root="${test_root}/ordinary-root"
ordinary_home="${test_root}/ordinary-home"
mkdir -p "${ordinary_root}/var/lib/disk-health/history" \
  "${ordinary_home}/.config/omarchy" \
  "${ordinary_home}/.local/state/disk-health"
printf 'custom=true\n' >"${ordinary_home}/.config/omarchy/disk-health.toml"
printf 'event-a\n' >"${ordinary_home}/.local/state/disk-health/seen-events"
printf '{"schema":1}\n' >"${ordinary_root}/var/lib/disk-health/disk-health.json"
printf 'history\n' >"${ordinary_root}/var/lib/disk-health/history/drive.csv"
run_installer "${ordinary_root}" "${ordinary_home}"
test ! -e "${ordinary_root}/var/lib/disk-health"
test -f "${ordinary_root}/var/lib/disk-status/disk-status.json"
test -f "${ordinary_root}/var/lib/disk-status/history/drive.csv"
test "$(cat "${ordinary_home}/.config/omarchy/disk-status.toml")" = "custom=true"
test "$(cat "${ordinary_home}/.local/state/disk-status/seen-events")" = "event-a"
before="$(sha256sum "${ordinary_home}/.config/omarchy/disk-status.toml" \
  "${ordinary_root}/var/lib/disk-status/history/drive.csv")"
run_installer "${ordinary_root}" "${ordinary_home}"
after="$(sha256sum "${ordinary_home}/.config/omarchy/disk-status.toml" \
  "${ordinary_root}/var/lib/disk-status/history/drive.csv")"
test "${before}" = "${after}"

# A symlinked preview state must remain a symlink to the same target.
symlink_root="${test_root}/symlink-root"
symlink_home="${test_root}/symlink-home"
symlink_target="${test_root}/external-state"
mkdir -p "${symlink_root}/var/lib" "${symlink_home}" "${symlink_target}/history"
printf '{"schema":1}\n' >"${symlink_target}/disk-health.json"
printf 'history\n' >"${symlink_target}/history/drive.csv"
ln -s "${symlink_target}" "${symlink_root}/var/lib/disk-health"
run_installer "${symlink_root}" "${symlink_home}"
test -L "${symlink_root}/var/lib/disk-status"
test "$(readlink -f "${symlink_root}/var/lib/disk-status")" = "${symlink_target}"
test -f "${symlink_target}/disk-status.json"
test -f "${symlink_target}/history/drive.csv"

# If both state trees exist, preserve the preview tree inside the new state;
# overlapping notifier ids must merge without duplicates.
collision_root="${test_root}/collision-root"
collision_home="${test_root}/collision-home"
mkdir -p "${collision_root}/var/lib/disk-health/history" \
  "${collision_root}/var/lib/disk-status" \
  "${collision_home}/.local/state/disk-health" \
  "${collision_home}/.local/state/disk-status"
printf 'old-history\n' >"${collision_root}/var/lib/disk-health/history/old.csv"
printf '{"new":true}\n' >"${collision_root}/var/lib/disk-status/disk-status.json"
printf 'event-a\nevent-b\n' >"${collision_home}/.local/state/disk-health/seen-events"
printf 'event-b\nevent-c\n' >"${collision_home}/.local/state/disk-status/seen-events"
run_installer "${collision_root}" "${collision_home}"
test ! -e "${collision_root}/var/lib/disk-health"
test -f "${collision_root}/var/lib/disk-status/preview-disk-health-state/history/old.csv"
test "$(cat "${collision_home}/.local/state/disk-status/seen-events")" = $'event-a\nevent-b\nevent-c'
test ! -e "${collision_home}/.local/state/disk-health"

echo "installer migration tests passed"
