ARG FEDORA_VERSION=43
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The desktop is intentionally small: XFCE, TigerVNC, and noVNC. nss_wrapper
# remains available for clusters that replace the image UID at runtime.
RUN dnf -y upgrade --refresh && \
    dnf -y install \
      bash \
      bubblewrap \
      buildah \
      ca-certificates \
      catatonit \
      curl \
      dbus-daemon \
      dbus-x11 \
      desktop-file-utils \
      firefox \
      findutils \
      git \
      google-noto-sans-fonts \
      gzip \
      hostname \
      iproute \
      libbrotli \
      libcap \
      nodejs \
      npm \
      nss_wrapper \
      xclip \
      novnc \
      openssh-clients \
      openssl \
      podman \
      procps-ng \
      python3 \
      shadow-utils \
      skopeo \
      fuse-overlayfs \
      tar \
      tigervnc-server-minimal \
      unzip \
      util-linux \
      which \
      xdg-utils \
      xfce4-panel \
      xfce4-session \
      xfce4-terminal \
      xfdesktop \
      xfwm4 \
      xorg-x11-xauth \
      xorg-x11-xinit && \
    dnf clean all && \
    rm -rf /var/cache/dnf

ARG CHATGPT_ARCH=x86_64
RUN curl -fLo /tmp/chatgpt.rpm \
      "https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.${CHATGPT_ARCH}.rpm" && \
    dnf -y install /tmp/chatgpt.rpm && \
    rm -f /tmp/chatgpt.rpm && \
    dnf clean all && \
    rm -rf /var/cache/dnf && \
    desktop_file="$(find /usr/share/applications -maxdepth 1 -type f -iname '*chatgpt*.desktop' -print -quit)" && \
    test -n "${desktop_file}" && \
    install -D -m 0644 "${desktop_file}" /opt/chatgpt-vnc/chatgpt.desktop

COPY container/start-desktop.sh container/launch-chatgpt.py /opt/chatgpt-vnc/

# Dev Spaces nested-container SCCs honor the image's non-root UID. A fixed
# 1000:1000 identity also gives rootless Podman stable subuid/subgid mappings.
RUN groupadd --gid 1000 chatgpt && \
    useradd --uid 1000 --gid 1000 --home-dir /home/chatgpt --shell /bin/bash chatgpt && \
    printf 'chatgpt:100000:65536\n' >> /etc/subuid && \
    printf 'chatgpt:100000:65536\n' >> /etc/subgid && \
    setcap cap_setuid+ep /usr/bin/newuidmap && \
    setcap cap_setgid+ep /usr/bin/newgidmap && \
    chmod 0755 /opt/chatgpt-vnc/start-desktop.sh /opt/chatgpt-vnc/launch-chatgpt.py && \
    mkdir -p /home/chatgpt /projects && \
    chown -R 1000:1000 /home/chatgpt /projects && \
    chgrp -R 0 /home/chatgpt /projects /opt/chatgpt-vnc && \
    chmod -R g=u /home/chatgpt /projects /opt/chatgpt-vnc && \
    ln -s /usr/libexec/podman/catatonit /usr/local/bin/container-init

ENV HOME=/home/chatgpt \
    DISPLAY=:1 \
    VNC_GEOMETRY=1920x1080 \
    VNC_DEPTH=24 \
    NOVNC_PORT=6080 \
    NOVNC_LISTEN_ADDRESS=0.0.0.0 \
    VNC_PORT=5901 \
    BUILDAH_ISOLATION=chroot \
    CHATGPT_EXTRA_ARGS="--disable-dev-shm-usage --ozone-platform=x11"

EXPOSE 6080
WORKDIR /projects
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/container-init", "--", "/opt/chatgpt-vnc/start-desktop.sh"]
