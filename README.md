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
    rune checkout <commit>      # skriv ut en ogonblicksbild
    rune lock <sokvag>          # ta filen, ingen annan far koa den
    rune unlock <sokvag>        # slapp den
    rune locks                  # vem haller vad
    rune stat <fil>             # visa chunkningen utan att lagra

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
ordningen. Nasta steg for laset ar att markera latta filer skrivskyddade pa
disk, sa Unreal sjalvt visar dem som tagna. Det kraver en ny runtime-extern
i Orion och ligger darfor utanfor.

## Remote

Hela synken ar en fraga: **vilka id saknar du?** Det ar innehallsadresseringens
utdelning. Ingen jamforelse av trad, inga deltan, ingen forhandling.

    rune serve 7420             # pa maskinen som haller repot
    rune remote http://host:7420
    rune push                   # skickar det servern saknar
    rune pull                   # hamtar det du saknar (ror inte arbetstradet)

Matt: 3 MB binar andrad pa **en byte** kostar 4 objekt over natet - en chunk,
dess blob, manifestet och commiten.

Egen HTTP pa net-orben, inte app-orben: app splittar requesten pa `

`
och tar andra biten som kropp, sa en binar kropp som rakar innehalla den
sekvensen kapas. Chunkar ur .uasset-filer gor det forr eller senare.

**Bara snabbspolning.** Push vagrar om serverns commit inte ligger i din
kedja, pull vagrar om du har egna commits vid sidan av. Binarer gar anda
inte att sla ihop - det ar darfor lasen finns.

Med en remote satt ar **servern sanningen om lasen**. Ett las som bara finns
lokalt kan aldrig saga att nagon ANNAN haller filen, och da ar det ingen
sparr utan en anteckning. Den lokala lasfilen blir en cache som `add` far
sin sparr ur.

## Granser

Filer lases hela i minnet, sa nagra hundra MB per fil. `status` hashar om
hela arbetstradet varje gang - korrekt, men langsamt pa stora repon.
Manifestet sorteras med en urvalssortering. Inga grenar, ingen
autentisering pa servern - den litar pa alla som kan na porten, sa den hor
hemma bakom brandvagg eller VPN tills det finns.
