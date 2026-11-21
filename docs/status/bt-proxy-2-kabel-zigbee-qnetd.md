# bt-proxy-2: kabel, ser2net (Zigbee) og corosync-qnetd

Bestilt af homeassistant 21/11-2026 (svar til pane w5:pR). Plan på HA-siden:
`homeassistant/docs/superpowers/plans/2026-11-21-proxmox-cluster-ha.md` (task 5 step 1, task 11 step 1).

## Næste skridt

Opgaven er færdig og svaret sendt til homeassistant (w5:pR) 21/11 kl. 14:45. Tilbage står kun:

1. Zigbee-donglen flyttes til Pi'en af Benjamin (HA-planens task 5). Tjek bagefter
   `ls -l /dev/serial/by-id/` og `journalctl -u ser2net` på bt-proxy-2.
2. Før `pvecm qdevice setup`: slå overlay fra og genstart, og slå det til igen bagefter.
3. Slet filen, når de to ting er gjort.

## Forløb 21/11

- 13:37 Pi'en flyttet til racket (Benjamin).
- 14:28–14:33 væk fra nettet: WiFi-klienten blev glemt i UniFi og røg på VLAN 40 (rettet af
  homeassistant).
- 14:34 `eth0` bragt op (profilen stod med autoconnect=no og ipv4 disabled); netplan-filen kopieret
  til det nedre lag. 14:34:53 genstart med overlay fra, oppe 14:36.
- 14:37–14:40 `setup-pi.sh` kørt med `NAME=bt-proxy-2 FRIENDLY="BT Proxy 2" NET=eth ZIGBEE=1
  QNETD=1 OVERLAY=1` og den eksisterende `UPDATE_WEBHOOK`. WiFi taget ned 14:37 (lease frigivet).
- 14:41 testet: ser2net svarer uden dongle med "Device open failure" og lukker; tjenesten kører
  videre. qnetd aktiv, nssdb oprettet.

- 14:41:58 genstart med overlay til, oppe 14:42:50. `eth0` = 192.168.41.5 (reservationen flyttet
  af homeassistant), `wlan0` findes ikke, HA forbundet 14:42:52, ser2net på 6638, qnetd på 5403,
  journalen i hubben 14:44.

## Givet videre til homeassistant

- `pvecm qdevice setup` skriver clusterens certifikat i `/etc/corosync/qnetd/nssdb`. Under overlay
  ligger det i RAM og er væk efter en genstart: gør det med overlay slået fra.
- `bt-proxy-update` genstarter Pi'en to gange, når der er pakkeopdateringer (tirsdag kl. 04:00).
  Zigbee og QDevice er nede imens.
- ser2net åbner serielporten med DTR/RTS sat, som ZHA gør i dag direkte på donglen.
- Zigbee-donglen ved siden af Pi'ens Bluetooth-antenne deler 2,4 GHz-båndet.

## Ændret i `deploy/setup-pi.sh`

- `ZIGBEE=1` (ser2net, `/etc/ser2net.yaml`) og `QNETD=1` (corosync-qnetd).
- `NET=eth` slår først WiFi fra, når `eth0` har en IPv4-adresse.
- nftables: accept + drop pr. port (lukker også IPv6), `lo` altid tilladt, reglerne genindlæses.

## danfoss-eco-ha

Har fået besked 21/11 kl. 14:36 om flytningen til racket (13:37) og nedetiden fra 14:28:28.
