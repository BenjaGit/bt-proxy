# BLE-forbindelser til Danfoss Eco: hvorfor kun ca. 1 af 4 lykkes

Undersøgt 20/11-2026 (bestilt af homeassistant). Tre forsøg kører fra 20/11 kl. 15:46, se nedenfor.

## Næste skridt

1. **Mål lørdag 21/11 efter kl. 15:50** (24 t efter start): success-rate og varighed pr. Pi
   fra hubben for 20/11 15:50 – 21/11 15:50 mod baseline 14/11–20/11 (bt-proxy-1 25 %,
   bt-proxy-2 22 %, bt-proxy-3 20 %). Forespørgslen står under (b). Der er ingen urørt
   kontrol-Pi, så sammenlign hver Pi med sin egen baseline.
2. Behold det, der virker, permanent (se "Gør et forsøg permanent"), og rul resten tilbage.
3. Knækket 10/11 kl. ca. 17 er stadig uforklaret (se "Knækket 10/11").
4. **bt-proxy-3 blev drejet 20/11 kl. ca. 21:05** (se "bt-proxy-3 drejet"). Tallene for bt-proxy-3
   efter det tidspunkt blander scan-pausen og drejningen; del målingen i før og efter 21:05.
5. Benjamin vil flytte bt-proxy-3 op på et skab, når han har en forlængerledning. Mål signalet
   igen bagefter med kommandoen under "bt-proxy-3 drejet".

## Connect-budget 30 s (`v1.0.3-benjagit.10`, bestilt af danfoss-eco-ha 20/11)

Benjamin sagde ja til to ændringer: tidsgrænsen for en connect-anmodning fra 15 s til 30 s, og
nyt forsøg med det samme, når linket tabes under opkobling.

- `CONNECT_TIMEOUT` er nu 30 s. Genforsøg efter tabt link fandtes allerede, men kørte aldrig: det
  kræver 10 s tilbage af budgettet, og linket tabes typisk 7 eller 11 s inde i et forsøg på 15 s.
  Med 30 s er der plads til ét eller to nye forsøg i samme anmodning.
- Oprydning efter et mislykket forsøg er begrænset til 5 s, så svaret kommer senest efter ca. 35 s.
  **HA skal vente længere end det:** danfoss_eco `.15` venter 40 s. Med `.14` (20 s) giver HA op
  før proxyen, og de næste anmodninger står i kø bag den.
- Kan sættes pr. Pi uden ny version: `BT_PROXY_CONNECT_TIMEOUT=<sekunder>` i en drop-in.
- Spærringen efter gentagne fejl (5 s pr. fejl i træk, højst 60 s) er uændret.

Før-tal fra danfoss-eco-ha, 40 min før kl. 21:40 (forsøg / ok / tabt / timeout / not found):
bt-proxy-1 197 / 62 / 60 / 56 / 16, bt-proxy-2 180 / 66 / 43 / 49 / 18, bt-proxy-3 135 / 34 / 44 /
22 / 31.

Deployet 20/11 kl. 21:48:22 (bt-proxy-1), 21:48:48 (-2) og 21:49:12 (-3). Målt fra hubben
21:50–22:20, talt pr. anmodning ("Connected to" + "Failed to connect to"), fordi "Connecting to" nu
logges pr. forsøg:

| Pi | Anmodninger | Ok | Tabt link | Timeout 30 s | Not found | Ok-andel | Før |
|---|---|---|---|---|---|---|---|
| bt-proxy-1 | 97 | 54 | 8 | 16 | 19 | 56 % | 31 % |
| bt-proxy-2 | 97 | 59 | 10 | 12 | 16 | 61 % | 37 % |
| bt-proxy-3 | 86 | 32 | 6 | 10 | 38 | 37 % | 25 % |

- Vellykkede pr. minut steg mindre end andelen (bt-proxy-1 1,55 → 1,8, -2 1,65 → 1,97, -3 0,85 →
  1,07), fordi hver anmodning nu tager længere tid, og der derfor er færre af dem.
- Linket blev tabt 44, 51 og 42 gange, men kun 8, 10 og 6 anmodninger endte med det: resten blev
  reddet af et nyt forsøg i samme anmodning.
