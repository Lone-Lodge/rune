#!/usr/bin/env bash
# rune-sviten. Kor hela flodet mot ett engangsrepo i build/t och jamfor
# aterskapade filer byte for byte mot originalen.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Windows ger .exe, POSIX inte. Sviten ska inte veta vilken plattform
# den star pa - den ska veta var binaren ar.
RUNE="$ROOT/build/rune_cli.exe"
[ -x "$RUNE" ] || RUNE="$ROOT/build/rune_cli"
# python3 pa de flesta POSIX, python i Git Bash. KOR den, inte bara leta:
# Windows lagger en python3 pa PATH som bara finns for att saga at en att
# installera den, och `command -v` hittar den glatt.
PY=python3; $PY -c "" >/dev/null 2>&1 || PY=python
T="$ROOT/build/t"
[ -x "$RUNE" ] || { echo "bygg forst: orbit build"; exit 1; }

rm -rf "$T"; mkdir -p "$T"; cd "$T"
fail=0
ok()   { echo "  PASS  $1"; }
bad()  { echo "  FAIL  $1"; fail=1; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (fick '$2', ville '$3')"; fi; }

# binart innehall med NUL-bytes, plus text
$PY -c "
import random; random.seed(3)
open('bild.png','wb').write(bytes([137,80,78,71,13,10,26,10])+bytes(random.getrandbits(8) for _ in range(300000)))
open('kod.txt','w').write('hej\n'*500)
import os; os.makedirs('sub', exist_ok=True)
open('sub/djup.bin','wb').write(bytes(random.getrandbits(8) for _ in range(120000)))
open('.runeignore','w').write('skrap/\n')
os.makedirs('skrap', exist_ok=True); open('skrap/strunt.txt','w').write('x')
"
md5() { $PY -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"; }
H_PNG=$(md5 bild.png); H_TXT=$(md5 kod.txt); H_SUB=$(md5 sub/djup.bin)

echo "== init och forsta commit =="
"$RUNE" init >/dev/null
check "status ser fyra nya (.runeignore versioneras ocksa)" "$("$RUNE" status | grep -c 'nytt')" "4"
check "runeignore haller skrap ute" "$("$RUNE" status | grep -c 'skrap')" "0"
"$RUNE" add . >/dev/null
check "status ser fyra koade" "$("$RUNE" status | grep -c 'koat')" "4"
C1=$("$RUNE" commit "forsta" | cut -d' ' -f1)
check "log har en commit" "$("$RUNE" log | wc -l)" "1"

echo "== andring =="
$PY -c "
d=bytearray(open('bild.png','rb').read()); d[150000]^=0xFF
open('bild.png','wb').write(d)"
check "status ser en andrad" "$("$RUNE" status | grep -c 'andrat')" "1"
H_PNG2=$(md5 bild.png)
"$RUNE" add . >/dev/null
C2=$("$RUNE" commit "andra" | cut -d' ' -f1)
check "log har tva commits" "$("$RUNE" log | wc -l)" "2"

echo "== checkout aterskapar byte for byte =="
rm -f bild.png kod.txt sub/djup.bin
"$RUNE" checkout "$C1" >/dev/null
check "png ur commit 1" "$(md5 bild.png)" "$H_PNG"
check "txt ur commit 1" "$(md5 kod.txt)" "$H_TXT"
check "djup fil ur commit 1" "$(md5 sub/djup.bin)" "$H_SUB"
"$RUNE" checkout "$C2" >/dev/null
check "png ur commit 2" "$(md5 bild.png)" "$H_PNG2"

echo "== borttagning syns =="
rm -f kod.txt
check "status ser borttaget" "$("$RUNE" status | grep -c 'borttaget')" "1"

echo "== dedup: en andrad byte kostar en chunk =="
# Chunkarna ligger i packen sedan `add` slutade skriva en fil per objekt,
# sa rakna bada stallena - annars provar testet ett lager som inte finns.
n=$(( $(find .rune/chunks -type f 2>/dev/null | wc -l) + $(cat .rune/pack/*.idx 2>/dev/null | awk -F'	' '$2=="chunks"' | wc -l) ))
check "chunkar delas mellan commits" "$([ "$n" -lt 12 ] && echo ja || echo nej)" "ja"

echo "== statcachen =="
# Cachen far ALDRIG dolja en andring. Det ar hela risken med den.
check "status skriver en cache" "$([ -f .rune/stat ] && echo ja || echo nej)" "ja"
f1="$("$RUNE" status)"
check "andra korningen ger samma svar" "$("$RUNE" status)" "$f1"
$PY -c "
d=bytearray(open('bild.png','rb').read()); d[9000]^=0xFF
open('bild.png','wb').write(d)"
check "cachen slapper igenom en andring" "$("$RUNE" status | grep -c 'bild.png')" "1"
printf 'x' >> sub/djup.bin
check "och en storleksandring" "$("$RUNE" status | grep -c 'djup.bin')" "1"

echo "== historik per fil =="
check "png har tva versioner" "$("$RUNE" history bild.png | wc -l)" "2"
check "kod.txt har en" "$("$RUNE" history kod.txt | wc -l)" "1"
check "okand fil har ingen" "$("$RUNE" history finns-inte.txt | grep -c 'ingen historik')" "1"
"$RUNE" show "$C1" bild.png v1.bin >/dev/null
check "show ger commit 1:s innehall" "$(md5 v1.bin)" "$H_PNG"

echo "== ur kon =="
mkdir -p "$T/ur"; cd "$T/ur"
"$RUNE" init >/dev/null
echo a > a.txt; echo b > b.txt
"$RUNE" add . >/dev/null
check "bada koade" "$("$RUNE" status | grep -c koat)" "2"
check "ur sager att den lag dar" "$("$RUNE" ur b.txt | grep -c 'ur kon')" "1"
check "och nu ar bara en koad" "$("$RUNE" status | grep -c koat)" "1"
check "en andra gang sager ifran" "$("$RUNE" ur b.txt | grep -c 'lag inte')" "1"
cd "$T"

echo "== runeignore med negation =="
# Utan att negationen nar IN i en utesluten mapp betyder `!` ingenting.
mkdir -p "$T/neg/Saved"; cd "$T/neg"
"$RUNE" init >/dev/null
echo x > Saved/skrap.txt; echo y > Saved/viktig.txt; echo z > a.log; echo w > behall.log
printf 'Saved/
!Saved/viktig.txt
*.log
!behall.log
' > .runeignore
check "utesluten mapp ar utesluten" "$("$RUNE" status | grep -c skrap)" "0"
check "men negationen nar in i den" "$("$RUNE" status | grep -c 'Saved/viktig')" "1"
check "glob utesluter" "$("$RUNE" status | grep -c 'a.log')" "0"
check "och negationen tar tillbaka" "$("$RUNE" status | grep -c behall)" "1"
cd "$T"

echo "== historik over ett namnbyte =="
# Ett namnbyte ar samma blob under ett annat namn, och blobbar ar vad
# manifestet redan bar - sa det kostar ingenting extra att folja.
mkdir -p "$T/nb"; cd "$T/nb"
"$RUNE" init >/dev/null
printf 'ett
' > a.txt; "$RUNE" add . >/dev/null; "$RUNE" commit a1 >/dev/null
printf 'tva
' > a.txt; "$RUNE" add . >/dev/null; "$RUNE" commit a2 >/dev/null
mv a.txt b.txt; "$RUNE" add . >/dev/null; "$RUNE" commit namnbyte >/dev/null
printf 'tre
' > b.txt; "$RUNE" add . >/dev/null; "$RUNE" commit b3 >/dev/null
check "historiken foljer med over bytet" "$("$RUNE" history b.txt | wc -l)" "3"
A=$("$RUNE" history b.txt | tail -1 | awk '{print $1}')
"$RUNE" show "$A" a.txt ut.txt >/dev/null
check "och aldsta versionen ar den forsta" "$(cat ut.txt)" "ett"
check "show tar ett forkortat id" "$("$RUNE" show "$A" a.txt ut2.txt | grep -c skrev)" "1"
cd "$T"

echo "== diff =="
mkdir -p "$T/df"; cd "$T/df"
"$RUNE" init >/dev/null
printf 'ett
tva
tre
fyra
fem
' > a.txt
"$RUNE" add . >/dev/null; "$RUNE" commit ett >/dev/null
check "ingen skillnad nar inget andrats" "$("$RUNE" diff a.txt | grep -c 'ingen skillnad')" "1"
printf 'ett
tva
TRE
fyra
ny
fem
' > a.txt
check "en andrad rad ut" "$("$RUNE" diff a.txt | grep -c '^  - 3     tre')" "1"
check "och in" "$("$RUNE" diff a.txt | grep -c '^  + 3     TRE')" "1"
check "en tillagd rad" "$("$RUNE" diff a.txt | grep -c '^  + 5     ny')" "1"
check "orord borjan och slut namns inte" "$("$RUNE" diff a.txt | wc -l)" "3"
# En binar har inga meningsfulla rader och ska sagas ifran om, inte
# jamforas byte for byte tills nagot ser konstigt ut.
$PY -c "import os;open('b.bin','wb').write(os.urandom(1000))"
"$RUNE" add . >/dev/null; "$RUNE" commit tva >/dev/null
$PY -c "import os;open('b.bin','wb').write(os.urandom(1000))"
check "binar sager ifran" "$("$RUNE" diff b.bin | grep -c 'binar')" "1"
cd "$T"

echo "== las =="
printf 'ny
' > last.txt
"$RUNE" lock last.txt >/dev/null
check "locks listar den" "$("$RUNE" locks | grep -c 'last.txt')" "1"
check "eget las hindrar inte" "$("$RUNE" add last.txt | grep -c 'koade 1')" "1"
# nagon annans las: skriv raden direkt, det ar det en remote skulle ha gjort
printf 'annans.txt	kollega	1
' >> .rune/locks
printf 'ny
' > annans.txt
check "annans las stoppar add" "$("$RUNE" add annans.txt | grep -c 'last av kollega')" "1"
check "annans las kommer inte in i kon" "$(grep -c 'annans.txt' .rune/index || true)" "0"
check "kan inte slappa annans las" "$("$RUNE" unlock annans.txt | grep -c 'inte din')" "1"
check "eget las gar att slappa" "$("$RUNE" unlock last.txt | grep -c 'slappt')" "1"
check "det andra laset star kvar" "$("$RUNE" locks | grep -c 'kollega')" "1"
# Ett las som nagon lamnat kvar maste ga att ta bort, annars star filen
# last tills nagon redigerar lasfilen for hand.
check "bryt sager vem som holl det" "$("$RUNE" bryt annans.txt | grep -c 'last av kollega')" "1"
check "och laset ar borta" "$("$RUNE" locks | grep -c 'kollega')" "0"
check "bryta ett fritt las sager ifran" "$("$RUNE" bryt annans.txt | grep -c 'ingen holl')" "1"
check "och filen gar att koa igen" "$("$RUNE" add annans.txt | grep -c 'koade 1')" "1"

echo "== ogonblicksbilden ar HELA tradet =="
# En partiell add fick manifestet att bli BARA det koade: allt man inte
# koade forsvann ur historien, och en clone hade fatt ett trad utan dem.
mkdir -p "$T/bild"; cd "$T/bild"
"$RUNE" init >/dev/null
printf 'ett
' > en.txt; printf 'tva
' > tva.txt
"$RUNE" add . >/dev/null; "$RUNE" commit "bada" >/dev/null
printf 'ett igen
' > en.txt
"$RUNE" add en.txt >/dev/null; "$RUNE" commit "bara en" >/dev/null
man() { C=$(cat .rune/refs/heads/main); M=$(grep '^manifest' ".rune/commits/${C:0:2}/${C:2}" | cut -d' ' -f2); cat ".rune/manifests/${M:0:2}/${M:2}"; }
check "partiell add behaller resten" "$(man | grep -c 'tva.txt')" "1"
check "och tradet ar rent efterat" "$("$RUNE" status | wc -l)" "0"
rm tva.txt
check "borttagen fil syns" "$("$RUNE" status | grep -c 'borttaget')" "1"
"$RUNE" add . >/dev/null
check "add . koar borttagningen" "$("$RUNE" status | grep -c 'koat.*tva.txt')" "1"
"$RUNE" commit "bort" >/dev/null
check "borttagningen ar ur ogonblicksbilden" "$(man | grep -c 'tva.txt')" "0"
check "rent efter borttagningen" "$("$RUNE" status | wc -l)" "0"
cd "$T"

echo "== .runeignore med stjarna =="
mkdir -p "$T/ign/sub/djup" "$T/ign/Saved"; cd "$T/ign"
"$RUNE" init >/dev/null
for f in a.txt a.log sub/b.log sub/b.txt sub/djup/c.log Saved/d.txt tmp.bak; do echo x > "$f"; done
printf '*.log\nSaved/\n*.bak\n' > .runeignore
check "stjarna tar filen i roten" "$("$RUNE" status | grep -c 'a.log')" "0"
check "och langre ner ocksa" "$("$RUNE" status | grep -c 'c.log')" "0"
check "prefix fungerar som forut" "$("$RUNE" status | grep -c 'Saved')" "0"
check "det som inte matchar ar kvar" "$("$RUNE" status | grep -c 'sub/b.txt')" "1"
check "tre filer kvar: .runeignore, a.txt och sub/b.txt" "$("$RUNE" status | wc -l)" "3"
cd "$T"

# Komprimeringen: text ska krympa, slumpdata ska lagras rakt av och
# ALDRIG vaxa av forsoket.
mkdir -p "$T/kz"; cd "$T/kz"
echo "== komprimeringen =="
"$RUNE" init >/dev/null
for q in $(seq 1 3000); do echo "public define nagot(x: number) -> number = x + 1"; done > text.txt
$PY -c "import os;open('slump.bin','wb').write(os.urandom(400000))"
"$RUNE" add . >/dev/null; "$RUNE" commit ett >/dev/null; "$RUNE" pack >/dev/null
PACK=$($PY -c "import glob,os;print(os.path.getsize(glob.glob('.rune/pack/*.pack')[0]))")
check "packen ar mindre an radatan" "$([ "$PACK" -lt 500000 ] && echo ja || echo nej)" "ja"
check "och storre an bara slumpdelen" "$([ "$PACK" -gt 400000 ] && echo ja || echo nej)" "ja"
H=$(cat .rune/refs/heads/main)
S1=$(md5 text.txt); S2=$(md5 slump.bin)
rm text.txt slump.bin; "$RUNE" checkout "$H" >/dev/null
check "texten ur den komprimerade packen" "$(md5 text.txt)" "$S1"
check "binaren ur samma pack" "$(md5 slump.bin)" "$S2"
cd "$T"

echo "== packnamn kolliderar inte =="
# Namnet raknades fram ur ANTALET filer i packmappen. Tva fel: list_dir pa
# en tom mapp ger [""] och alltsa langden 1, och `(n + 1 as text)` binder
# som `n + (1 as text)` - en konkatenering. En pack hette "21" i stallet
# for "3", och forr eller senare hade ett add oppnat en BEFINTLIG pack for
# skrivning och tomt den.
mkdir -p "$T/pn"; cd "$T/pn"
"$RUNE" init >/dev/null
echo forsta > a.txt
"$RUNE" add . >/dev/null; "$RUNE" commit ett >/dev/null; "$RUNE" pack >/dev/null
for i in 2 3 4 5 6; do echo "rad $i" > "f$i.txt"; "$RUNE" add . >/dev/null; "$RUNE" commit "c$i" >/dev/null; done
"$RUNE" pack >/dev/null
check "lagret ar sunt efter varv av add och pack" "$("$RUNE" fsck | grep -c 'sunt')" "1"
H=$(cat .rune/refs/heads/main); rm -f ./*.txt
"$RUNE" checkout "$H" >/dev/null
check "alla sex filerna finns kvar" "$(ls ./*.txt | wc -l)" "6"
check "och den forsta ar orord" "$(cat a.txt)" "forsta"
cd "$T"

echo "== skrapet =="
# `pack` skriver om det NABARA, sa skrap forsvinner som en foljd.
# Ett add som aldrig blev en commit lamnar sina chunkar kvar. Man sparar,
# koar, sparar igen - och ingenting stadade det forut.
mkdir -p "$T/gc"; cd "$T/gc"
"$RUNE" init >/dev/null
for i in 1 2 3; do $PY -c "import os;open('a.bin','wb').write(os.urandom(500000))"; "$RUNE" add . >/dev/null; done
"$RUNE" commit ett >/dev/null
objekt(){ find .rune/chunks .rune/blobs .rune/commits .rune/manifests -type f 2>/dev/null | wc -l; }
FORE=$(objekt)
"$RUNE" pack >/dev/null
EFTER=$(objekt)
check "pack tog bort skrapet" "$([ "$EFTER" -lt "$FORE" ] && echo ja || echo nej)" "ja"
check "och lagret ar sunt efterat" "$("$RUNE" fsck | grep -c 'sunt')" "1"
H=$(cat .rune/refs/heads/main)
rm a.bin; "$RUNE" checkout "$H" >/dev/null
check "commiten gar fortfarande att checka ut" "$($PY -c "import os;print(os.path.getsize('a.bin'))")" "500000"
# Det KOADE far inte stadas bort under fotterna pa den som koade det.
$PY -c "import os;open('b.bin','wb').write(os.urandom(100000))"
"$RUNE" add b.bin >/dev/null
"$RUNE" pack >/dev/null
"$RUNE" commit tva >/dev/null
check "koat overlever en pack" "$("$RUNE" status | wc -l)" "0"
check "och lagret ar sunt" "$("$RUNE" fsck | grep -c 'sunt')" "1"
cd "$T"

echo "== packen =="
# Ett objekt per fil kostar bade plats och tid. En pack ar manga kroppar
# efter varandra med ett register bredvid.
mkdir -p "$T/pk"; cd "$T/pk"
"$RUNE" init >/dev/null
$PY -c "
import os
for i in range(300):
    d='d%02d'%(i%10); os.makedirs(d,exist_ok=True)
    open(os.path.join(d,'f%03d.bin'%i),'wb').write(os.urandom(2048))"
"$RUNE" add . >/dev/null; "$RUNE" commit ett >/dev/null
FORE=$(du -sk .rune | cut -f1)
"$RUNE" pack >/dev/null
EFTER=$(du -sk .rune | cut -f1)
check "packen tar mindre plats" "$([ "$EFTER" -lt "$FORE" ] && echo ja || echo nej)" "ja"
check "och ar fa filer" "$([ "$(find .rune -type f | wc -l)" -lt 10 ] && echo ja || echo nej)" "ja"
check "fsck laser packen ocksa" "$("$RUNE" fsck | grep -c 'sunt')" "1"
check "tradet ar orort" "$("$RUNE" status | wc -l)" "0"
H=$(cat .rune/refs/heads/main); rm -rf d00
"$RUNE" checkout "$H" >/dev/null
check "checkout ur packen" "$("$RUNE" status | wc -l)" "0"
# En byte fel mitt i packen ska hittas, inte tigas ihjal.
$PY -c "
import glob
p=glob.glob('.rune/pack/*.pack')[0]
d=bytearray(open(p,'rb').read()); d[5000]^=0xFF; open(p,'wb').write(d)"
check "fsck hittar skada i packen" "$("$RUNE" fsck | grep -c 'TRASIGT')" "1"
# En trasig strom far inte KRASCHA avkodaren. Det ar just pa trasiga
# bytes fsck kors, sa den maste overleva dem och saga vad den fann.
check "och kraschar inte pa vagen" "$("$RUNE" fsck >/dev/null 2>&1; echo $?)" "0"
cd "$T"

echo "== lagrets sundhet =="
mkdir -p "$T/sund"; cd "$T/sund"
"$RUNE" init >/dev/null
$PY -c "import os;open('a.bin','wb').write(os.urandom(200000))"
"$RUNE" add . >/dev/null; "$RUNE" commit "ett" >/dev/null
check "fsck ser ett sunt lager" "$("$RUNE" fsck | grep -c 'sunt')" "1"
check "stat laser inte hela filen" "$("$RUNE" stat a.bin | grep -c 'chunkar')" "1"
# Namnet ar hashen av innehallet, sa en andrad byte gor kroppen till nagot
# annat an det objekt den utger sig for att vara. Objekten ligger i packen
# nu, sa det ar dar bytet ska andras.
$PY -c "
import glob
p=glob.glob('.rune/pack/*.pack')[0]
d=bytearray(open(p,'rb').read()); d[10]^=0xFF; open(p,'wb').write(d)"
check "fsck hittar en andrad chunk" "$("$RUNE" fsck | grep -c 'TRASIGT')" "1"

echo "== en skrivning som inte gar igenom =="
# Bade packmappen och objektmappen som FILER: da misslyckas skrivningen
# oavsett vilken vag objektet tar. Forut hamnade blob-id:t i kon anda, och
# commiten gick inte att checka ut.
mkdir -p "$T/full"; cd "$T/full"
"$RUNE" init >/dev/null
printf 'x
' > a.txt
rm -rf .rune/chunks .rune/pack
printf 'inte en mapp' > .rune/chunks; printf 'inte heller' > .rune/pack
check "add sager ifran" "$("$RUNE" add . | grep -c 'KUNDE INTE LAGRAS')" "1"
check "och koar ingenting" "$(cat .rune/index | wc -c)" "0"
cd "$T"

cd "$ROOT"; rm -rf "$T"
[ "$fail" = 0 ] && echo "rune: allt gront" || { echo "rune: NAGOT GICK FEL"; exit 1; }
