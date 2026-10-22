#!/bin/bash
# Opsætning af en Raspberry Pi som bt-proxy (BenjaGit-forken) til Home Assistant.
#
# Brug (på Pi'en, som brugeren benjamin med sudo):
#   NAME=bt-proxy-2 FRIENDLY="BT Proxy 2" NET=eth bash setup-pi.sh
#   NAME=bt-proxy-2 FRIENDLY="BT Proxy 2" NET=vlan KEEPWIFI=1 bash setup-pi.sh
#   NAME=bt-proxy-3 FRIENDLY="BT Proxy 3" NET=wifi USBWIFI=1 bash setup-pi.sh
#
# Køres via systemd-run, så det overlever, at SSH-sessionen lukker. Kopiér scriptet
# over med scp.
#
# NET:
#   eth     kabel med IoT som utagget netværk (switchportens Native VLAN / Network =
#           40 - IoT). Kun på en port, Pi'en har for sig selv. WiFi slås fra.
#   vlan    kabel, hvor Pi'en selv tagger VLAN $VLAN (standard 40) på eth0.$VLAN med
#           DHCP, og det utaggede eth0 får ingen IPv4. Brug det bag en AP-port: AP'ens
#           port skal beholde Native VLAN / Network = Default (1) og Tagged VLAN
#           Management = Allow All. Med IoT som native mister AP'ens WiFi-klienter på
#           IoT forbindelsen, og UniFi's client network override virker ikke bag en
#           AP-bro. Det utaggede eth0 slås fra til sidst; står porten stadig på IoT som
#           native, er Pi'en væk, indtil porten er rettet. WiFi slås fra.
#   wifi    WiFi skal allerede være forbundet, f.eks. via Raspberry Pi Imager: til
#           Coldberg_IoT5 (5 GHz) med den indbyggede WiFi, eller til Coldberg_IoT
#           (2,4 GHz) med USBWIFI=1. Strømsparing slås fra.
# USBWIFI=1 WiFi via en USB-adapter (f.eks. RTL8192EU, driver rtl8xxxu), så den
#           indbyggede chip kun laver Bluetooth. Den indbyggede WiFi slås fra
#           (dtoverlay=disable-wifi), og forbindelsen bindes til adapterens MAC, fordi
#           adapteren skifter navn fra wlan1 til wlan0 ved genstarten. Kræver genstart,
#           og DHCP-reservationen skal laves på den MAC, scriptet skriver ud.
# DONGLE=1  brug en USB-Bluetooth-dongle og slå den indbyggede Bluetooth fra
#           (dtoverlay=disable-bt), så dongle'en bliver hci0. Kræver genstart.
# KEEPWIFI=1 (eth/vlan) lad den indbyggede WiFi blive tændt som reserveadgang. Den
#           skal allerede være forbundet til Coldberg_IoT; kablet vinder på rute-metric.
# LOG_URL   hvor journalen sendes hen (systemd-journal-upload). Standard er VictoriaLogs
#           i LXC 105 'logs' på nuc-pve. LOG_URL= (tom) slår det fra.
# OVERLAY=1 skrivebeskyttet rod (overlayfs, raspi-config) til sidst, så USB-nøglen/
#           SD-kortet ikke slides. Alt skrevet efter genstarten ligger i RAM. Opdatering:
#           'sudo bt-proxy-overlay off' + genstart, opdatér, 'sudo bt-proxy-overlay on' +
#           genstart. Kør altid scriptet igen med overlay slået fra.
set -u
if grep -q ' / overlay ' /proc/mounts; then
  echo "Roden er skrivebeskyttet (overlay): kør 'sudo bt-proxy-overlay off', genstart og prøv igen."
  exit 1
