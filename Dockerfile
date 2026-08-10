FROM ubuntu:26.04

ARG BUILD_CHANNEL=local
ARG COMMIT_SHA=unknown

LABEL org.opencontainers.image.title="Virtual Veeam File Server" \
      org.opencontainers.image.description="Unofficial SSH-managed Linux file server sidecar for Veeam Backup & Replication" \
      org.opencontainers.image.source="https://github.com/Migz93/virtual-veeam-file-server" \
      org.opencontainers.image.licenses="GPL-3.0-only"

ENV DEBIAN_FRONTEND=noninteractive \
    BUILD_CHANNEL="${BUILD_CHANNEL}" \
    COMMIT_SHA="${COMMIT_SHA}" \
    VEEAM_USERNAME="gdveeam" \
    PUID="1000" \
    PGID="1000"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        dbus \
        dmidecode \
        libmagic1 \
        lvm2 \
        openssh-client \
        openssh-server \
        passwd \
        perl \
        systemd \
        systemd-sysv \
        sudo \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /config /usr/local/lib/virtual-veeam-file-server

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY scripts/veeam-state-sync.sh /usr/local/bin/veeam-state-sync.sh
COPY systemd/virtual-veeam-sshd.service /etc/systemd/system/virtual-veeam-sshd.service
COPY systemd/virtual-veeam-state-sync.service /etc/systemd/system/virtual-veeam-state-sync.service
COPY systemd/virtual-veeam-state-sync.timer /etc/systemd/system/virtual-veeam-state-sync.timer

RUN chmod 0755 \
        /usr/local/bin/entrypoint.sh \
        /usr/local/bin/healthcheck.sh \
        /usr/local/bin/veeam-state-sync.sh \
    && systemctl mask \
        getty.target \
        getty@.service \
        ssh.service \
        ssh.socket \
        systemd-logind.service \
        tmp.mount \
    && systemctl enable virtual-veeam-sshd.service virtual-veeam-state-sync.timer

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/sbin/init"]
