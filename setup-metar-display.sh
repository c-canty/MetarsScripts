#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_DIR="/home/pi"
readonly CRON_MARKER="# BEGIN metar-display setup"
readonly CRON_END_MARKER="# END metar-display setup"

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
    fail "Run as root, for example: sudo bash $0 [path-or-URL-to-metar.py]"
fi

if ! command -v apt-get >/dev/null 2>&1; then
    fail "apt-get was not found; this installer requires Raspberry Pi OS or another Debian-based OS."
fi

if [[ $# -gt 1 ]]; then
    fail "Usage: sudo bash $0 [path-or-URL-to-metar.py]"
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
metar_source="${1:-${METAR_PY_URL:-}}"
if [[ -z "$metar_source" && -f "$script_dir/metar.py" ]]; then
    metar_source="$script_dir/metar.py"
fi
if [[ -z "$metar_source" ]]; then
    fail "Provide a metar.py path or URL, or place metar.py beside this installer."
fi

log "Installing Python and LED hardware build dependencies."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential ca-certificates cron curl python3 python3-dev python3-pip

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

metar_file="$tmp_dir/metar.py"
if [[ "$metar_source" =~ ^https?:// ]]; then
    log "Downloading metar.py."
    curl --fail --location --retry 3 --output "$metar_file" "$metar_source"
else
    [[ -f "$metar_source" ]] || fail "METAR source file not found: $metar_source"
    cp -- "$metar_source" "$metar_file"
fi

log "Checking metar.py syntax."
python3 -m py_compile "$metar_file"

log "Installing Python packages."
python3 -m pip install --break-system-packages \
    rpi_ws281x adafruit-circuitpython-neopixel astral

systemctl enable --now cron.service

install_with_backup() {
    local source="$1"
    local destination="$2"

    if [[ -e "$destination" ]] && ! cmp -s "$source" "$destination"; then
        cp -a -- "$destination" "${destination}.bak.$(date '+%Y%m%d%H%M%S')"
        log "Backed up existing file: $destination"
    fi
    install -o root -g root -m 0755 "$source" "$destination"
}

log "Installing METAR display files in ${INSTALL_DIR}."
install -d -o root -g root -m 0755 "$INSTALL_DIR"
install_with_backup "$metar_file" "$INSTALL_DIR/metar.py"

cat > "$tmp_dir/pixelsoff.py" <<'PYTHON_EOF'
import board
import neopixel
try:
    import displaymetar
except ImportError:
    displaymetar = None

pixels = neopixel.NeoPixel(board.D18, 50)

pixels.deinit()

if displaymetar is not None:
    disp = displaymetar.startDisplay()
    displaymetar.shutdownDisplay(disp)

print("LEDs off")
PYTHON_EOF
install_with_backup "$tmp_dir/pixelsoff.py" "$INSTALL_DIR/pixelsoff.py"

cat > "$tmp_dir/airports" <<'AIRPORTS_EOF'
EGJA
NULL
EGDR
EGHQ
EGTE
EGDY
EGHH
EGHI
EGDM
EGGD
EGFF
EGOP
EGOS
EGOV
EGNS
EGAC
EGPK
EGPF
EGPH
EGNT
EGNV
EGNM
EGGP
EGCC
EGNX
EGBB
EGNV
EGUB
EGLL
EGKK
EGLC
EGGW
EGXT
EGXC
EGUL
EGSH
EGSS
EGMC
EGMD
LFAT
AIRPORTS_EOF
install_with_backup "$tmp_dir/airports" "$INSTALL_DIR/airports"

cat > "$tmp_dir/refresh.sh" <<'REFRESH_EOF'
#!/usr/bin/env bash
/usr/bin/pkill -F /home/pi/offpid.pid 2>/dev/null || true
/usr/bin/pkill -F /home/pi/metarpid.pid 2>/dev/null || true
/usr/bin/python3 /home/pi/metar.py &
echo $! > /home/pi/metarpid.pid
REFRESH_EOF
install_with_backup "$tmp_dir/refresh.sh" "$INSTALL_DIR/refresh.sh"

cat > "$tmp_dir/lightsoff.sh" <<'LIGHTSOFF_EOF'
#!/usr/bin/env bash
/usr/bin/pkill -F /home/pi/offpid.pid 2>/dev/null || true
/usr/bin/pkill -F /home/pi/metarpid.pid 2>/dev/null || true
/usr/bin/python3 /home/pi/pixelsoff.py &
echo $! > /home/pi/offpid.pid
LIGHTSOFF_EOF
install_with_backup "$tmp_dir/lightsoff.sh" "$INSTALL_DIR/lightsoff.sh"

log "Updating root cron jobs while preserving unrelated entries."
crontab -l 2>/dev/null > "$tmp_dir/crontab" || true
awk -v start="$CRON_MARKER" -v end="$CRON_END_MARKER" '
    $0 == start { in_block = 1; next }
    $0 == end { in_block = 0; next }
    !in_block &&
    $0 != "*/5 * * * * /home/pi/refresh.sh" &&
    $0 != "0 3 * * * /usr/sbin/reboot" { print }
' "$tmp_dir/crontab" > "$tmp_dir/crontab.filtered"
{
    cat "$tmp_dir/crontab.filtered"
    printf '%s\n' "$CRON_MARKER"
    printf '%s\n' '*/5 * * * * /home/pi/refresh.sh'
    printf '%s\n' '0 3 * * * /usr/sbin/reboot'
    printf '%s\n' "$CRON_END_MARKER"
} | crontab -

log "Setup complete. Test the display with: sudo python3 /home/pi/metar.py"
log "To turn the LEDs off, run: sudo /home/pi/lightsoff.sh"
log "Installed files:"
ls -l "$INSTALL_DIR"
log "Root cron jobs:"
crontab -l
