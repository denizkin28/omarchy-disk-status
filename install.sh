#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target_user="${SUDO_USER:-${USER}}"
target_group="$(id -gn "${target_user}")"
target_home="$(getent passwd "${target_user}" | cut -d: -f6)"

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
elif [[ -f "${old_seen_dir}/seen-events" && -f "${new_seen_dir}/seen-events" ]]; then
  sort -u "${old_seen_dir}/seen-events" "${new_seen_dir}/seen-events" \
    -o "${new_seen_dir}/seen-events"
  rm -f "${old_seen_dir}/seen-events"
  rmdir "${old_seen_dir}" 2>/dev/null || true
fi

if sudo test -d /var/lib/disk-health && ! sudo test -e /var/lib/disk-status; then
  sudo mv /var/lib/disk-health /var/lib/disk-status
fi
sudo install -d -m 0750 -o "${target_user}" -g "${target_group}" /var/lib/disk-status
if sudo test -e /var/lib/disk-status/disk-health.json \
   && ! sudo test -e /var/lib/disk-status/disk-status.json; then
  sudo mv /var/lib/disk-status/disk-health.json /var/lib/disk-status/disk-status.json
fi
if sudo test -e /var/lib/disk-status/disk-health.log \
   && ! sudo test -e /var/lib/disk-status/disk-status.log; then
  sudo mv /var/lib/disk-status/disk-health.log /var/lib/disk-status/disk-status.log
fi

sudo install -Dm755 "${repo_dir}/bin/disk-status" /usr/local/bin/disk-status
sudo install -Dm755 "${repo_dir}/bin/disk-status-collect" /usr/local/bin/disk-status-collect
sudo install -Dm755 "${repo_dir}/bin/disk-status-notify" /usr/local/bin/disk-status-notify

for unit in "${repo_dir}"/systemd/system/*; do
  sudo install -Dm644 "${unit}" "/etc/systemd/system/$(basename "${unit}")"
done
sudo install -Dm644 "${repo_dir}/udev/99-disk-status.rules" /etc/udev/rules.d/99-disk-status.rules

install -d -m 0755 "${target_home}/.config/systemd/user"
for unit in "${repo_dir}"/systemd/user/*; do
  install -m644 "${unit}" "${target_home}/.config/systemd/user/$(basename "${unit}")"
done

# Remove only the exact legacy artifacts superseded above. State/configuration
# were moved first, so history and user customizations survive the rename.
sudo rm -f /usr/local/bin/disk-health /usr/local/bin/disk-health-collect /usr/local/bin/disk-health-notify
sudo rm -f /etc/systemd/system/disk-health-collect.service \
  /etc/systemd/system/disk-health-collect.timer \
  /etc/systemd/system/disk-health-collect.path \
  /etc/systemd/user/disk-health-notify.service \
  /etc/systemd/user/disk-health-notify.path \
  /etc/systemd/user/disk-health-notify.timer \
  /etc/udev/rules.d/99-disk-health.rules
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
echo "State:  /var/lib/disk-status/disk-status.json"
echo "Config: ${target_home}/.config/omarchy/disk-status.toml"
echo "Check:  disk-status status"
