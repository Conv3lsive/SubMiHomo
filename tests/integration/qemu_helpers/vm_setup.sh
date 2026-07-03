#!/bin/sh
# vm_setup.sh — run inside the QEMU OpenWrt VM to install and start SubMiHomo.
# shellcheck shell=sh
set -e

APK_DIR=${APK_DIR:-/apk}

echo '==> Installing SubMiHomo APKs...'
apk add --allow-untrusted "$APK_DIR"/submihomo-*.apk \
    "$APK_DIR"/luci-app-submihomo-*.apk

# Seed a test Mihomo core so lifecycle tests do not depend on external network.
mkdir -p /usr/libexec/submihomo
cat > /usr/libexec/submihomo/mihomo <<'EOF'
#!/bin/sh
case "$1" in
    -t) exit 0 ;;
    -v|--v) printf 'Mihomo v0.0.0-test\n'; exit 0 ;;
    *) sleep 3600 ;;
esac
EOF
chmod 755 /usr/libexec/submihomo/mihomo

# Seed a minimal subscription so the service can start without external network.
mkdir -p /etc/submihomo/subscriptions
chmod 700 /etc/submihomo/subscriptions
cp "$APK_DIR/subscription_minimal.yaml" /etc/submihomo/subscriptions/current.yaml
chmod 600 /etc/submihomo/subscriptions/current.yaml

echo '==> Configuring UCI...'
uci set submihomo.main.enabled='1'
uci set submihomo.main.subscription_url='https://example.com/sub'
uci set submihomo.main.subscription_update_interval='24'
uci set submihomo.main.dns_mode='fake-ip'
uci set submihomo.main.log_level='warning'
uci set submihomo.main.external_controller_port='9090'
uci set submihomo.main.allow_lan_access='0'
uci set submihomo.main.bypass_china='0'
uci commit submihomo

echo '==> Starting SubMiHomo...'
/etc/init.d/submihomo enable
/etc/init.d/submihomo start

echo '==> VM setup complete.'