- "Not found" er nu den største fejl på bt-proxy-3 (38 af 54 fejl, næsten alle efter ét forsøg).
  Det er anmodninger om en termostat, BlueZ på den Pi ikke kender i øjeblikket. Ikke undersøgt.
- Sammenligningen er ikke ren: før-vinduet er 40 min og talt af danfoss-eco-ha, danfoss_eco skiftede
  version imellem, og bt-proxy-3 blev drejet kl. 21:05.
- Lukningen af ubrugte links (`.9`) ses nu i drift: 4 gange på bt-proxy-1 og 1 på bt-proxy-3 i
  vinduet. HA efterlader altså stadig links uden at lukke dem.

## "Not found": vent på annoncering (`v1.0.3-benjagit.11`, bestilt af danfoss-eco-ha 20/11)

"device … not found" betyder, at BlueZ ikke har enheden lige nu. BlueZ smider en ikke-parret enhed
30 s efter sidste rapport (`TemporaryTimeout = 30`, standard, står udkommenteret i main.conf på
alle tre), og controlleren rapporterer kun en kendt annoncør nu og da (målt 1–6 rapporter pr.
termostat pr. minut). Det rammer derfor også stærke termostater: stue karnap på −60 dBm fik 10
"not found" og 7 vellykkede på bt-proxy-3 kl. 21:50–22:20.

`.11` venter op til 12 s (`ADVERT_WAIT_MAX`) på næste annoncering inden for anmodningens budget og
forbinder så. Kommer den ikke, fejler anmodningen med "did not advertise within N s". Journalen
viser ventetiden: `<MAC> advertised after X s, connecting`. På bt-proxy-3 kører scanneren under
ventetiden, så scan-pausen er ikke længere ubrudt.

Ikke prøvet: at hæve `TemporaryTimeout` i main.conf, så BlueZ beholder enhederne længere.

Deployet 20/11 kl. 22:30:43, 22:31:06 og 22:31:30 sammen med rettelsen af dobbelt disconnect (se
`haengende-forbindelser.md`).

Målt fra hubben 22:33–23:03, pr. anmodning:

| Pi | Anmodninger | Ok | Tabt link | Timeout 30 s | Not found | Ok-andel | `.10` | Før `.10` |
|---|---|---|---|---|---|---|---|---|
| bt-proxy-1 | 77 | 50 | 17 | 9 | 1 | 65 % | 56 % | 31 % |
| bt-proxy-2 | 74 | 54 | 14 | 6 | 0 | 73 % | 61 % | 37 % |
| bt-proxy-3 | 57 | 44 | 8 | 5 | 0 | 77 % | 37 % | 25 % |

- "Not found" er væk som fejl: 18 gange kendte BlueZ ikke enheden (10, 1 og 7), 17 gange kom
  annonceringen inden for ventetiden (median 3,9 s, længst 10,0 s), én gang ikke.
- Ingen efterladte links: 0 "Closing … unused" og 0 "No free connection slots" på alle tre (mod 5
  lukninger i det forrige vindue).
- Vellykkede pr. minut: bt-proxy-3 steg fra 1,07 til 1,48; bt-proxy-1 og -2 faldt lidt (1,8 → 1,68
  og 1,97 → 1,81), fordi der kom færre anmodninger (77, 74 og 57 mod 97, 97 og 86). Om det skyldes
  ændringer på HA-siden i samme tidsrum, ved jeg ikke.
- "Tabt link" er nu den største fejl (17, 14 og 8): anmodninger, hvor linket blev tabt flere gange,
  til budgettet var brugt.

## Forsøg i drift fra 20/11-2026 kl. 15:46

Benjamin sagde ja til forsøg 1, 2 og 4, ét pr. Pi. Alle ændringer er lavet med overlay slået
TIL, så de ligger kun i RAM: **en genstart af Pi'en ruller forsøget tilbage af sig selv.** Den
ugentlige opdatering genstarter kun, hvis der er pakker at opdatere: bt-proxy-1 mandag 23/11
kl. 04, bt-proxy-2 tirsdag 24/11, bt-proxy-3 onsdag 25/11. Tjek efter de tidspunkter, om
forsøget stadig kører, før tallene bruges.

