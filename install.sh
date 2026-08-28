#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install_root="${DISK_STATUS_INSTALL_ROOT:-}"
if [[ -n "${install_root}" && "${DISK_STATUS_TESTING:-}" != "1" ]]; then
  echo "DISK_STATUS_INSTALL_ROOT is reserved for the test suite." >&2
  exit 1
fi
state_parent="${install_root}/var/lib"
local_bin_dir="${install_root}/usr/local/bin"
system_unit_dir="${install_root}/etc/systemd/system"
global_user_unit_dir="${install_root}/etc/systemd/user"
udev_rules_dir="${install_root}/etc/udev/rules.d"
target_user="${SUDO_USER:-${USER}}"
target_group="$(id -gn "${target_user}")"
target_home="${DISK_STATUS_TARGET_HOME:-$(getent passwd "${target_user}" | cut -d: -f6)}"

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this installer as your normal desktop user, without sudo." >&2
  echo "It will request sudo only for system-owned files." >&2
  exit 1
fi

if [[ -z "${target_home}" ]]; then
  echo "Could not determine the home directory for ${target_user}." >&2
  exit 1
fi

for command in python3 smartctl lsblk systemctl udevadm install getent; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Missing required command: ${command}" >&2
    echo "On Omarchy/Arch, install dependencies with: sudo pacman -S smartmontools util-linux" >&2
    exit 1
  fi
done

if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'; then
  echo "Disk Status requires Python 3.11 or newer (found $(python3 --version 2>&1))." >&2
  exit 1
fi

# Stop legacy units before moving their state. Missing units are expected on a
# clean install; these commands intentionally remain best-effort.
sudo systemctl disable --now disk-health-collect.service disk-health-collect.timer disk-health-collect.path 2>/dev/null || true
sudo systemctl --global disable disk-health-notify.path disk-health-notify.timer 2>/dev/null || true
systemctl --user disable --now disk-health-notify.service disk-health-notify.path disk-health-notify.timer 2>/dev/null || true

install -d -m 0755 "${target_home}/.config/omarchy"
if [[ -e "${target_home}/.config/omarchy/disk-health.toml" \
      && ! -e "${target_home}/.config/omarchy/disk-status.toml" ]]; then
  mv "${target_home}/.config/omarchy/disk-health.toml" \
    "${target_home}/.config/omarchy/disk-status.toml"
fi
if [[ -e "${target_home}/.config/omarchy/disk-health.toml" ]]; then
  preview_config="${target_home}/.config/omarchy/disk-status.toml.preview-backup"
  if [[ ! -e "${preview_config}" ]]; then
    mv "${target_home}/.config/omarchy/disk-health.toml" "${preview_config}"
  else
    echo "Legacy config retained at ${target_home}/.config/omarchy/disk-health.toml; preview backup already exists." >&2
  fi
fi
if [[ -e "${target_home}/.config/omarchy/disk-health.toml.bak" \
      && ! -e "${target_home}/.config/omarchy/disk-status.toml.bak" ]]; then
  mv "${target_home}/.config/omarchy/disk-health.toml.bak" \
    "${target_home}/.config/omarchy/disk-status.toml.bak"
fi
if [[ ! -e "${target_home}/.config/omarchy/disk-status.toml" ]]; then
  install -m644 "${repo_dir}/config/disk-status.toml.example" \
    "${target_home}/.config/omarchy/disk-status.toml"
fi

old_seen_dir="${target_home}/.local/state/disk-health"
new_seen_dir="${target_home}/.local/state/disk-status"
if [[ -d "${old_seen_dir}" && ! -e "${new_seen_dir}" ]]; then
  mv "${old_seen_dir}" "${new_seen_dir}"
elif [[ -f "${old_seen_dir}/seen-events" ]]; then
  install -d -m 0755 "${new_seen_dir}"
  if [[ -f "${new_seen_dir}/seen-events" ]]; then
    sort -u "${old_seen_dir}/seen-events" "${new_seen_dir}/seen-events" \
      -o "${new_seen_dir}/seen-events"
  else
    mv "${old_seen_dir}/seen-events" "${new_seen_dir}/seen-events"
  fi
  rm -f "${old_seen_dir}/seen-events"
  rmdir "${old_seen_dir}" 2>/dev/null || true
