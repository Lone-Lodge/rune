# rune

Innehallsadresserad lagring for stora binarer. En fil lagras som ett recept:
listan av chunkar den bestar av.

Chunkgransen valjs av innehallet via en rullande hash, inte av en fast
storlek. Det ar hela poangen. Andras en byte mitt i en 200 MB `.uasset`
flyttas inte alla efterfoljande granser, sa bara den chunken ar ny.
Helfilshashning (git-LFS) skulle lagra 200 MB igen.

Matt pa en 8 MB-fil, 128 chunkar:

| andring                  | nya chunkar |
|--------------------------|-------------|
| en byte mitt i filen     | 1           |
| 1000 bytes INSKJUTNA     | 1           |

Den andra raden ar den som betyder nagot. En inskjutning flyttar varje
efterfoljande grans i en fastblocksmodell och skulle ge ~64 nya chunkar.
CDC re-synkroniserar.

## Objekten

```
chunk      innehall -> sha256. Variabel storlek.
blob       en fils recept: chunk-id, ett per rad.
manifest   en ogonblicksbild: "sokvag<TAB>blob-id", sorterad pa sokvag.
commit     foralder, manifest-id, forfattare, tid, meddelande.
```

Allt bor pa `.rune/<sort>/ab/cdef...`, tva hex som mapp sa en katalog aldrig
far hundratusen poster.

## Kon och ogonblicksbilden

Kon (`.rune/index`) ar **det som andrats sedan sist**, och den toms efter
varje commit. Ogonblicksbilden ar HEAD plus kon, inte kon i sig. Darfor
kan man koa en enda fil och committa utan att resten av tradet forsvinner
ur historien - vilket ar precis vad som hande innan, och en clone hade da
fatt ett trad utan dem.

En BORTTAGNING maste darfor sagas rakt ut, for tystnad om en fil betyder
oror. `rune add .` ser det: allt som fanns i HEAD men inte langre pa
disken koas som borttaget, markt med "-" i kon. `rune add <fil>` gor det
inte, den ror bara den sokvag du namner.

## Komprimering

Ingen. Medvetet. Chunk-id ar hashen av det **okomprimerade** innehallet,
sa komprimering kan laggas till senare som en ren lagringstransform utan
att ett enda id andras eller ett befintligt repo blir ogiltigt.

## Frusna parametrar

`chunk_min` 16 KB, `chunk_norm` 64 KB, `chunk_max` 256 KB, maskerna, och
gear-tabellens fro. De ar en del av FORMATET, inte installningar. Andras
nagot av dem flyttas varje grans och all dedup mot befintliga repon
forsvinner.

## Kor

    orbit build
    bash tools/test.sh          # hela flodet mot ett engangsrepo
    bash tools/remote_test.sh   # server + tva klienter

    rune init                   # starta ett repo har
    rune add .                  # koa hela tradet
    rune status                 # koat / nytt / andrat / borttaget
    rune commit "meddelande"
    rune log
    rune history <fil>          # filens versioner, nyast forst
    rune show <commit> <fil> <ut>   # innehallet vid en commit, till en fil
    rune checkout <commit>      # skriv ut en ogonblicksbild
    rune lock <sokvag>          # ta filen, ingen annan far koa den
    rune unlock <sokvag>        # slapp den
    rune locks                  # vem haller vad
    rune stat <fil>             # visa chunkningen utan att lagra
    rune fsck                   # las varje objekt och jamfor med dess id

Ett commit-id far forkortas sa langt det ar entydigt, alltsa de tolv
tecken `rune log` visar. Ar prefixet tvetydigt sager rune det i stallet
for att gissa.

## Bredvid git

`rune init` lagger `.rune/` i `.gitignore` om mappen redan har en git.
Utan det dyker lagret upp som ospardat bredvid ditt riktiga arbete. Raden
laggs bara om den saknas; vi skriver aldrig om nagons fil mer an sa.

## .runeignore

En rad per monster, prefixmatchning pa den relativa sokvagen. `Saved/` tar
allt darunder. Inga globbar. For ett Unreal-projekt racker:

    Saved/
    Intermediate/
    DerivedDataCache/
    Binaries/
    .vs/

## Las

En `.uasset` gar inte att sla ihop. Da ar las enda arbetssattet: den som ska
andra en fil tar den forst, alla andra ser att den ar tagen.

    rune lock Content/Karaktar.uasset
    rune locks
    rune unlock Content/Karaktar.uasset

