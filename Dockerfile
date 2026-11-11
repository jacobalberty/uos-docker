# UniFi OS Server for Docker.
#
# The base image is Ubiquiti's own `uosserver` image, extracted from their installer by
# .github/workflows/uosserver.yml and published as ghcr.io/<owner>/uosserver:<version>.
# This layer only adapts it to run under Docker (systemd as PID 1; see docker-entrypoint.sh).
ARG UOS_VERSION
FROM ghcr.io/jacobalberty/uosserver:${UOS_VERSION}

# Repeat the ARG: build args do not carry across FROM.
ARG UOS_VERSION

ENV container="docker" \
    APP_MODEL="UOSSERVER" \
    PRODUCT_NAME="UniFi OS Server" \
    APP_VERSION="${UOS_VERSION}" \
    CERTDIR="/unifi/cert" \
    CERTNAME="cert.pem" \
    CERT_PRIVATE_NAME="privkey.pem" \
    CERT_IS_CHAIN="false"

# systemd treats SIGRTMIN+3 as "shut down"
STOPSIGNAL SIGRTMIN+3

# There is no console in a container; the getty units only spin.
RUN systemctl mask getty.target getty@.service serial-getty@.service \
        console-getty.service container-getty@.service

COPY systemd/unifi.service.d/ /etc/systemd/system/unifi.service.d/
COPY docker-entrypoint.sh /usr/local/sbin/uos-entrypoint
COPY import-cert.sh /usr/local/sbin/uos-import-cert
RUN chmod 0755 /usr/local/sbin/uos-entrypoint /usr/local/sbin/uos-import-cert

ENTRYPOINT ["/usr/local/sbin/uos-entrypoint"]
