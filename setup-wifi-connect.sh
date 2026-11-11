#!/usr/bin/env bash
set -Eeuo pipefail

readonly WIFI_CONNECT_VERSION="4.11.84"
readonly WIFI_CONNECT_URL="https://github.com/balena-os/wifi-connect/releases/download/v${WIFI_CONNECT_VERSION}/wifi-connect-aarch64-unknown-linux-gnu.tar.gz"
readonly WIFI_CHECK_SCRIPT="/usr/local/bin/wifi-check.sh"
readonly WIFI_CONNECT_BIN="/usr/local/sbin/wifi-connect"
readonly SYSTEMD_UNIT="/etc/systemd/system/wifi-connect-auto.service"

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
    fail "Run as root, for example: sudo bash $0"
fi

if [[ "$(uname -m)" != "aarch64" ]]; then
    fail "This installer expects a 64-bit ARM system (aarch64); found $(uname -m)."
fi

if ! command -v apt-get >/dev/null 2>&1; then
    fail "apt-get was not found; this installer requires Raspberry Pi OS or another Debian-based OS."
fi

if ! command -v nmcli >/dev/null 2>&1 || ! systemctl is-active --quiet NetworkManager.service; then
    fail "NetworkManager must be installed and active before running this script."
fi

log "Updating package lists and upgrading installed packages."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log "Installing required utilities."
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl iproute2 iputils-ping tar

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log "Downloading WiFi Connect ${WIFI_CONNECT_VERSION} for aarch64."
curl --fail --location --retry 3 --output "$tmp_dir/wifi-connect.tar.gz" "$WIFI_CONNECT_URL"
tar -xzf "$tmp_dir/wifi-connect.tar.gz" -C "$tmp_dir"
[[ -f "$tmp_dir/wifi-connect" ]] || fail "The downloaded archive did not contain the wifi-connect binary."
install -o root -g root -m 0755 "$tmp_dir/wifi-connect" "$WIFI_CONNECT_BIN"
"$WIFI_CONNECT_BIN" -V

log "Installing Wi-Fi connectivity check."
cat > "$WIFI_CHECK_SCRIPT" <<'WIFI_CHECK_EOF'
#!/usr/bin/env bash
LOG="/var/log/wifi-check.log"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

log "=== wifi-check.sh starting ==="

RADIO="disabled"
for i in $(seq 1 10); do
    RADIO=$(nmcli -t -f WIFI g)
    [ "$RADIO" = "enabled" ] && break
    log "WiFi radio not enabled yet (got: '$RADIO'), attempt $i/10"
    nmcli radio wifi on 2>/dev/null
    sleep 3
done

if [ "$RADIO" != "enabled" ]; then
    log "WiFi radio never became enabled after retries, aborting"
    exit 0
fi

sleep 20

TRIES=8
WIFI_OK=0

for i in $(seq 1 "$TRIES"); do
    STATE=$(nmcli -t -f GENERAL.STATE device show wlan0 2>/dev/null | cut -d: -f2 | awk '{print $1}')
    log "check $i/$TRIES: STATE='$STATE'"

    if [ "$STATE" = "100" ]; then
        IP=$(nmcli -t -f IP4.ADDRESS device show wlan0 | cut -d: -f2)
        if [ -n "$IP" ]; then
            GW=$(ip route | awk '/default/ {print $3; exit}')
            if [ -n "$GW" ] && ping -c1 -W1 "$GW" >/dev/null 2>&1; then
                WIFI_OK=1
                break
            fi
        fi
    fi
    sleep 4
done

if [ "$WIFI_OK" -eq 1 ]; then
    log "WiFi OK - no AP needed"
else
    log "WiFi not connected after retries - starting WiFi Connect"
    /usr/local/sbin/wifi-connect >> "$LOG" 2>&1
    log "wifi-connect exited with code $?"
fi
log "=== wifi-check.sh finished ==="
WIFI_CHECK_EOF
chmod 0755 "$WIFI_CHECK_SCRIPT"

log "Installing systemd service."
cat > "$SYSTEMD_UNIT" <<'SYSTEMD_EOF'
[Unit]
Description=Auto-trigger WiFi Connect when WiFi is not connected
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
ExecStartPre=/bin/sleep 30
ExecStart=/usr/local/bin/wifi-check.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

systemctl daemon-reload
systemctl enable wifi-connect-auto.service
systemctl restart wifi-connect-auto.service

if ! systemctl is-active --quiet wifi-connect-auto.service; then
    log "ERROR: wifi-connect-auto.service did not become active."
    systemctl status wifi-connect-auto.service --no-pager --full || true
    journalctl -u wifi-connect-auto.service -b --no-pager -n 50 || true
    exit 1
fi

log "wifi-connect-auto service status:"
systemctl status wifi-connect-auto.service --no-pager --full
log "Recent service journal:"
journalctl -u wifi-connect-auto.service -b --no-pager -n 50
log "Wi-Fi check log:"
if [[ -f /var/log/wifi-check.log ]]; then
    cat /var/log/wifi-check.log
else
    log "The Wi-Fi check has not written a log yet."
fi
log "NetworkManager saved connections:"
nmcli -t -f NAME,TYPE,AUTOCONNECT connection show

log "Setup complete. The service is enabled at boot."