| Pi | Forsøg | Startet | Ændring | Backup |
|---|---|---|---|---|
| bt-proxy-1 (kontor) | 1: GATT-cache for alle enheder | 15:45:33 | `/etc/bluetooth/main.conf`: begge linjer `Cache = yes` → `Cache = always`; bluetooth og bt-proxy genstartet | `/etc/bluetooth/main.conf.bak-20261120-forsoeg` |
| bt-proxy-2 (gildesal) | 2: forbindelsesinterval 7,5–15 ms, supervision timeout 2 s | 15:45:59 | `/etc/bluetooth/main.conf` under `[LE]`: `MinConnectionInterval=6`, `MaxConnectionInterval=12`, `ConnectionSupervisionTimeout=200`; bluetooth og bt-proxy genstartet. Kernen viser 6/12/200 (før 24/40/42) | `/etc/bluetooth/main.conf.bak-20261120-forsoeg` |
| bt-proxy-3 (stue) | 4: scanneren stoppes under connect | 15:46:26 | `/opt/bt-proxy` på tag `v1.0.3-benjagit.8` (før `.7`, ingen `uv sync`, så afhængighederne er uændrede); ny fil `/etc/systemd/system/bt-proxy.service.d/10-pause-scan.conf` med `Environment=BT_PROXY_PAUSE_SCAN_ON_CONNECT=1`; bt-proxy genstartet | ingen fil ændret; `.7` er stadig i git |

**Fra 20/11 kl. 22:55 er `v1.0.3-benjagit.11` permanent på alle tre** (nedre lag, se
`haengende-forbindelser.md`). De tre forsøg er stadig kun i RAM: efter en genstart kører en Pi `.11`
uden sit forsøg (bt-proxy-1 `Cache = yes`, bt-proxy-2 standardinterval, bt-proxy-3 uden scan-pause).

`v1.0.3-benjagit.8` (commit b10ca44, pushet til BenjaGit) tilføjer kun flaget
`--pause-scan-on-connect` / `BT_PROXY_PAUSE_SCAN_ON_CONNECT=1`. Uden flaget opfører den sig
som `.7`. bt-proxy-1 og -2 kører stadig `.7`, og setup-pi.sh's standard-tag er stadig `.7`.

Verificeret 20/11 kl. 15:59 fra hubben: alle tre tjenester er aktive og forbinder. Efter
ændringen: bt-proxy-1 3 vellykkede af 8 forsøg, bt-proxy-2 2 af 7, bt-proxy-3 1 af 8. Ingen
"wedged" eller "did not resume". Tallene er for få til at sige noget om effekten.

Fra 20/11 kl. 20:47–20:50 kører alle tre `v1.0.3-benjagit.9` (lukker ubrugte links, se
`haengende-forbindelser.md`). Forsøgene er uændrede; rollback på bt-proxy-3 skal derfor gå til
`.9`, ikke `.7`, hvis kun scan-pausen skal væk.

### bt-proxy-3 drejet 20/11 kl. ca. 21:05

Pi'en i stuen vendte USB-stikkene mod stue vest-radiatoren, som sad i luftlinjen til termostaten.
Antennen på 3B+ sidder i hjørnet ved GPIO-stikkets ende og er svagest hen over printet mod USB- og
netværksstikkene. Benjamin drejede den, så antennehjørnet vender mod radiatoren. Samme plads, samme
højde.

Signal målt på Pi'en i 60 s før og efter (BlueZ, 1–6 målinger pr. termostat, så under ca. 5 dB er
støj):

| Radiator | MAC | Før 21:03 | Efter 21:09 |
|---|---|---|---|
| Stue vest | `…95:32:CF` | −77 | −61 |
| Gang | `…0F:09:A2` | −85 | −76 |
| Soveværelse | `…6A:BA:29` | −90 | −83 |
| Kontor 1 | `…B2:AB:A2` | −91 | −84 |
| Makerspace | `…0F:13:1D` | −73 | −72 |
| Stue karnap | `…6A:BA:A4` | −60 | −62 |
| Spisestue | `…95:32:9E` | −67 | −72 |
| Gildesal vest midt | `…CF:04:D0` | −94 | ikke hørt |
| Garderobe | `…0F:09:E3` | ikke hørt | −79 |
| Gildesal vest syd | `…B2:77:06` | ikke hørt | −82 |
| Køkken | `…95:84:AF` | ikke hørt | −82 |
| Gæsteværelse | `…0F:13:1A` | ikke hørt | −89 |
| Kontor 2 | `…95:76:85` | ikke hørt | −89 |

