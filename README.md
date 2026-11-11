```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/c-canty/MetarsScripts.git
cd MetarsScripts
sudo bash setup-wifi-connect.sh
sudo bash setup-metar-display.sh
```

## Clone the Pi to another SD card (headless)

To make a bootable copy of this Pi for another Pi, connect the destination SD card using a USB card reader. **The destination card will be erased.**

Install `rpi-clone`:

```bash
git clone https://github.com/billw2/rpi-clone.git
sudo install -m 755 rpi-clone/rpi-clone /usr/local/sbin/rpi-clone
sudo install -m 755 rpi-clone/rpi-clone-setup /usr/local/sbin/rpi-clone-setup
```

Identify the destination card:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
```

Check the card's size and model carefully. Do not guess the device name or select the SD card the Pi is running from. Once you have positively identified the destination, replace `sda` below with its device name (without `/dev/`):

```bash
sudo rpi-clone sda
```

Wait for the clone to finish, shut down the Pi, and remove the copied card. When testing it in another Pi on the same network, keep the original Pi powered off to avoid a hostname conflict.
