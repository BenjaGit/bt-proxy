# Hængende BLE-forbindelser, som ingen lukker

Bestilt af danfoss-eco-ha 20/11-2026.

## Næste skridt

1. **Deploy `v1.0.3-benjagit.9` til de tre Pi'er.** Kræver genstart af `bt-proxy` på hver; afventer
   Benjamins ja. Rettelsen er committet, tagget og pushet, men kører ikke nogen steder endnu.
2. Efter deploy: se i journalen efter `Closing … connected but unused for 60 s`. Hver linje er en
   forbindelse, HA har efterladt.
3. Indtil deploy kan fejlen komme igen. Luk hængende forbindelser uden genstart med kommandoen under
   "Luk uden genstart".

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
