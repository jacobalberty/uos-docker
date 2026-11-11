#!/bin/bash
# Prepare the container for UniFi OS Server, then hand over to systemd.
#
# Runtime inputs:
#   UOS_SYSTEM_IP  hostname or IP that devices use for inform (http://<it>:8080/inform)
#   UOS_UUID       fixed system UUID; generated once and kept in /data/uos_uuid when unset
#   CERTDIR, CERTNAME, CERT_PRIVATE_NAME, CERT_IS_CHAIN   custom TLS certificate (import-cert.sh)
set -eu

# --- stable system UUID, persisted in /data ----------------------------------------------
if [ ! -f /data/uos_uuid ]; then
    if [ -n "${UOS_UUID:-}" ]; then
        echo "$UOS_UUID" > /data/uos_uuid
    else
        # random UUID with the version nibble forced to 5
        sed 's/./5/15' /proc/sys/kernel/random/uuid > /data/uos_uuid
    fi
fi
echo "UOS_UUID=$(cat /data/uos_uuid)"

# --- platform identity files UniFi OS reads ----------------------------------------------
case "$(dpkg --print-architecture)" in
    amd64) platform=linux-x64 ;;
    arm64) platform=arm64 ;;
    *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;;
esac
echo "$platform"       > /usr/lib/platform
echo "$PRODUCT_NAME"   > /usr/lib/product_name
echo "$APP_MODEL"      > /usr/lib/app_model
echo "$APP_MODEL.0000000.$APP_VERSION.0000000.000000.0000" > /usr/lib/version
echo "platform=$platform product=$PRODUCT_NAME model=$APP_MODEL version=$APP_VERSION"

# --- network: UniFi OS expects eth0; on a macvlan/bridge setup it may only see tap0 -------
if [ ! -d /sys/devices/virtual/net/eth0 ] && [ -d /sys/devices/virtual/net/tap0 ]; then
    ip link add name eth0 link tap0 type macvlan
    ip link set eth0 up
fi

# --- directories the services expect on the (bind-mounted) volumes -----------------------
install -d -m 0755 -o nginx    -g nginx    /var/log/nginx
install -d -m 0755 -o mongodb  -g mongodb  /var/log/mongodb
install -d -m 0755 -o rabbitmq -g rabbitmq /var/log/rabbitmq
chown -R mongodb:mongodb /var/lib/mongodb

# Network 10.6.77+ looks for a unit named unifi-mongodb
if [ ! -e /etc/systemd/system/unifi-mongodb.service ]; then
    ln -s /lib/systemd/system/mongodb.service /etc/systemd/system/unifi-mongodb.service
fi

# --- inform address ----------------------------------------------------------------------
if [ -n "${UOS_SYSTEM_IP:-}" ]; then
    props=/var/lib/unifi/system.properties
    echo "UOS_SYSTEM_IP=$UOS_SYSTEM_IP"
    if grep -qs '^system_ip=' "$props"; then
        sed -i "s|^system_ip=.*|system_ip=$UOS_SYSTEM_IP|" "$props"
    else
        echo "system_ip=$UOS_SYSTEM_IP" >> "$props"
    fi
fi

# --- custom TLS certificate (optional; see README) ---------------------------------------
/usr/local/sbin/uos-import-cert

exec /sbin/init