"Ikke hørt" i før-målingen kan også skyldes, at termostaten var midt i en forbindelse. Om det
giver flere vellykkede forbindelser til stue vest (12 % i baseline-ugen), er ikke målt endnu.

Mål igen (proxyen logger ikke RSSI, så det læses fra BlueZ):

```
ssh bt-proxy-3 '(sleep 60 | timeout 65 bluetoothctl) | grep -oE "00:04:2F:[0-9A-F:]{8} RSSI: 0x[0-9a-f]+ \(-[0-9]+\)"'
```

### VIGTIGT før parring via bt-proxy-1

**Sæt `Cache` tilbage til `yes` på bt-proxy-1, før en termostat parres gennem den** (rollback
nedenfor). Med `Cache = always` giver BlueZ HA en gemt GATT-tabel uden nøglekarakteristikken
(1002000b-…), som kun findes, mens knappen er trykket. Parringen fejler så med "button not
pressed", også når knappen er trykket (set 18/10, se danfoss-eco-trv.md i HA-repoets memory).

### Rollback

Nemmest for alle tre: `sudo reboot` (overlay smider ændringerne væk). Uden genstart:

- **bt-proxy-1:**
  `sudo cp -p /etc/bluetooth/main.conf.bak-20261120-forsoeg /etc/bluetooth/main.conf && sudo rm -f /var/lib/bluetooth/*/cache/00:04:2F:* && sudo systemctl restart bluetooth && sleep 3 && sudo systemctl restart bt-proxy`
- **bt-proxy-2:** samme `cp` og genstart af tjenesterne, men kernen beholder 6/12/200, til
  Pi'en genstartes (set 19/10). Brug derfor `sudo reboot`.
- **bt-proxy-3:**
  `sudo rm /etc/systemd/system/bt-proxy.service.d/10-pause-scan.conf && sudo systemctl daemon-reload && git -C /opt/bt-proxy checkout -q v1.0.3-benjagit.7 && sudo systemctl restart bt-proxy`

### Hvad der skal ses i målingen

- **bt-proxy-1:** median-varigheden for vellykkede connects skal falde fra ca. 12 s til under
  9 s. Sker det ikke, springer BlueZ ikke opdagelsen over, og forsøget kan stoppes.
- **bt-proxy-2:** samme varighed, plus andelen "dropped the link" (baseline 36 %).
- **bt-proxy-3:** andelen "dropped the link" (baseline 34 %). Hold øje med `bluetoothd is
  wedged` og "BLE scanner did not resume" i journalen; upstream advarer om, at start og stop af
  scanneren kan få bluetoothd til at hænge. Opstartslinjen "Experiment: the BLE scanner is
  paused while connecting" viser, at flaget er slået til.

### Gør et forsøg permanent

Ændringerne skal ind i `deploy/setup-pi.sh` (main.conf-trinnet, hhv. standard-tag og flaget i
ExecStart) og rulles ud med overlay fra → setup-pi.sh → overlay til. Ikke gjort.

## Konklusion

- Success-raten er 20–25 % på alle tre Pi'er og har været det siden 10/11 kl. ca. 17. Før det
  var den 30–32 %. Der er intet knæk omkring 14/11.
- Et vellykket connect tager typisk 12 s (median 12,2 s, 75 % over 10,6 s) mod en grænse på
  15 s. Tiden går med at vente på to annonceringer fra termostaten (den annoncerer ca. hvert
  4. s) og derefter ca. 5,5 s service-opdagelse. Der er altså næsten ingen luft: mistes én
  annoncering, ender forsøget som timeout.
- En tredjedel af alle timeouts (ca. 12 % af alle forsøg) havde et link oppe, da de 15 s løb
  ud. De blev afbrudt midt i service-opdagelsen og ville være lykkedes med et kortere forløb.
- "Dropped the link" (30–36 %) kommer oftest 7 eller 11 s inde, dvs. lige når linket
  oprettes. Der er da under 10 s tilbage, så forkens genforsøg inden for samme forespørgsel
  bliver aldrig brugt.
