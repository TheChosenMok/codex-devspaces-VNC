#!/usr/bin/env bash
set -Eeuo pipefail

export HOME="${HOME:-/home/chatgpt}"
export DISPLAY="${DISPLAY:-:1}"
export VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
export VNC_DEPTH="${VNC_DEPTH:-24}"
export VNC_PORT="${VNC_PORT:-5901}"
export NOVNC_PORT="${NOVNC_PORT:-6080}"
export NOVNC_LISTEN_ADDRESS="${NOVNC_LISTEN_ADDRESS:-0.0.0.0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"

mkdir -p \
  "${HOME}" \
  "${XDG_RUNTIME_DIR}" \
  "${XDG_CACHE_HOME}" \
  "${XDG_CONFIG_HOME}" \
  "${XDG_DATA_HOME}" \
  "${HOME}/.vnc"
chmod 0700 "${XDG_RUNTIME_DIR}" "${HOME}/.vnc"

# Rootless Podman/Buildah are available to Codex inside this sidecar. Keep the
# nested image store ephemeral and use fuse-overlayfs, matching the Dev Spaces
# nested-container pattern for OpenShift user namespaces.
if command -v podman >/dev/null 2>&1; then
  containers_config_dir="${XDG_CONFIG_HOME}/containers"
  containers_storage_config="${containers_config_dir}/storage.conf"
  mkdir -p "${containers_config_dir}"
  if [[ ! -e "${containers_storage_config}" ]]; then
    cat >"${containers_storage_config}" <<'EOF'
[storage]
driver = "overlay"
graphroot = "/tmp/graphroot"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF
  fi
fi

# OpenShift assigns an arbitrary UID.  Electron, D-Bus, and desktop utilities
# behave more reliably when getpwuid(3) can resolve it.
if ! getent passwd "$(id -u)" >/dev/null 2>&1; then
  cp /etc/passwd "${XDG_RUNTIME_DIR}/passwd"
  cp /etc/group "${XDG_RUNTIME_DIR}/group"
  printf 'chatgpt:x:%s:%s:ChatGPT Desktop:%s:/bin/bash\n' \
    "$(id -u)" "$(id -g)" "${HOME}" >> "${XDG_RUNTIME_DIR}/passwd"
  export NSS_WRAPPER_PASSWD="${XDG_RUNTIME_DIR}/passwd"
  export NSS_WRAPPER_GROUP="${XDG_RUNTIME_DIR}/group"
  nss_wrapper_lib="$(find /usr/lib64 /usr/lib -name libnss_wrapper.so -print -quit 2>/dev/null)"
  if [[ -z "${nss_wrapper_lib}" ]]; then
    echo "nss_wrapper library was not found" >&2
    exit 1
  fi
  export LD_PRELOAD="${nss_wrapper_lib}${LD_PRELOAD:+:${LD_PRELOAD}}"
fi

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  jobs -pr | xargs -r kill 2>/dev/null || true
  wait 2>/dev/null || true
  exit "${status}"
}
trap cleanup EXIT INT TERM

Xvnc "${DISPLAY}" \
  -geometry "${VNC_GEOMETRY}" \
  -depth "${VNC_DEPTH}" \
  -rfbport "${VNC_PORT}" \
  -SecurityTypes None \
  -localhost yes \
  -AlwaysShared \
  -ac \
  >"${HOME}/.vnc/xvnc.log" 2>&1 &
xvnc_pid=$!

for _ in {1..50}; do
  [[ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]] && break
  kill -0 "${xvnc_pid}" 2>/dev/null || {
    cat "${HOME}/.vnc/xvnc.log" >&2
    exit 1
  }
  sleep 0.2
done

dbus-run-session -- startxfce4 \
  >"${HOME}/.vnc/xfce.log" 2>&1 &
xfce_pid=$!

# Start one instance automatically. If it exits, the desktop remains available
# so the user can relaunch the RPM-provided entry from the XFCE menu.
(
  sleep 2
  /opt/chatgpt-vnc/launch-chatgpt.py \
    >"${HOME}/.vnc/chatgpt.log" 2>&1
) &

# The Dev Spaces service connects to the pod IP, so noVNC must listen on the
# pod interface. The endpoint is marked secure and is protected by the
# workspace JWT proxy. Xvnc itself remains loopback-only.
websockify \
  --web=/usr/share/novnc \
  "${NOVNC_LISTEN_ADDRESS}:${NOVNC_PORT}" \
  "127.0.0.1:${VNC_PORT}" \
  >"${HOME}/.vnc/novnc.log" 2>&1 &
novnc_pid=$!

wait -n "${xvnc_pid}" "${xfce_pid}" "${novnc_pid}"