fi
: "${NAME:?NAME mangler, f.eks. bt-proxy-2}"
: "${FRIENDLY:?FRIENDLY mangler, f.eks. \"BT Proxy 2\"}"
: "${NET:?NET mangler: eth, vlan eller wifi}"
DONGLE="${DONGLE:-0}"
USBWIFI="${USBWIFI:-0}"
KEEPWIFI="${KEEPWIFI:-0}"
OVERLAY="${OVERLAY:-0}"
LOG_URL="${LOG_URL-http://192.168.80.222:9428/insert/journald}"
VLAN="${VLAN:-40}"
[ "$USBWIFI" = 1 ] && [ "$NET" != wifi ] && { echo "USBWIFI=1 kræver NET=wifi"; exit 1; }
[ "$KEEPWIFI" = 1 ] && [ "$NET" = wifi ] && { echo "KEEPWIFI=1 giver kun mening med NET=eth eller vlan"; exit 1; }
[ "$USBWIFI" = 1 ] && [ "$DONGLE" = 1 ] && { echo "Vælg enten USBWIFI=1 eller DONGLE=1"; exit 1; }
MAC_IF=eth0
TAG="${TAG:-v1.0.3-benjagit.7}"
HA_IP="${HA_IP:-192.168.40.2}"
CFG=/boot/firmware/config.txt
REBOOT=0
UNTAGGED_CON=""
step() { echo; echo "=== $*"; }
wifi_off() {
  if [ "$KEEPWIFI" = 1 ]; then
    grep -q '^dtoverlay=disable-wifi' "$CFG" && { sudo sed -i 's/^dtoverlay=disable-wifi/#dtoverlay=disable-wifi/' "$CFG"; REBOOT=1; }
    sudo nmcli radio wifi on && echo "nmcli: wifi on (reserve)"
    nmcli -t -f NAME,DEVICE con show --active | grep wlan0 || echo "ADVARSEL: wlan0 er ikke forbundet"
    return
  fi
  sudo nmcli radio wifi off && echo "nmcli: wifi off"
  grep -q '^dtoverlay=disable-wifi' "$CFG" || { echo 'dtoverlay=disable-wifi' | sudo tee -a "$CFG"; REBOOT=1; }
}

step "System"
# Subshell: os-release definerer selv NAME og ville overskrive vores.
(. /etc/os-release; echo "$PRETTY_NAME / $(uname -m) / kernel $(uname -r)")
vcgencmd get_throttled || true
sudo hostnamectl set-hostname "$NAME" && echo "hostname: $NAME"