- Derfor er den største gevinst i vores ende at gøre selve forbindelsen kortere (forsøg 1 og
  2). Det giver både færre timeouts og plads til et genforsøg efter et tabt link.

## (a) Målt success-rate pr. Pi

Kilde: Pi-journalerne i observability-hubben (VictoriaLogs, `_HOSTNAME:bt-proxy-N`), 16.928
forsøg fra 7/11 til 20/11 kl. 15. Hvert "Connecting to" er parret med sit udfald, og dubletter
fra journal-upload er fjernet.

| Periode | Pi | Forsøg | Lykkedes | Tabt link | Timeout 15 s | Ikke fundet |
|---|---|---|---|---|---|---|
| 7/11 – 10/11 kl. 17 | bt-proxy-1 | 1659 | 30 % | 46 % | 21 % | 3 % |
| | bt-proxy-2 | 702 | 32 % | 45 % | 21 % | 3 % |
| | bt-proxy-3 | 721 | 31 % | 43 % | 22 % | 4 % |
| 10/11 kl. 17 – 13/11 | bt-proxy-1 | 1880 | 22 % | 35 % | 36 % | 5 % |
| | bt-proxy-2 | 1547 | 23 % | 38 % | 34 % | 5 % |
| | bt-proxy-3 | 1104 | 21 % | 31 % | 39 % | 9 % |
| 14/11 – 20/11 | bt-proxy-1 | 3941 | 25 % | 30 % | 39 % | 6 % |
| | bt-proxy-2 | 2919 | 22 % | 36 % | 37 % | 5 % |
| | bt-proxy-3 | 2455 | 20 % | 34 % | 37 % | 8 % |

**Før og efter WiFi-skiftet kan ikke måles.** Hubben har først logs fra 7/11, og ifølge
HA-repoets memory kom Pi'erne på indbygget 5 GHz WiFi allerede 19/10 (bt-proxy-1) og 24/10
(bt-proxy-2 og -3). Det, der kan ses omkring 14/11, er at HA's API-forbindelse til proxyerne
blev stabil igen (130–345 genforbindelser pr. døgn 11/11–14/11, under 10 derefter). Det
ændrede ikke success-raten (22 % → 23 %).

Det eneste datapunkt om WiFi-sameksistens er fra 19/10: bt-proxy-1 havde 71 % tabte links
(0x3E) på kabel med WiFi slået fra. Problemet fandtes altså også uden WiFi.

### Knækket 10/11

Mellem kl. 16 og 20 den 10/11 steg timeouts fra ca. 21 % til ca. 36 % på alle tre Pi'er
samtidig, og vellykkede connects blev ca. 1 s langsommere (andel på 13–14 s: 12 % → 25 %).
Andelen af forsøg, hvor der slet ikke kom et link på 15 s, gik fra ca. 11 % til ca. 24 %.

Samme eftermiddag: HA flyttede til 192.168.80.40 (første forbindelse derfra 16:30),
Pi'erne kom på 192.168.41.x, setup-pi.sh blev kørt igen på alle tre (bt-proxy genstartet
17:28–17:31), og journal-videresenderen kom på (commit 17:47). Kernen skiftede ikke den dag
(6.18.50 ved alle opstarter fra 9/11). Jeg har ikke fundet årsagen. Den billigste test er at
stoppe `systemd-journal-upload` og `bt-proxy-journal-forward` på én Pi i et døgn og se, om
timeout-andelen falder; journalen bliver liggende i RAM og sendes bagefter.

### Hvad Pi'erne viser nu (20/11 kl. 15:20, kun læst)

- Alle tre: Coldberg_IoT5 på 5 GHz (kanal 100, 40 og 56), −40/−54/−60 dBm, strømspare fra,
  `throttled=0x0`, ingen hængende BLE-links, kerne 6.18.50, BlueZ 5.82, v1.0.3-benjagit.7.
- BlueZ-standarder er i brug: forbindelsesinterval 30–50 ms, supervision timeout 420 ms,
  `[GATT] Cache = yes` (kun bundne enheder, så termostaterne opdages forfra hver gang).
