#!/bin/bash
# Install a user-provided TLS certificate for the UniFi OS web UI / API (port 443).
#
# Runs from the entrypoint before systemd starts. If ${CERTDIR}/${CERTNAME} is absent this is a
# no-op and UniFi OS keeps its self-signed certificate. Otherwise the certificate (plus chain)
# and private key are written to the paths unifi-core serves:
#   /data/unifi-core/config/unifi-core.crt
#   /data/unifi-core/config/unifi-core.key
#
# Inputs (same names as jacobalberty/unifi-docker):
#   CERTDIR            directory holding the files          (default /unifi/cert)
#   CERTNAME           certificate file                     (default cert.pem)
#   CERT_PRIVATE_NAME  private key file                     (default privkey.pem)
#   CERT_IS_CHAIN      "true" if CERTNAME already contains the full chain
# Optional extra files in CERTDIR: chain.pem (intermediates), ca.pem (root).
set -eu

CERTDIR="${CERTDIR:-/unifi/cert}"
CERTNAME="${CERTNAME:-cert.pem}"
CERT_PRIVATE_NAME="${CERT_PRIVATE_NAME:-privkey.pem}"
CERT_IS_CHAIN="${CERT_IS_CHAIN:-false}"
DEST_DIR="${UOS_CERT_DEST:-/data/unifi-core/config}"

log() { echo "[import-cert] $*"; }

cert="$CERTDIR/$CERTNAME"
key="$CERTDIR/$CERT_PRIVATE_NAME"

[ -f "$cert" ] || exit 0

# A bad mount must not stop the container from booting: warn and keep the current cert.
if [ ! -f "$key" ]; then
    log "WARN: $cert found but private key $key is missing; not importing"
    exit 0
fi
if ! openssl x509 -noout -in "$cert" 2>/dev/null; then
    log "WARN: $cert is not a valid PEM certificate; not importing"
    exit 0
fi

# The key must belong to the (first) certificate. Comparing public keys works for RSA and EC.
cert_pub=$(openssl x509 -noout -pubkey -in "$cert" 2>/dev/null | openssl sha256) || cert_pub=
key_pub=$(openssl pkey -pubout -in "$key" 2>/dev/null | openssl sha256) || key_pub=
if [ -z "$key_pub" ] || [ "$cert_pub" != "$key_pub" ]; then
    log "WARN: private key $key does not match $cert (or is encrypted); not importing"
    exit 0
fi

# Leaf first, then intermediates, then root, as nginx expects.
bundle=$(mktemp)
trap 'rm -f "$bundle"' EXIT
cat "$cert" > "$bundle"
if [ "$CERT_IS_CHAIN" != "true" ]; then
    for extra in chain.pem ca.pem; do
        if [ -f "$CERTDIR/$extra" ]; then
            # make sure the previous file ended with a newline before appending
            tail -c1 "$bundle" | od -An -c | grep -q '\\n' || echo >> "$bundle"
            cat "$CERTDIR/$extra" >> "$bundle"
        fi
    done
fi

if cmp -s "$bundle" "$DEST_DIR/unifi-core.crt" && cmp -s "$key" "$DEST_DIR/unifi-core.key"; then
    log "certificate unchanged"
    exit 0
fi

owner=unifi-core
id "$owner" >/dev/null 2>&1 || owner=root

install -d -m 0755 -o "$owner" -g "$owner" "$DEST_DIR"
install -m 0644 -o "$owner" -g "$owner" "$bundle" "$DEST_DIR/unifi-core.crt"
install -m 0600 -o "$owner" -g "$owner" "$key"    "$DEST_DIR/unifi-core.key"

log "installed $(openssl x509 -noout -subject -enddate -in "$cert" | tr '\n' ' ')"
