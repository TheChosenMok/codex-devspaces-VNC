# ChatGPT Linux desktop preview in OpenShift Dev Spaces

This project runs the official ChatGPT desktop RPM on Fedora 43 or 44 in an
XFCE sidecar. TigerVNC supplies the X11 desktop, and noVNC exposes it through a
JWT-protected OpenShift Dev Spaces endpoint. A separate Universal Developer
Image (UDI) hosts Che Code, terminals, and the normal development tools. Both
containers see the workspace sources under `/projects`.

## Build and push

1. Build and push the image. The RPM is downloaded automatically during the
   build from the official OpenAI package host:

   ```bash
   # x86_64 (default)
   podman build --build-arg FEDORA_VERSION=43 \
     -t quay.io/rh-ee-malarhab/chatgpt-linux-vnc:fedora43 .

   # aarch64
   podman build --build-arg FEDORA_VERSION=43 --build-arg CHATGPT_ARCH=aarch64 \
     -t quay.io/rh-ee-malarhab/chatgpt-linux-vnc:fedora43 .

   podman push quay.io/rh-ee-malarhab/chatgpt-linux-vnc:fedora43
   ```

   For Fedora 44, use `--build-arg FEDORA_VERSION=44` and a different image tag.

2. Commit the devfile to the repository root and start the repository from the
   Dev Spaces dashboard.
3. Open the `chatgpt-novnc` endpoint. The app should start automatically. Its
   RPM launcher also remains available in the XFCE Applications menu.

The `/home/chatgpt` volume preserves login and application state across
workspace restarts. The workspace uses per-workspace storage, while project
sources are mounted into both containers at `/projects`.

## Dev Spaces and nested-container prerequisites

The layout follows the same sidecar pattern used by the Dev Spaces examples in
`cgruver/devspaces-chrome-sidecar`: a normal development container plus a GUI
browser/desktop container with ports declared as Devfile endpoints.

For Electron and Codex sandboxing, use the nested-container support available
with OpenShift 4.20+ and Dev Spaces 3.25+. The Dev Spaces administrator must
enable both container build and run capabilities in the `CheCluster`:

```yaml
spec:
  devEnvironments:
    disableContainerBuildCapabilities: false
    disableContainerRunCapabilities: false
```

The nested-container SCC should run the image's UID/GID `1000:1000` in a
pod-level user namespace and retain the `SETUID`/`SETGID` capabilities required
for rootless mappings. The image supplies `/etc/subuid` and `/etc/subgid`
entries and capability-enabled `newuidmap`/`newgidmap` helpers for that UID.
Podman, Buildah, Skopeo, and `fuse-overlayfs` are installed in the ChatGPT
sidecar because Codex commands execute there. The nested image graphroot is
ephemeral under `/tmp`; source files and ChatGPT state remain persistent.
These are cluster-level prerequisites; the Devfile cannot grant them by itself.

From the `dev-tools` terminal, these checks should succeed when nested user
namespaces are enabled:

```bash
id
cat /proc/self/uid_map
unshare -Ur true
```

Run the Podman check in the noVNC desktop's XFCE terminal, because that verifies
the ChatGPT/Codex sidecar rather than only the UDI:

```bash
podman info
podman run --rm quay.io/podman/hello
```

The two containers request 3 GiB of memory in total and have a combined 10 GiB
memory limit. Adjust both component limits if the workspace quota is smaller.

## Important constraints

- noVNC listens on the pod interface because the Dev Spaces service must reach
  port 6080. The Devfile endpoint uses `secure: true`, placing the public route
  behind the workspace JWT proxy. TigerVNC stays bound to loopback and has no
  externally declared endpoint.
- The image leaves Electron's sandbox enabled by default. If the cluster's SCC
  still prevents it, add the following environment variable to the
  `chatgpt-desktop` component as a diagnostic fallback:

  ```yaml
  - name: CHATGPT_EXTRA_ARGS
    value: --no-sandbox --disable-dev-shm-usage --disable-gpu --ozone-platform=x11
  ```

  `--no-sandbox` weakens renderer isolation, so fix the nested-user-namespace
  configuration instead of leaving that fallback enabled when possible.
- Codex's command sandbox is separate from Electron's renderer sandbox. The
  image includes `bubblewrap`, but the cluster can still block nested user
  namespaces. If Codex reports `bwrap` or namespace errors, verify the SCC and
  Dev Spaces capability settings above. Do not make the workspace privileged
  just to bypass this.
- VNC does not forward a microphone, camera, or high-quality audio. Chat, Work,
  Codex, files, and browser login are the intended use here; voice features are
  not.
- The RPM cannot update system files as the arbitrary runtime UID. Rebuild the
  container when a new preview RPM is released.

## Troubleshooting

Runtime logs are under `/home/chatgpt/.vnc/`:

- `xvnc.log`
- `xfce.log`
- `novnc.log`
- `chatgpt.log`

If authentication opens a browser, complete it in the Firefox window inside
the same noVNC desktop so custom-protocol or loopback callbacks return to the
containerized app. Firefox is installed only for this OAuth/login fallback; it
is not required for rendering the ChatGPT desktop itself.

If the noVNC endpoint returns 502/503, check that the sidecar is running and
that `novnc.log` reports a listener on `0.0.0.0:6080`. If the desktop opens but
ChatGPT does not, inspect `chatgpt.log` first and temporarily try the sandbox
fallback above.
