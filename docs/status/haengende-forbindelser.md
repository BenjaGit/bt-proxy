# Hængende BLE-forbindelser, som ingen lukker

Bestilt af danfoss-eco-ha 20/11-2026.

## Næste skridt

1. Lukningen virker i drift: 20/11 kl. 21:50–22:20 lukkede proxyen 4 ubrugte links på bt-proxy-1
   og 1 på bt-proxy-3 (`Closing … connected but unused`). HA efterlader altså stadig links; find
   ud af hvorfor på HA-siden.
2. Kontor 2 (`…95:76:85`) bliver forsøgt igen fra 20:45, men havde ikke fået en vellykket
   forbindelse kl. 20:51 (timeout og tabt link, som ved de øvrige mislykkede forsøg). Tjek at den
   kommer igennem.
3. `v1.0.3-benjagit.11` er permanent på alle tre Pi'er fra 20/11 kl. 22:55: tagget er tjekket ud
   i det nedre, skrivebeskyttede lag (`/media/root-ro/opt/bt-proxy`, genmonteret rw og tilbage til
   ro), uden genstart. `deploy/setup-pi.sh` har `.11` som standard-tag. Ikke afprøvet med en
   genstart af en Pi endnu.
4. danfoss-eco-ha ser efter, om HA-siden undlader at sende disconnect ved annullering.

## I drift

`v1.0.3-benjagit.9` deployet med Benjamins ja 20/11: bt-proxy-1 kl. 20:46:53, bt-proxy-2 kl.
20:48:13, bt-proxy-3 kl. 20:49:31 (`git checkout` af tagget i `/opt/bt-proxy` og
`systemctl restart bt-proxy`). Efter genstart: `Cache = always` på -1, interval 6/12/200 på -2 og
`BT_PROXY_PAUSE_SCAN_ON_CONNECT=1` på -3 er uændrede.

Efter lukningen kl. 20:43 forbindes gæstetoilet igen (20:45:32 og 20:48:36) og lager (20:50:07).

Rul tilbage: `git -C /opt/bt-proxy checkout -q v1.0.3-benjagit.7` (bt-proxy-3: `.8`) og
`sudo systemctl restart bt-proxy`, eller sæt `BT_PROXY_IDLE_TIMEOUT=0` i en drop-in.

## Den egentlige årsag (fundet 20/11 kl. 22:25, rettet i `v1.0.3-benjagit.11`)

Afsnittet "Årsag" nedenfor gættede på en annullering i HA. Det var forkert. Forløbet, set i
journalen på bt-proxy-1 og i HA's log (gang `…09:A2`, lokal tid):

1. 22:12:18.606 proxyen forbinder til stue karnap; det fejler efter 30 s kl. 22:12:48.617.
2. 22:12:48.619 proxyen går i gang med gang, 2 ms senere. HA havde sendt den anmodning, mens den
   forrige stadig kørte. Proxyen behandler beskeder én ad gangen, så den stod i kø.
3. Kø + 16,7 s opkobling er over HA's ventetid, så HA giver op og sender en disconnect. Den udføres
   2 ms efter "Connected" (22:13:05.328).
4. Proxyen sendte **to** "disconnected" til HA: én da linket gik ned (22:13:07.508) og kvitteringen
   ca. 1,1 s senere, efter BlueZ-oprydningen.
5. HA havde efter den første sendt sit næste connect (22:13:08.661) og læste den sene kvittering
   som at det fejlede ("Disconnected" 7 ms senere). Proxyen forbandt alligevel kl. 22:13:20, og
   ingen brugte eller lukkede linket.

Rettet: ét svar pr. disconnect-anmodning, sendt når linket er nede; BlueZ-oprydningen kører
bagefter. En rapport fra BlueZ om et allerede frigivet link sendes ikke videre og kan ikke
afregistrere et nyere link til samme adresse. Test: `tests/test_api_cleanup.py`,
`tests/test_connection_tracking.py`.

Ikke rettet i proxyen: køen (punkt 2). Anmodninger behandles stadig én ad gangen, så et connect, der
sendes mens et andet kører, bruger af HA's ventetid i køen. danfoss_eco er bedt om aldrig at sende
to connects til samme proxy samtidig. Mulig rettelse her, hvis det ikke er nok: regn budgettet fra
anmodningen ankom, og svar fejl med det samme, hvis der er for lidt tilbage.

Deployet 20/11 kl. 22:30:43 (bt-proxy-1), 22:31:06 (-2), 22:31:30 (-3).

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
