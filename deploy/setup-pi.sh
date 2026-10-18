#!/bin/bash
# Opsætning af en Raspberry Pi som bt-proxy (BenjaGit-forken) til Home Assistant.
#
# Brug (på Pi'en, som brugeren benjamin med sudo):
#   NAME=bt-proxy-2 FRIENDLY="BT Proxy 2" NET=eth bash setup-pi.sh
#   NAME=bt-proxy-3 FRIENDLY="BT Proxy 3" NET=wifi DONGLE=1 bash setup-pi.sh
#
# Køres via systemd-run, så det overlever, at SSH-sessionen lukker. Kopiér scriptet
# over med scp.
#
# NET:
#   eth     kabel med IoT som utagget netværk. Pi'en tagger ikke selv VLAN'er; bag en
#           AP-port sættes switchportens native VLAN til IoT (UniFi's client network
#           override virker ikke bag en AP-bro). WiFi slås fra.
#   wifi    WiFi skal allerede være forbundet til Coldberg_IoT5 (5 GHz), f.eks. via
#           Raspberry Pi Imager. Forbindelsen låses til 5 GHz, og strømsparing slås fra.
# DONGLE=1  brug en USB-Bluetooth-dongle og slå den indbyggede Bluetooth fra
#           (dtoverlay=disable-bt), så dongle'en bliver hci0. Kræver genstart.
set -u
: "${NAME:?NAME mangler, f.eks. bt-proxy-2}"
: "${FRIENDLY:?FRIENDLY mangler, f.eks. \"BT Proxy 2\"}"
: "${NET:?NET mangler: eth eller wifi}"
DONGLE="${DONGLE:-0}"
TAG="${TAG:-v1.0.3-benjagit.3}"
HA_IP="${HA_IP:-192.168.40.2}"
CFG=/boot/firmware/config.txt
REBOOT=0
step() { echo; echo "=== $*"; }

step "System"
# Subshell: os-release definerer selv NAME og ville overskrive vores.
(. /etc/os-release; echo "$PRETTY_NAME / $(uname -m) / kernel $(uname -r)")
vcgencmd get_throttled || true
sudo hostnamectl set-hostname "$NAME" && echo "hostname: $NAME"

step "Netværk ($NET)"
case "$NET" in
  eth)
    sudo nmcli radio wifi off && echo "nmcli: wifi off"
    grep -q '^dtoverlay=disable-wifi' "$CFG" || { echo 'dtoverlay=disable-wifi' | sudo tee -a "$CFG"; REBOOT=1; }
    ;;
  wifi)
    CON=$(nmcli -t -f NAME,TYPE con show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
    [ -n "$CON" ] || { echo "Ingen aktiv WiFi-forbindelse. Forbind til Coldberg_IoT5 først."; exit 1; }
    sudo nmcli con modify "$CON" 802-11-wireless.band a 802-11-wireless.powersave 2
    sudo nmcli con up "$CON" >/dev/null
    iw dev wlan0 link | grep -E 'SSID|freq|signal'
    iw dev wlan0 link | awk '/freq/{exit !($2 >= 5000)}' || { echo "ADVARSEL: ikke på 5 GHz"; }
    ;;
  *) echo "Ukendt NET=$NET"; exit 1 ;;
esac

if [ "$DONGLE" = 1 ]; then
  step "USB-dongle: indbygget Bluetooth fra"
  grep -q '^dtoverlay=disable-bt' "$CFG" || { echo 'dtoverlay=disable-bt' | sudo tee -a "$CFG"; REBOOT=1; }
  sudo systemctl disable --now hciuart 2>/dev/null || true
  lsusb | grep -iE 'bluetooth|0bda:|8087:|0a12:' || echo "ADVARSEL: ingen USB-dongle fundet"
fi

step "Pakker"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git rfkill nftables iw >/dev/null && echo "git rfkill nftables iw ok"
sudo rfkill unblock bluetooth
bluetoothctl --version

step "BlueZ: GATT-cache kun for bundne enheder, ingen --experimental"
# Cache=always gav HA en gammel GATT-tabel uden nøglekarakteristikken under parring.
# --experimental (passiv scanning) får eTRV'er med konstant advert til at gå stale.
[ -f /etc/bluetooth/main.conf.orig ] || sudo cp /etc/bluetooth/main.conf /etc/bluetooth/main.conf.orig
if grep -qE '^#?\s*Cache\s*=' /etc/bluetooth/main.conf; then
  sudo sed -i -E 's/^#?\s*Cache\s*=.*/Cache = yes/' /etc/bluetooth/main.conf
else
  printf '\n[GATT]\nCache = yes\n' | sudo tee -a /etc/bluetooth/main.conf >/dev/null
fi
grep -E '^Cache' /etc/bluetooth/main.conf
sudo rm -f /etc/systemd/system/bluetooth.service.d/experimental.conf

step "uv"
command -v uv >/dev/null || [ -x ~/.local/bin/uv ] || curl -LsSf https://astral.sh/uv/install.sh | sh -s -- -q
~/.local/bin/uv --version

step "bt-proxy ($TAG)"
[ -d /opt/bt-proxy/.git ] || sudo git clone -q https://github.com/BenjaGit/bt-proxy.git /opt/bt-proxy
sudo chown -R "$USER": /opt/bt-proxy
git -C /opt/bt-proxy fetch -q --tags && git -C /opt/bt-proxy checkout -q "$TAG"
git -C /opt/bt-proxy log -1 --format='commit %h %cd %s' --date=short
cd /opt/bt-proxy && timeout 900 ~/.local/bin/uv sync -q && echo "uv sync ok"

step "systemd: bt-proxy + watchdog"
sed "s|-m bt_proxy|-m bt_proxy --name $NAME --friendly-name \"$FRIENDLY\" --adapter hci0|" /opt/bt-proxy/bt-proxy.service \
  | sudo tee /etc/systemd/system/bt-proxy.service >/dev/null
sudo tee /etc/systemd/system/bt-proxy-watchdog.service >/dev/null <<'EOF'
[Unit]
Description=Restart bluetoothd if unresponsive

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'journalctl -u bt-proxy --since "-3min" | grep -q "bluetoothd is wedged" && systemctl restart bluetooth || true'
EOF
sudo tee /etc/systemd/system/bt-proxy-watchdog.timer >/dev/null <<'EOF'
[Unit]
Description=Periodically check whether bluetoothd needs restarting

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF

step "nftables: kun HA ($HA_IP) må nå 6053"
sudo tee /etc/nftables.conf >/dev/null <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy accept;
    tcp dport 6053 ip saddr != $HA_IP drop
  }
}
EOF

step "Start"
sudo systemctl daemon-reload
sudo systemctl restart bluetooth
sudo systemctl enable --now nftables bt-proxy bt-proxy-watchdog.timer 2>&1 | grep -v '^Created symlink' || true
sleep 15
systemctl is-active bluetooth nftables bt-proxy bt-proxy-watchdog.timer
sudo nft list ruleset | grep 6053
journalctl -u bt-proxy -n 15 --no-pager
ip -4 -br addr | grep -v '^lo'
IF=eth0; [ "$NET" = wifi ] && IF=wlan0
ip link show "$IF" | awk -v i="$IF" '/ether/{print i, "MAC (til DHCP-reservation):", $2}'
[ "$REBOOT" = 1 ] && echo && echo ">>> config.txt er ændret: kør 'sudo reboot'."
exit 0