- BlueZ sender 90–120 D-Bus-signaler i sekundet. dbus-daemon, NetworkManager, bluetoothd og
  bt-proxy bruger hver ca. 10 % af en kerne. Der er 4 kerner, så det er ikke en flaskehals.
- wlan0 sender 12–14 kB/s (annonceringer til HA).

### Andre mønstre i loggen

- Forskellen ligger mest i termostaten og afstanden, ikke i Pi'en. Bedste par: kontor 2 via
  bt-proxy-1 45 %, gildesal nord via bt-proxy-2 44 %. Dårligste: stue vest 12 %, køkken 9 %,
  soveværelse 13 %, trappeopgang 4 % (0,3 aflæsninger pr. døgn).
- 30 % af forsøgene går gennem en proxy, der ikke er termostatens bedste. De lykkes 8 % af
  gangene mod 29 % via den bedste. Valget af proxy sker i HA.
- Tidspunkt på døgnet betyder intet (21–29 % i alle timer). Der er aldrig to connects ad
  gangen på samme proxy.
- Kontor 2, 1 m fra bt-proxy-1: 45 % lykkes, 18 % tabt link, 32 % timeout. Selv ved kort
  afstand rammer timeout-grænsen altså hvert tredje forsøg.
- "Failed to acquire MTU … StopIteration" kommer ved hvert eneste vellykkede connect og er
  kosmetisk (MTU bliver 23).

## (b) Forslag, rangeret efter forventet effekt

Alle forsøg måles på samme måde: success-rate og varighed pr. Pi pr. døgn fra hubben, mod
Pi'ens egne tal for 14/11–20/11 og mod en urørt Pi som kontrol. 2–3 døgn giver 800–1500
forsøg pr. Pi.

```
_HOSTNAME:~"bt-proxy-[123]" ("Connecting to" OR "Connected to" OR "Failed to connect")
| extract_regexp "(?P<ev>Connecting to|Connected to|Failed to connect)"
| stats by (_time:1d, _HOSTNAME, ev) count_uniq(_msg) n
```

### 1. GATT-cache for alle enheder (`[GATT] Cache = always`)

- **Hvorfor:** sparer de ca. 5,5 s service-opdagelse ved hvert connect efter det første.
- **Forventet effekt:** stor. De ca. 12 % af forsøgene, der i dag afbrydes midt i opdagelsen,
  bliver til succes, og et vellykket connect falder fra ca. 12 s til ca. 7–8 s. Skøn: 23 % →
  ca. 35 %.
- **Risiko:** kendt fra 18/10: under parring gav cachen HA en gammel tabel uden
  nøglekarakteristikken. Alle 18 er parret, så det rammer kun ny parring; da skal cachen for
  den MAC slettes først, eller indstillingen sættes tilbage. Under overlay ligger cachen i RAM.
  Usikkert: at BlueZ 5.82 faktisk springer opdagelsen over for ubundne enheder. Fejlen 18/10
  tyder på det, men det er ikke målt.
- **Test på én Pi:** bt-proxy-1. Ret main.conf og genstart bluetooth og bt-proxy. Uden at slå
  overlay fra forsvinder ændringen ved næste genstart (mandag kl. 04), hvilket passer til et
  forsøg.
- **Måling:** median-varigheden for vellykkede connects skal falde fra ca. 12 s til under 9 s
  inden for de første timer. Sker det ikke, virker cachen ikke, og forsøget stoppes.

### 2. Kortere forbindelsesinterval og længere supervision timeout

- **Hvorfor:** opdagelsen er ca. 110 rundture, og hver koster ét interval (30–50 ms i dag).
  Med 7,5–15 ms bør den tage under 2 s. Supervision timeout på 420 ms betyder, at et link
  dør efter under et halvt sekunds forstyrrelse; telefonen bruger 5 s.
- **Forventet effekt:** mellem til stor, samme mekanisme som 1 uden cache-risikoen. Forsøget
  19/10 (interval 15–18,75 ms, timeout 5 s) blev dømt ude på 9 forsøg og målte ikke
  varigheden; nu kan det måles på over 1000.
- **Risiko:** lav. Termostaten er vågen i kortere tid pr. aflæsning. Værdierne hænger i
  kernen til genstart.
