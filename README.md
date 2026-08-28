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

    rune init                   # starta ett repo har
    rune add .                  # koa hela tradet
    rune status                 # koat / nytt / andrat / borttaget
    rune commit "meddelande"
    rune log
    rune checkout <commit>      # skriv ut en ogonblicksbild
    rune stat <fil>             # visa chunkningen utan att lagra

## .runeignore

En rad per monster, prefixmatchning pa den relativa sokvagen. `Saved/` tar
allt darunder. Inga globbar. For ett Unreal-projekt racker:

    Saved/
    Intermediate/
    DerivedDataCache/
    Binaries/
    .vs/

## Granser

Filer lases hela i minnet, sa nagra hundra MB per fil. `status` hashar om
hela arbetstradet varje gang - korrekt, men langsamt pa stora repon.
Manifestet sorteras med en urvalssortering. Ingen remote, inga grenar,
inga las. Inget av det andrar formatet.