Laset ar **sparret, inte en varning**: `add` vagrar koa en sokvag nagon
annan haller, sa den kan inte ta sig in i en commit. Kontrollen bor i `add`
och inte i CLI:t, annars gar den att ga runt genom att anropa lagret direkt.
Man tar inte heller nagon annans las ifran dem - `unlock` vagrar.

    .rune/locks    "sokvag<TAB>agare<TAB>unixtid", en per rad, sorterad

Sa lange det inte finns nagon remote ar lasen lokala. Formatet ar det som
ska synkas och sparret det som maste finnas fore en remote, sa det ar den
ordningen.

### Skyddet pa disk

En last fil markeras **skrivskyddad i filsystemet** hos alla utom den som
haller den. Sparret i `add` kommer forst nar jobbet redan ar gjort; det har
sager ifran i programmet man faktiskt ritar i, innan man borjar. Det
fungerar oavsett vilket program det ar - Photoshop, Blender, vad som helst
som sparar en fil.

Skyddet foljer tabellen och satts om varje gang den andras: nar ett las tas
eller slapps, nar `add` synkar med servern, och efter en `pull` som skrivit
om tradet. Slapps ett las far filen tillbaka sin skrivratt.

Skrivningarna i rune tar sjalva bort skyddet forst, sa en `pull` eller
`checkout` kan skriva over en fil som ar skyddad utan att tyst misslyckas.

## Remote

Hela synken ar en fraga: **vilka id saknar du?** Det ar innehallsadresseringens
utdelning. Ingen jamforelse av trad, inga deltan, ingen forhandling.

    rune secret <varde>         # den delade hemligheten for det har repot
    rune serve 7420             # pa maskinen som haller repot
    rune clone <url> <hemlighet>    # init + remote + hemlighet + pull i ett
    rune push                   # skickar det servern saknar
    rune pull                   # hamtar det du saknar OCH skriver arbetstradet

Matt: 3 MB binar andrad pa **en byte** kostar 4 objekt over natet - en chunk,
dess blob, manifestet och commiten.

## Egen klient, inte curl

Klienten talar HTTP sjalv over net-orben, precis som servern gor. Skalet
ar matt: http-orben startar en curl-PROCESS per request, och en push av
30 MB ar 553 objekt.

    push 30 MB     25,0 s  ->  5,8 s
    clone 30 MB                6,5 s

En https-adress gar fortfarande till http-orben, som har curl och darmed
TLS. Rune:s egen server talar inte TLS, sa den vagen finns bara for den
som satt en proxy framfor.

Det som ar kvar ar UPPKOPPLINGEN: servern ger ett svar per uppkoppling,
sa en push oppnar 553 stycken, ungefar tio millisekunder var. Keep-alive
skulle ta bort det, men det ar en verklig andring av vem som ager en
uppkoppling och inte en justering.

Egen HTTP pa net-orben, inte app-orben: app splittar requesten pa `

`
och tar andra biten som kropp, sa en binar kropp som rakar innehalla den
sekvensen kapas. Chunkar ur .uasset-filer gor det forr eller senare.

`pull` gor bada halvorna: hamtar objekten, flyttar HEAD och skriver
arbetstradet dit. Forut gjorde den bara den forsta, sa du fick klistra in
ett 64 tecken langt id i `checkout` efterat.

Darfor **vagrar den nar du har nagot okommitterat**, och kontrollen
ligger fore hamtningen sa ett nej inte lamnar halva servern nedladdad.
`checkout` skriver bara filer och tar aldrig bort nagot - den flyttar
inte heller HEAD, sa den ar till for att TITTA pa ett gammalt lage, inte
for att sta i det.

**Bara snabbspolning.** Push vagrar om serverns commit inte ligger i din
kedja, pull vagrar om du har egna commits vid sidan av. Binarer gar anda
inte att sla ihop - det ar darfor lasen finns.

## Hemligheten

Servern kraver en delad hemlighet och vagrar starta utan en. Den bor i
`.rune/secret`, alltsa i mappen git redan haller utanfor, och gar over
natet som ett `Authorization`-huvud - aldrig i sokvagen, for en URL hamnar
i loggar och i kommandoradshistorik. http-orben skickar huvuden genom en
konfigfil, sa den syns inte heller for den som listar processer.