- **Test på én Pi:** bt-proxy-2. `[LE] MinConnectionInterval=6`, `MaxConnectionInterval=12`,
  `ConnectionSupervisionTimeout=200` i main.conf, genstart bluetooth og bt-proxy.
- **Måling:** varighed som i 1, plus andelen "dropped the link".

### 3. Ændringer i forken (kræver 1 eller 2 for fuld effekt)

- **a. Genforsøg efter tabt link:** `DROP_RETRY_MIN_REMAINING` er 10 s, fordi et forsøg i
  dag kræver så meget. De fleste links tabes 7 s inde, så genforsøget sker aldrig. Med kort
  opdagelse kan grænsen sænkes til ca. 6 s.
- **b. "Not found":** 6 % af forsøgene (22 % af dem, der starter under 1 s efter en fejl)
  fejler på 0,0 s, fordi BlueZ har glemt enheden. Vent i stedet på næste annoncering (højst
  ca. 5 s) inden for samme budget.
- **c. Log RSSI, annonceringens alder og tidspunkt for link-op ved hvert connect.** Så kan
  alle forsøg måles uden btmon, og vi kan se, om svagt signal forudsiger fejl.
- **d. Lad være med at genstarte scanneren,** når HA beder om passiv scanning, som alligevel
  falder tilbage til aktiv (10–50 genstarter pr. døgn pr. Pi).
- **Forventet effekt:** a +5–10 procentpoint oven på 1 eller 2; b +3–5; c og d ingen eller
  lille direkte effekt.
- **Risiko:** lav; a og b er dækket af de eksisterende tests' mønster. En ny tag skal ud med
  overlay fra og til.
- **Test på én Pi:** check grenen ud på bt-proxy-1 som 19/10, før tag.

### 4. Stop scanning, mens der forbindes (hypotese 1)

- **Hvorfor:** aktiv scanning kører med fuld sendetid på den samme radio og genoptages i det
  øjeblik, linket er oprettet, hvor de første 6 forbindelsesintervaller afgør, om linket
  overlever (0x3E).
- **Forventet effekt:** ukendt. Det er det eneste forslag, der sigter direkte på de 30–36 %
  tabte links.
- **Risiko:** mellem. Upstreams kode advarer om, at start og stop af scanneren pr. connect
  fik bluetoothd til at hænge. HA får ingen annonceringer fra den Pi i op til 15 s pr.
  connect, hvilket er langt under HA's grænse på 195 s.
- **Test på én Pi:** bt-proxy-3, bag et flag i forken, så det kan slås fra uden ny tag.
- **Måling:** andelen "dropped the link" mod kontrol, og `bluetoothd is wedged` i journalen.
  Suppler med en btmon-optagelse (som 19/10), der skiller 0x3E fra links tabt under
  opdagelsen.

### 5. Hardware (hypotese 5)

- **USB-Bluetooth-dongle på én Pi** (`DONGLE=1` findes i setup-pi.sh). Tegn på, at
  controlleren betyder noget: NUC'ens Intel-adapter havde 25 af 40 vellykkede 18/10, mens
  Pi'en havde 8 af 53. Det var få forsøg og før forkens rettelser.
- **ESP32 med ESPHome Bluetooth-proxy** ved siden af bt-proxy-1 som sammenligning.
- **Forventet effekt:** ukendt, muligvis stor for tabte links. Vent til 1–4 er målt, så det
  er tydeligt, hvor meget der er tilbage til radioen.
- **Risiko:** lav. Koster hardware og en genstart.
- **Måling:** samme tal for de termostater, den Pi betjener bedst.

### Ikke anbefalet nu

- **WiFi-sameksistens (hypotese 2):** alle tre er på 5 GHz med godt signal, og fejlen fandtes
  på kabel. Kan kun afgøres ved at sætte én Pi på kabel i et par døgn.
- **Længere `CONNECT_TIMEOUT` (hypotese 4):** bundet af HA's 20 s.

## Til HA-siden

- 30 % af forsøgene går via en proxy med ca. 8 % chance. Hvis valget kan styres mod den
  bedste proxy, er det en gevinst uden ændringer her.
- Trappeopgang (6A:A5:9A) lykkes 4 % af gangene og aflæses ca. hver tredje dag; køkken
  (95:84:AF) 9 %. De ligner dækningsproblemer mere end proxy-problemer.
