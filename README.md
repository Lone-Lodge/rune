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

## Bygga och kora

rune ar skrivet i [Orion](https://github.com/Lone-Lodge/orion) och byggs
med dess `orbit`. Klona orion BREDVID det har repot - bygget letar efter
`../orion/dist/orbit`:

    git clone https://github.com/Lone-Lodge/orion.git

    bash tools/gate.sh          # bygg + bada sviterna, ett kommando

    orbit build
    bash tools/test.sh          # hela flodet mot ett engangsrepo
    bash tools/remote_test.sh   # server + tva klienter

Sviterna antar inte Windows: de hittar binaren med eller utan `.exe` och
kor `python3` dar den finns. De ar dock bara KORDA pa Windows.
POSIX-grenarna i `file_readonly`, `file_seek` och `mkdir_all` ar skrivna
men aldrig exekverade, och det ar skillnad pa rimligt och bevisat.

    rune init                   # starta ett repo har
    rune add .                  # koa hela tradet
    rune status                 # koat / nytt / andrat / borttaget
    rune ur <sokvag>            # ta en sokvag UR kon
    rune commit "meddelande"
    rune log
    rune diff <fil> [commit]    # rader ut och in mot HEAD, eller mot en commit
    rune history <fil>          # filens versioner, nyast forst, over namnbyten
    rune show <commit> <fil> <ut>   # innehallet vid en commit, till en fil
    rune checkout <commit>      # skriv ut en ogonblicksbild
    rune lock <sokvag>          # ta filen, ingen annan far koa den
    rune unlock <sokvag>        # slapp den
    rune locks                  # vem haller vad
    rune bryt <sokvag>          # ta ifran nagon annan deras las
    rune stat <fil>             # visa chunkningen utan att lagra
    rune fsck                   # las varje objekt och jamfor med dess id
    rune gc                     # ta bort det ingen commit nar
    rune pack                   # skriv om lagret till en enda pack

Ett commit-id far forkortas sa langt det ar entydigt, alltsa de tolv
tecken `rune log` visar. Ar prefixet tvetydigt sager rune det i stallet
for att gissa.

## Bredvid git

`rune init` lagger `.rune/` i `.gitignore` om mappen redan har en git.
Utan det dyker lagret upp som ospardat bredvid ditt riktiga arbete. Raden
laggs bara om den saknas; vi skriver aldrig om nagons fil mer an sa.

## .runeignore

En rad per monster, och SISTA monstret som traffar avgor. Ett `!` framfor
betyder "behall anda":

    Saved/                  allt darunder ut
    !Saved/viktig.uasset    utom den har

Negationen nar IN i en utesluten mapp. git gor tvartom och dokumenterar
det; har ar det viktigare att `!` betyder nagot. `.rune/` gar inte att
negera - ett lager som gar att koa in i sig sjalvt ar inget lager.

Ett monster UTAN stjarna ar ett prefix pa den relativa sokvagen:
`Saved/` tar allt darunder. Med stjarna matchas hela sokvagen,
och `*` star for vilken foljd som helst - aven tom, aven over `/`:

    *.log        varje .log var den an ligger
    Saved/*      allt under Saved

Inget annat monster. `?` och `[a-z]` har ingen bett om, och varje tecken
till ar ett tecken den som laser filen maste minnas.

For ett Unreal-projekt racker:

    Saved/
    Intermediate/
    DerivedDataCache/
    Binaries/
    .vs/

## Diff

    rune diff <fil>             mot HEAD
    rune diff <fil> <commit>    mot en aldre

BARA for text. En binar har inga meningsfulla rader, och for den ar
`history` plus `show` svaret - `diff` sager det i stallet for att jamfora
byte for byte tills nagot ser konstigt ut.

Gemensam borjan och gemensamt slut skalas bort forst, och det ar nastan
hela arbetet i en verklig andring. Pa det som blir kvar gors en riktig
LCS. Blir mitten storre an taket - 250 000 radpar - sags den vara ETT
utbytt block, och det STAR i utskriften. Ett tak som tiger blir ett fel
man inte ser.

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

    rune bryt <sokvag>          ta ifran nagon annan deras las

`unlock` vagrar med FLIT. Men en som slutat, eller en maskin som dott,
lamnar annars sitt las for alltid, och da star filen last tills nagon
redigerar lasfilen for hand. Darfor ett eget ord: det ska ga att lasa i en
terminalhistorik vad som hande.

Vem som helst med hemligheten far bryta. Hemligheten ar en dorrnyckel och
inte en identitet, sa det finns ingen grund att skilja pa vem som far -
det som finns ar att det SYNS.

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

Sedan var det uppkopplingen sjalv. Servern gav ett svar per uppkoppling,
sa en push oppnade over femhundra stycken a ungefar tio millisekunder.
Nu haller en push eller en pull EN uppkoppling hela vagen.

    push 30 MB     25,0 s  ->  5,8 s  ->  1,6 s
    clone 30 MB              6,5 s  ->  1,7 s

En https-adress gar fortfarande till http-orben, som har curl och darmed
TLS. Rune:s egen server talar inte TLS, sa den vagen finns bara for den
som satt en proxy framfor - och over den finns ingen lina, utan varje
anrop tar en egen uppkoppling som forut.

**Foljden ar att servern tar en push i taget.** Den gjorde det redan -
den svarar en uppkoppling i taget - men nu haller en push linan hela
vagen i stallet for att slappa mellan varje objekt. Den som pushar 1 GB
later alltsa nagon annan vanta. Sockeln har trettio sekunders timeout, sa
en klient som dor mitt i slapper servern igen, men det ar allt som skyddar
och det ar uttalat.

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

## Packen

Ett objekt per fil kostar bade plats och tid. En 2 KB-chunk tar 4 KB pa ett
filsystem med 4 KB-kluster, och att SKAPA en fil ar det dyra pa Windows.

    rune pack   skriver om allt nabart till EN pack och tar bort resten

    .rune/pack/<n>.pack    kropparna, en efter en
    .rune/pack/<n>.idx     "id<TAB>sort<TAB>start<TAB>lagrad<TAB>ra", en per rad

**Tva langder**: hur manga bytes kroppen tar i packen, och hur stor den ar
i sanning. Ar de lika ligger den okomprimerad.

Id:t ar fortfarande hashen av kroppen, sa en pack ar en LAGRINGSFORM och
inte ett nytt format. Samma repo kan ha bade losa objekt och packar, och
den som laser behover inte veta vilket det ar.

### Komprimering

Varje objekt provas for sig och lagras rakt av nar komprimeringen inte
vann. En .uasset-chunk VAXER av att komprimeras och ska inte betala for
det. Kompressorn ar `compress`-orben: LZ77 over ett 64 KB-fonster och en
kanonisk Huffman ovanpa. Inte zlib och inte kompatibel med det - vi
skriver och laser vara egna bytes, sa det finns inget utbytesformat att
folja.

LZ77 tar bort upprepningen; literalerna kostar fortfarande en hel byte
styck, och i text ar de kraftigt snedfordelade. Ett trad over HELA
utdatan, inte separata for literaler och langder som DEFLATE har - ett
huvud i stallet for tre, och skillnaden mellan dem ar mindre an
skillnaden mot ingen alls.

    kallkod   1,75x med bara LZ77  ->  2,15x med Huffman  (zlib: 2,8x)

    2000 filer a 2 KB, OKOMPRIMERBAR slumpdata
    losa objekt   12343 KB   (4005 filer)
    packat         4618 KB   (5 filer)
    git efter gc   4419 KB

    118 filer riktig kallkod, 2713 KB
    losa objekt    2824 KB
    packat         1078 KB
    git efter gc    819 KB

Pa slumpdata ar vi jamsides med git. Pa text ar git 1,3 gangar battre, och
den skillnaden BLIR KVAR. Det ar ett beslut, matt fram:

Varje objekt komprimeras for sig, utan delat fonster med sina grannar. Det
ligger nara till hands att tro att SOLIDA block - manga objekt i en strom -
ar den stora vinsten. Matt pa 2,4 MB riktig kallkod:

    per objekt   1046 KB
    solid         986 KB      alltsa sex procent

Sex procent, mot att varje intervallasning skulle behova packa upp ett helt
block for att na en chunk. Det ar fel byte, och intervallasningen ar en av
de fa saker rune gor som ingen annan gor.

Det som DA ar kvar av gapet mot git ar tva saker som bada ar egna projekt:
separata Huffman-trad for literaler och for langder, och deltakomprimering
mellan liknande objekt. Var chunkning gor det andra arendet for stora
binarer, men en liten textfil ar en enda chunk och har inget att deltas
mot. Priset ar ungefar 170 KB pa 2,4 MB. Det ar inte samma sorts vinst som
packningen var, och det star har i stallet for att sta pa en lista.

En trasig strom far inte krascha avkodaren. Det ar just pa trasiga bytes
`fsck` kors, sa den maste sta emot dem: ett avstand bakom stromens borjan
eller en literalfoljd utanfor den avbryter avkodningen i stallet for att
lasa ur minnet bredvid.

Packen tar bara det NABARA, sa skrap kommer aldrig in i en - det ar darfor
det inte behovs nagon gc for packar. Gamla packar och losa objekt tas bort
EFTERAT, aldrig fore: gar skrivningen fel star repot kvar som det var.

Och de tomma objektmapparna tas bort. Tva hex som mapp ger upp till 256 per
sort, och en tom mapp kostar ett kluster precis som en fil - tusen av dem
var fyra av de sju megabyte som lag kvar efter forsta packningen.

## Vad `add` kostar

`add` av 2000 sma filer tog 27 sekunder mot gits 6,5. Det matte inte rune.

Samma trad, men lasta EN gang av nagot annat forst:

    2000 filer    git 6,0 s    rune 2,6 s
    samma, nyss skapade och aldrig lasta:
                  git 6,5 s    rune 26,9 s

Rune ar alltsa **2,3 ganger snabbare an git**, och de 27 sekunderna var
Windows Defender som skannar varje nyskapad fil forsta gangen den oppnas.
git rors knappt av det - `git.exe` ar en kand signerad binar, medan
`rune_cli.exe` ar en nybyggd osignerad exe, och det ar det varsta fallet
for realtidsskanning.

Sa syns det inifran: samma chunkning over samma filista tog 2406 ms
forsta gangen och 125 ms andra gangen, i SAMMA process, med samma kod.

MATT MED ANTIVIRUS I VAGEN AR INTE EN MATNING AV KODEN. Lat nagot lasa
tradet forst - `cat` eller en `status` - eller undanta arbetsytan i
Defender, annars mater man skannern.

## Skrapet

Ett `add` som aldrig blev en commit lamnar sina chunkar kvar. Det ar inte
sallan: man sparar, koar, sparar igen, koar igen. Matt pa tre add och en
commit: **28 objekt i lagret dar 7 behovdes.**

    rune gc     tar bort det ingen commit nar

Natbart ar kedjan bakat fran HEAD, OCH kon: det som ar koat men inte
committat far inte stadas bort under fotterna pa den som koade det.

    36 objekt, 1564 KB  ->  14 objekt, 536 KB

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

Servern ger ett svar per uppkoppling, sa en push oppnar en per objekt.
Keep-alive ar den enda kvarvarande posten pa listan.
