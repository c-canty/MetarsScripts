# Fresh Raspberry Pi setup

On first boot, connect the Pi to the internet (Wi-Fi or Ethernet) and open a terminal or SSH session. Use **64-bit Raspberry Pi OS** if you also want the Wi-Fi recovery installer.

## Copy and run

Run these commands in order:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/c-canty/MetarsScripts.git
cd MetarsScripts
sudo bash setup-metar-display.sh
```

The display installer installs the required packages and schedules the display to refresh every five minutes.

## Set the airports for the order

The installer puts a default airport list on the Pi. Replace it with the ICAO station IDs for the ordered map, one per line and in LED order:

```bash
sudo nano /home/pi/airports
```

Use `NULL` for an unused LED, and do not list more airports than the `LED_COUNT` setting in `metar.py` (default: 50). Save in nano with **Ctrl+O**, **Enter**, then exit with **Ctrl+X**.

## Test the display

```bash
sudo python3 /home/pi/metar.py
```

To turn the LEDs off:

```bash
sudo /home/pi/lightsoff.sh
```

The next scheduled refresh turns them on again.

## Optional: install automatic Wi-Fi recovery

The Pi needs internet access to install this, and NetworkManager must already be active. Run from the `MetarsScripts` directory:

```bash
sudo bash setup-wifi-connect.sh
```

This requires a 64-bit ARM (`aarch64`) system. After installation, if the Pi cannot reconnect to a saved Wi-Fi network at boot, WiFi Connect starts an access point so you can configure the network from a phone or computer.

## Optional: change display hardware settings

Before installing the display script, edit the configuration to match the ordered hardware:

```bash
nano metar.py
```

Check `LED_COUNT`, `LED_PIN`, and `LED_ORDER` near the top. Save (**Ctrl+O**, **Enter**) and exit (**Ctrl+X**), then run `sudo bash setup-metar-display.sh`.