Hemligheten ar en **dorrnyckel, inte en identitet**. Den sager att du far
tala med servern, inte VEM du ar. Lasen bar fortfarande ett namn som
klienten sjalv anger, sa den som har nyckeln kan ange vilket namn som
helst. Det racker for ett lag som redan litar pa varandra. Det racker inte
mot oppna natet, och det ar inte heller krypterat - en avlyssnare pa
vagen ser bade hemligheten och innehallet. Bakom brandvagg eller VPN, med
andra ord, men nu med en dorr i stallet for ett halt i vaggen.

Med en remote satt ar **servern sanningen om lasen**. Ett las som bara finns
lokalt kan aldrig saga att nagon ANNAN haller filen, och da ar det ingen
sparr utan en anteckning. Den lokala lasfilen blir en cache som `add` far
sin sparr ur.

## Lasa och skriva utan att kanna lagret

Med bara `/obj/<sort>/<id>` maste en lasare kanna hela objektmodellen -
commit, manifest, blob, chunkar - for att komma at en enda fil. Tre
endpoints till racker for att nagon annans program ska slippa det:

    GET /tree?at=<commit>                    sokvag<TAB>blob, en per rad
    GET /hist?path=<sokvag>                  filens versioner, nyast forst
    GET /file?path=<sokvag>&at=&from=&to=    bytes

`at` far vara ett forkortat commit-id, eller utelamnas for HEAD. `from`
och `to` utelamnade betyder hela filen. En sokvag som inte fanns i den
commiten ger 404, sa "fanns inte" gar att skilja fran "ar tom".

**Innehallsadressering ger slumpvis lasning gratis.** Objekten ar
okomprimerade, sa en chunkfils STORLEK ar chunkens langd. Ett recept plus
en storleksfraga per chunk sager alltsa var varje chunk borjar, och da
oppnas bara de chunkar som tacker intervallet. Ingen seek, ingen
genomlasning.

Matt pa en 100 MB-binar over HTTP (klientens curl-uppstart ar ~140 ms av
varje rad):

    16 bytes ur borjan     151 ms
    16 bytes ur mitten     276 ms
    16 bytes ur slutet     347 ms
    hela filen            1825 ms

Kostnaden foljer alltsa hur langt in i RECEPTET man laser, inte hur stor
filen ar, och det som vaxer ar storleksfragor - inte lasningar.

Servern har aldrig skrivit ut nagon fil till sin egen arbetsyta. Den
svarar ur objekten, och det ar det som gor rune till ett lager under
nagon annans program i stallet for ett verktyg bredvid det.

### Skriva

    POST /file?path=<sokvag>&who=<namn>&msg=<text>    kroppen ar innehallet

**Ett innehall in, en commit ut.** Ingen ko ar inblandad, och det ar
avsiktligt: kon ar en delad fil, och en server som stagar at en klient
hade lagt nagon annans halvfardiga arbete i din commit.

Ar innehallet redan det HEAD har blir det ingen commit - en redigerare som
sparar utan att ha andrat nagot ska inte fylla historien. Svaret ar
commit-id:t i bada fallen.

Lassparren ligger i lagret och inte i den som svarar pa requesten, precis
som for `add`. Haller nagon annan sokvagen svarar servern 409 med vem det
ar. `who` ar samma sjalvangivna namn som lasen bar: hemligheten ar en
dorrnyckel, inte en identitet.

Kroppen lases som exakt Content-Length bytes, sa en binar som rakar
innehalla `\r\n\r\n` overlever. Sviten skriver en 300 kB-binar med
den sekvensen i sig och laser tillbaka den byte for byte.

### Servern haller inte kroppen i minnet

En skrivning gar rakt till disk medan den tas emot, och ett filsvar
skickas ut bit for bit. Ingen av dem bygger nagot helt i minnet, och det
ar inte finlir: Orion lamnar inte tillbaka det ett varv allokerar, sa en
server som bygger kroppar i minnet vaxer tills den dor.

    20 MB in     7,8 s och 26 GB  ->  1,4 s och 66 MB
    20 MB ut     +378 MB          ->  +23 MB
    120 MB in och 100 MB ut           182 MB totalt

Tre saker gjorde de 26 GB: `bytes_concat` i mottagningsslingan kopierade
allt hittills for varje block, `byte_count` byggde en byteslista bara for
att rakna langden pa varje block, och kroppen fogades ihop till en enda
text innan den chunkades. Alla tre ar borta.

## Statcachen

`status` hashade om hela arbetstradet varje gang. Nu minns `.rune/stat`
mtime och storlek per fil, och bara det som rort sig hashas om.

    57 MB, 40 filer      kall cache 1,08 s  ->  varm 0,06 s