fi

old_state="${state_parent}/disk-health"
new_state="${state_parent}/disk-status"
if { sudo test -e "${old_state}" || sudo test -L "${old_state}"; } \
   && ! sudo test -e "${new_state}"; then
  sudo mv "${old_state}" "${new_state}"
elif sudo test "${old_state}" -ef "${new_state}"; then
  sudo rm -f "${old_state}"
elif sudo test -e "${old_state}" || sudo test -L "${old_state}"; then
  preview_state="${new_state}/preview-disk-health-state"
  if ! sudo test -e "${preview_state}"; then
    sudo mv "${old_state}" "${preview_state}"
  else
    echo "Legacy state retained at ${old_state}; preview backup already exists." >&2
  fi
fi
sudo install -d -m 0750 -o "${target_user}" -g "${target_group}" "${new_state}"
if sudo test -e "${new_state}/disk-health.json" \
   && ! sudo test -e "${new_state}/disk-status.json"; then
  sudo mv "${new_state}/disk-health.json" "${new_state}/disk-status.json"
fi
if sudo test -e "${new_state}/disk-health.log" \
   && ! sudo test -e "${new_state}/disk-status.log"; then
  sudo mv "${new_state}/disk-health.log" "${new_state}/disk-status.log"
fi

sudo install -Dm755 "${repo_dir}/bin/disk-status" "${local_bin_dir}/disk-status"
sudo install -Dm755 "${repo_dir}/bin/disk-status-collect" "${local_bin_dir}/disk-status-collect"
sudo install -Dm755 "${repo_dir}/bin/disk-status-notify" "${local_bin_dir}/disk-status-notify"

for unit in "${repo_dir}"/systemd/system/*; do
  sudo install -Dm644 "${unit}" "${system_unit_dir}/$(basename "${unit}")"
done
sudo install -Dm644 "${repo_dir}/udev/99-disk-status.rules" "${udev_rules_dir}/99-disk-status.rules"

install -d -m 0755 "${target_home}/.config/systemd/user"
for unit in "${repo_dir}"/systemd/user/*; do
  install -m644 "${unit}" "${target_home}/.config/systemd/user/$(basename "${unit}")"
done

# Remove only the exact legacy artifacts superseded above. State/configuration
# were moved first, so history and user customizations survive the rename.
sudo rm -f "${local_bin_dir}/disk-health" "${local_bin_dir}/disk-health-collect" "${local_bin_dir}/disk-health-notify"
sudo rm -f "${system_unit_dir}/disk-health-collect.service" \
  "${system_unit_dir}/disk-health-collect.timer" \
  "${system_unit_dir}/disk-health-collect.path" \
  "${global_user_unit_dir}/disk-health-notify.service" \
  "${global_user_unit_dir}/disk-health-notify.path" \
  "${global_user_unit_dir}/disk-health-notify.timer" \
  "${udev_rules_dir}/99-disk-health.rules"
rm -f "${target_home}/.config/systemd/user/disk-health-notify.service" \
  "${target_home}/.config/systemd/user/disk-health-notify.path" \
  "${target_home}/.config/systemd/user/disk-health-notify.timer"

sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo systemctl enable --now disk-status-collect.timer disk-status-collect.path
sudo systemctl start disk-status-collect.service

if ! systemctl --user daemon-reload; then
  echo "Could not reach the systemd user session. Run the installer from your logged-in Omarchy desktop session." >&2
  exit 1
fi
systemctl --user enable --now disk-status-notify.path disk-status-notify.timer

echo
echo "Disk Status backend installed."
echo "State:  ${new_state}/disk-status.json"
echo "Config: ${target_home}/.config/omarchy/disk-status.toml"
echo "Check:  disk-status status"
