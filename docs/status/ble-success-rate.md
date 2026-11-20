# BLE-forbindelser til Danfoss Eco: hvorfor kun ca. 1 af 4 lykkes

Undersøgt 20/11-2026 (bestilt af homeassistant). Ingen ændringer er lavet på Pi'erne eller i koden.

## Næste skridt

1. Benjamin vælger, hvilke af forsøgene 1–4 nedenfor der skal køres. Forslag: forsøg 1 på
   bt-proxy-1 og forsøg 2 på bt-proxy-2 samtidig, med bt-proxy-3 som kontrol, i 2–3 døgn.
2. Find ud af, hvad der skete 10/11 kl. ca. 17 (se "Knækket 10/11"). Det kostede ca. 9
   procentpoint og er ikke forklaret.
3. Hardware (forsøg 5) først, når 1–4 er målt.

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
