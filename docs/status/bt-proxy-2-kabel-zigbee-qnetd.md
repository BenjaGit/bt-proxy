# bt-proxy-2: kabel, ser2net (Zigbee) og corosync-qnetd

Bestilt af homeassistant 21/11-2026 (svar til pane w5:pR). Plan på HA-siden:
`homeassistant/docs/superpowers/plans/2026-11-21-proxmox-cluster-ha.md` (task 5 step 1, task 11 step 1).

## Næste skridt

1. **Venter på homeassistant (21/11 kl. 14:42):** 41.5-reservationen skal flyttes til eth-MAC
   `b8:27:eb:97:3e:f7`. Pi'en står på kabel med den midlertidige adresse 192.168.41.7 (SSH:
   `ssh -o HostName=192.168.41.7 -o HostKeyAlias=192.168.41.5 bt-proxy-2`).
2. Når reservationen er flyttet: `sudo reboot` (overlay er sat til at slå TIL ved næste genstart).
3. Verificér: `eth0` = 192.168.41.5, `wlan0` væk, bt-proxy aktiv og forbundet til HA, ser2net
   lytter på 6638, qnetd på 5403, journalen kommer frem i hubben. Svar til w5:pR, og skriv til
   danfoss-eco-ha (wK:p1), at Pi'en er stabil, med tidsrummene nedenfor.

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

## Til svaret til homeassistant

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