Cachen bor i EGEN fil och inte i indexet: indexet haller bara KOADE filer,
och det ar just de okoade som ar manga och kostar tid.

**Gransen, uttalad:** andras en fil inom samma mtime-tick OCH behaller
exakt samma storlek tror cachen att den ar oforandrad. Det ar samma
kapplopning git har. Den syns nasta gang mtime rors, och `rune add <fil>`
gar alltid forbi cachen.

## Kostnad per fil

`add` gar EN vanda over listan: index och lasfil lases, sorteras och skrivs
en gang, inte en gang per fil. `status` slar upp i tabell i stallet for att
soka linjart. Bada ar linjara i antal filer nu; forut var de kvadratiska och
3200 filer tog slut pa minnet innan de blev klara.

    3200 filer      add 43 s     status kall 1,2 s   varm 0,8 s

Det som ar kvar i `add` ar disken: tva nya objekt per fil, och en ny fil pa
Windows kostar nagra millisekunder. Kor `add` en gang till pa samma trad och
den tar 0,4 s - da finns objekten redan.

**Ingen packning, och det ar ett beslut.** Att lagga manga objekt i fa
filer, som git gor, skulle ta ner de 43 sekunderna. Men kostnaden betalas
EN gang per nytt innehall: andra vandan over samma trad ar 0,4 s. Priset
vore en formatandring som ror uppslagning, `has_object`, remoteprotokollet
och ett behov av gc - alltsa nastan varje del av lagret - for att gora en
engangskostnad mindre. Det ar fel byte just nu. Om ett trad nagon gang
tar minuter att koa forsta gangen ar det da fragan ska stallas om.

## Minnet

Filer lases inte hela. Chunkningen gar genom ett FONSTER: en grans beror
bara pa bytesen fran chunkens borjan och som mest chunk_max framat, sa mer
an sa behover aldrig ligga inne. `checkout` skriver chunk for chunk rakt ut
i filen.

Fonstret racker inte i sig sjalvt. Orion har ingen skrapsamlare, sa det ett
varv allokerar ligger kvar tills processen dor, och `bytes_of` ger ett tal
per byte - atta ganger innehallet. En 256 MB-fil kostade 4,6 GB.

Darfor kor chunkningen i en ARENA (`arena`-orben) och lamnar tillbaka
varvet nar det ar klart. Det som ska leva vidare - chunk-id:na och det som
blev over av fonstret - kopieras ut med `persisted` FORE svepet. Utan den
kopian pekar raderna i receptet in i minne som nasta varv skriver over.

    256 MB     4,6 GB  ->  54 MB

Arenan slas pa forst nar filen inte rymdes i ett fonster. En liten fil har
inget varv att lamna tillbaka och betalar darfor ingenting.

## Lagrets sundhet

Namnet pa ett objekt ar hashen av dess innehall, sa den jamforelsen ar hela
sanningen om lagret.

    rune fsck       laser varje objekt och jamfor med dess namn

En skrivning som inte gick igenom **tas bort**. En full disk eller en
krasch mitt i skrivningen lamnar annars en stympad fil under ett giltigt
id, och da sager `has_object` for alltid att vi har objektet - vilket ar
varre an att sakna det. Ett saknat objekt syns, ett fel objekt gor det
inte. Gick en fil inte att lagra kommer den inte heller in i kon, for en
kopost som pekar pa ett objekt som inte finns ar en commit som inte gar
att checka ut.

## Inga grenar, och varfor

Rune har en enda ref och snabbspolar bara. Det ar ett beslut, inte en
lucka.

En gren ar bara meningsfull om den kan sla ihop sig igen, och det ar
precis det binarer inte kan. Det ar darfor lasen finns. En gren som aldrig
kan sla ihop sig ar en fork, och for det racker en till mapp.

Foljden ar att `checkout` inte flyttar HEAD. Den skriver ut en gammal
ogonblicksbild for att man ska kunna TITTA pa den. Att lata den flytta
refen bakat hade gjort de nyare commitarna onaabara och nasta push till en
icke-snabbspolning.

## Granser

Ingen kryptering over natet, sa en avlyssnare pa vagen ser bade hemligheten
och innehallet: bakom brandvagg eller VPN.

Ingen packning, inga grenar - bada uttalade beslut ovan, inte luckor.

`.runeignore` matchar pa prefix och kan inga globbar. `Saved/` fungerar,
`*.log` gor det inte.
