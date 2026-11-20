# Hængende BLE-forbindelser, som ingen lukker

Bestilt af danfoss-eco-ha 20/11-2026.

## Næste skridt

1. Se i journalen efter `Closing … connected but unused for 60 s`. Hver linje er en forbindelse, HA
   har efterladt. Ingen set endnu (kl. 20:51); rettelsen er altså testet i `tests/`, men ikke set
   virke i drift.
2. Kontor 2 (`…95:76:85`) bliver forsøgt igen fra 20:45, men havde ikke fået en vellykket
   forbindelse kl. 20:51 (timeout og tabt link, som ved de øvrige mislykkede forsøg). Tjek at den
   kommer igennem.
3. `.9` ligger kun i RAM på Pi'erne (overlay). En genstart af en Pi ruller den tilbage til `.7`, og
   så er fejlen der igen. Gør den permanent: sæt `TAG=v1.0.3-benjagit.9` som standard i
   `deploy/setup-pi.sh` og kør den uden om overlayet. Ikke gjort.
4. danfoss-eco-ha ser efter, om HA-siden undlader at sende disconnect ved annullering.

## I drift

`v1.0.3-benjagit.9` deployet med Benjamins ja 20/11: bt-proxy-1 kl. 20:46:53, bt-proxy-2 kl.
20:48:13, bt-proxy-3 kl. 20:49:31 (`git checkout` af tagget i `/opt/bt-proxy` og
`systemctl restart bt-proxy`). Efter genstart: `Cache = always` på -1, interval 6/12/200 på -2 og
`BT_PROXY_PAUSE_SCAN_ON_CONNECT=1` på -3 er uændrede.

Efter lukningen kl. 20:43 forbindes gæstetoilet igen (20:45:32 og 20:48:36) og lager (20:50:07).

Rul tilbage: `git -C /opt/bt-proxy checkout -q v1.0.3-benjagit.7` (bt-proxy-3: `.8`) og
`sudo systemctl restart bt-proxy`, eller sæt `BT_PROXY_IDLE_TIMEOUT=0` i en drop-in.

## Hvad der skete

bt-proxy-1 holdt tre forbindelser i over en time (kontor 2 `…95:76:85` fra 19:09:52, lager
`…95:32:99` fra 19:11:02, gæstetoilet `…0F:09:DD` fra 20:15:44). `hcitool con` viste alle tre links
oppe kl. 20:42. En termostat med et link oppe annoncerer ikke, så HA så dem ikke længere, og de tre
pladser var optaget ("No free connection slots" fra 20:00:44).

## Årsag

Proxyen behandler HA's beskeder én ad gangen, så en disconnect, der ankommer under en igangværende
connect, bliver udført lige bagefter. Den vej virker (se 20:15:32: "Connected" og "Disconnecting" i
samme millisekund).

Fejlen opstår, når HA slet ikke sender en disconnect. Det sker, når connect-kaldet på HA-siden
bliver annulleret, mens proxyen stadig forbinder: proxyen gennemfører, svarer "forbundet", og ingen
bruger eller lukker linket. Proxyen havde ingen grænse for, hvor længe et ubrugt link måtte stå.
Linket blev kun ryddet, hvis HA's API-forbindelse til proxyen faldt.

At HA annullerer uden disconnect er udledt af journalen (intet "Disconnecting from" efter
"Connected", og kontor 2's andet forsøg startede 17 s inde i HA's samlede ventetid). Det er ikke set
på HA-siden; det undersøger danfoss-eco-ha.

## Rettelse (`v1.0.3-benjagit.9`)

Et link, som klienten ikke har brugt i 60 s, lukkes af proxyen, og HA får besked. "Brugt" er
connect, enhver GATT-forespørgsel og modtagne notifikationer. Links med et aktivt
notifikations-abonnement røres ikke.

- Grænsen sættes med `--idle-timeout <sekunder>` eller `BT_PROXY_IDLE_TIMEOUT`; `0` slår den fra.
- Kode: `bt_proxy/ble_manager.py` (`_close_idle_connections`), test: `tests/test_idle_disconnect.py`.

## Luk uden genstart

Gjort 20/11 kl. 20:43 på bt-proxy-1; alle tre links forsvandt, og tjenesten (startet 15:45:33) kørte
videre og forbandt til andre termostater sekunder efter:

```
ssh bt-proxy-1 'hcitool con'                       # hvilke links er oppe
ssh bt-proxy-1 'bluetoothctl disconnect <MAC>'     # én pr. hængende adresse
```

BlueZ melder afbrydelsen til bt-proxy, som frigiver pladsen og giver HA besked.

## Hensyn til forsøgene fra 15:46

En genstart af `bt-proxy` rører ikke forsøgene på bt-proxy-1 og -2 (de ligger i BlueZ og kernen).
På bt-proxy-3 skal drop-in'en med `BT_PROXY_PAUSE_SCAN_ON_CONNECT=1` blive liggende; `.9` indeholder
flaget. Målingen bliver dog ikke ren: de hængende links og den nye lukning ændrer tallene fra 19:09
og frem, og danfoss_eco `.14` forbinder langt oftere end i baseline-ugen.
Se `ble-success-rate.md`.
