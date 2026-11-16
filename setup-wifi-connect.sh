#!/bin/bash

set -e

# ============================================================
# WiFi Connect Setup
# ============================================================

# 1. Update system
sudo apt update
sudo apt upgrade -y

# 2. Install/configure NetworkManager for WiFi Connect
curl -L https://github.com/balena-io/wifi-connect/raw/master/scripts/raspbian-install.sh \
    | sed 's/\*rpi/\*aarch64/' \
    | bash

# 3. Download WiFi Connect 4.11.84
cd /tmp

curl -LO https://github.com/balena-os/wifi-connect/releases/download/v4.11.84/wifi-connect-aarch64-unknown-linux-gnu.tar.gz

# 4. Extract WiFi Connect
tar xzf wifi-connect-aarch64-unknown-linux-gnu.tar.gz

# 5. Install WiFi Connect
sudo cp /tmp/wifi-connect /usr/local/sbin/wifi-connect
sudo chmod +x /usr/local/sbin/wifi-connect

# 6. Verify WiFi Connect version
wifi-connect -V

# 7. Show NetworkManager status
systemctl status NetworkManager --no-pager

# ============================================================
# Create wifi-check.sh
# ============================================================

sudo tee /usr/local/bin/wifi-check.sh > /dev/null <<'EOF'
#!/bin/bash

LOG="/var/log/wifi-check.log"

log() {
    echo "$(date '+%F %T') $*" >> "$LOG"
}

log "=== wifi-check.sh starting ==="

# Don't bail on one bad reading — retry, and try to force the radio on
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

for i in $(seq 1 $TRIES); do

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
EOF

sudo chmod +x /usr/local/bin/wifi-check.sh

# ============================================================
# Create systemd service
# ============================================================

sudo tee /etc/systemd/system/wifi-connect-auto.service > /dev/null <<'EOF'
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
EOF

# ============================================================
# Enable and start service
# ============================================================

sudo systemctl daemon-reload

sudo systemctl enable wifi-connect-auto

sudo systemctl start wifi-connect-auto

# ============================================================
# Show service status
# ============================================================

sudo systemctl status wifi-connect-auto --no-pager