step "Netværk ($NET)"
case "$NET" in
  eth)
    wifi_off
    ;;
  vlan)
    wifi_off
    UNTAGGED_CON=$(nmcli -t -f NAME,TYPE,DEVICE con show | awk -F: '$2=="802-3-ethernet" && $3=="eth0"{print $1; exit}')
    [ -n "$UNTAGGED_CON" ] || { echo "Ingen aktiv kabelforbindelse på eth0"; exit 1; }
    # Uendelig DHCP-ventetid: porten kan stå forkert lige nu og blive rettet bagefter.
    VLAN_OPTS=(ipv4.method auto ipv6.method ignore connection.autoconnect yes
      connection.autoconnect-retries 0 ipv4.dhcp-timeout infinity)
    if nmcli -t -f NAME con show | grep -qx "vlan$VLAN"; then
      sudo nmcli con modify "vlan$VLAN" "${VLAN_OPTS[@]}"
    else
      sudo nmcli con add type vlan con-name "vlan$VLAN" ifname "eth0.$VLAN" dev eth0 id "$VLAN" "${VLAN_OPTS[@]}"
    fi
    echo "vlan$VLAN: eth0.$VLAN med DHCP. '$UNTAGGED_CON' mister sin IPv4 til sidst."
    ;;
  wifi)
    CON=$(nmcli -t -f NAME,TYPE con show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
    [ -n "$CON" ] || { echo "Ingen aktiv WiFi-forbindelse. Forbind til Coldberg_IoT(5) først."; exit 1; }
    SSID=$(nmcli -g 802-11-wireless.ssid con show "$CON")
    MAC_IF=wlan0
    if [ "$USBWIFI" = 1 ]; then
      # USB-adapteren er det trådløse interface, hvis driver ikke er Pi'ens brcmfmac.
      USB_IF=""
      for d in /sys/class/net/*/wireless; do
        IF=$(basename "$(dirname "$d")")
        DRV=$(basename "$(readlink "/sys/class/net/$IF/device/driver")")
        [ "$DRV" != brcmfmac ] && { USB_IF=$IF; echo "USB-WiFi: $IF ($DRV)"; }
      done
      [ -n "$USB_IF" ] || { echo "Ingen USB-WiFi-adapter fundet (lsusb):"; lsusb; exit 1; }
      [ "$SSID" = Coldberg_IoT5 ] && { echo "Adapteren kan kun 2,4 GHz: forbind til Coldberg_IoT, ikke Coldberg_IoT5."; exit 1; }
      USB_MAC=$(cat "/sys/class/net/$USB_IF/address")
      # Bind til MAC'en, ikke navnet: adapteren hedder wlan0 efter genstarten.
      sudo nmcli con modify "$CON" connection.autoconnect-retries 0 connection.interface-name "" \
        802-11-wireless.mac-address "$USB_MAC" 802-11-wireless.cloned-mac-address permanent \
        802-11-wireless.band bg 802-11-wireless.powersave 2
      grep -q '^dtoverlay=disable-wifi' "$CFG" || { echo 'dtoverlay=disable-wifi' | sudo tee -a "$CFG"; REBOOT=1; }
      MAC_IF=$USB_IF
      echo "Forbindelsen '$CON' ($SSID) tager over på $USB_IF ved genstarten."
    else
      sudo nmcli con modify "$CON" connection.autoconnect-retries 0 802-11-wireless.band a 802-11-wireless.powersave 2
      sudo nmcli con up "$CON" >/dev/null
      iw dev wlan0 link | grep -E 'SSID|freq|signal'
      iw dev wlan0 link | awk '/freq/{exit !($2 >= 5000)}' || { echo "ADVARSEL: ikke på 5 GHz"; }
    fi
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

step "Netværks-watchdog: genstart efter 10 min uden gateway"
# NetworkManager kan give op på WiFi'en, og så hænger Pi'en uden net, mens dens
# BLE-forbindelser bliver holdt. En genstart redder begge dele. Tælleren ligger i /run.
sudo tee /usr/local/sbin/net-watchdog >/dev/null <<'EOF'
#!/bin/sh
F=/run/net-watchdog.fails
GW=$(ip -4 route show default | awk '{print $3; exit}')
if [ -n "$GW" ] && ping -c 3 -W 2 "$GW" >/dev/null 2>&1; then
  rm -f "$F"; exit 0
fi
N=$(( $(cat "$F" 2>/dev/null || echo 0) + 1 )); echo "$N" > "$F"
echo "ingen svar fra gateway '${GW:-ingen rute}' ($N/10)"
[ "$N" -ge 10 ] && { echo "genstarter"; systemctl reboot; }
exit 0
EOF
sudo chmod 755 /usr/local/sbin/net-watchdog
sudo tee /etc/systemd/system/net-watchdog.service >/dev/null <<'EOF'
[Unit]
Description=Reboot when the default gateway has been unreachable for 10 minutes

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/net-watchdog
EOF
sudo tee /etc/systemd/system/net-watchdog.timer >/dev/null <<'EOF'
[Unit]
Description=Check the default gateway every minute

[Timer]
OnBootSec=5min
OnUnitActiveSec=1min
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF

step "Journal: i RAM, sendes til ${LOG_URL:-(slået fra)}"
sudo install -d /etc/systemd/journald.conf.d
# Plads nok i RAM til at holde et længere netværksudfald, indtil det kan sendes.
printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=40M\n' | sudo tee /etc/systemd/journald.conf.d/10-volatile.conf >/dev/null
if [ -n "$LOG_URL" ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends systemd-journal-remote >/dev/null
  # Kun uploaderen; modtageren skal ikke køre her.
  sudo systemctl disable --now systemd-journal-remote.socket systemd-journal-remote.service 2>/dev/null || true
  sudo install -d /etc/systemd/journal-upload.conf.d /etc/systemd/system/systemd-journal-upload.service.d
  printf '[Upload]\nURL=%s\n' "$LOG_URL" | sudo tee /etc/systemd/journal-upload.conf.d/10-victorialogs.conf >/dev/null
  printf '[Unit]\nStartLimitIntervalSec=0\n[Service]\nRestart=always\nRestartSec=30\n' \
    | sudo tee /etc/systemd/system/systemd-journal-upload.service.d/10-restart.conf >/dev/null
fi

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
sudo systemctl restart systemd-journald bluetooth
UNITS="nftables bt-proxy bt-proxy-watchdog.timer net-watchdog.timer"
[ -n "$LOG_URL" ] && UNITS="$UNITS systemd-journal-upload"
# shellcheck disable=SC2086
sudo systemctl enable --now $UNITS 2>&1 | grep -v '^Created symlink' || true
[ -n "$LOG_URL" ] && sudo systemctl restart systemd-journal-upload
sleep 15
# shellcheck disable=SC2086
systemctl is-active bluetooth $UNITS
sudo nft list ruleset | grep 6053
journalctl -u bt-proxy -n 15 --no-pager
ip -4 -br addr | grep -v '^lo'
ip link show "$MAC_IF" | awk -v i="$MAC_IF" '/ether/{print i, "MAC (til DHCP-reservation):", $2}'
[ "$USBWIFI" = 1 ] && echo "Bluetooth bliver på den indbyggede chip (hci0); tjek efter genstarten: ls /sys/class/bluetooth"
if [ -n "$UNTAGGED_CON" ]; then
  # Til sidst, så alt ovenfor er skrevet ud, før en forkert sat port tager Pi'en af nettet.
  step "Utagget eth0 ('$UNTAGGED_CON'): ingen IPv4"
  sudo nmcli con modify "$UNTAGGED_CON" ipv4.method disabled ipv6.method ignore
  sudo nmcli con up "$UNTAGGED_CON" >/dev/null
  sleep 10
  ip -4 -br addr | grep -v '^lo'
  ip -4 addr show "eth0.$VLAN" | grep -q inet \
    || echo "ADVARSEL: eth0.$VLAN har ingen IP endnu. AP-/switchporten skal have Native VLAN / Network = Default (1) og Tagged VLAN Management = Allow All."
fi
step "bt-proxy-overlay (skrivebeskyttet rod)"
sudo tee /usr/local/sbin/bt-proxy-overlay >/dev/null <<'EOF'
#!/bin/sh
# on|off|status: skrivebeskyttet rod via raspi-config. Virker ved næste genstart.
case "$1" in
  on)  raspi-config nonint do_overlayfs 0 && echo "overlay slås TIL ved næste genstart" ;;
  off) raspi-config nonint do_overlayfs 1 && echo "overlay slås FRA ved næste genstart" ;;
  status) grep -q ' / overlay ' /proc/mounts && echo "nu: overlay (skrivebeskyttet)" || echo "nu: skrivbar" ;;
  *) echo "brug: bt-proxy-overlay on|off|status"; exit 2 ;;
esac
EOF
sudo chmod 755 /usr/local/sbin/bt-proxy-overlay
if [ "$OVERLAY" = 1 ]; then
  sudo bt-proxy-overlay on
  REBOOT=1
fi
[ "$REBOOT" = 1 ] && echo && echo ">>> Kræver genstart: kør 'sudo reboot'."
exit 0
