#!/usr/bin/env bash
# rune-sviten. Kor hela flodet mot ett engangsrepo i build/t och jamfor
# aterskapade filer byte for byte mot originalen.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNE="$ROOT/build/rune_cli.exe"
T="$ROOT/build/t"
[ -x "$RUNE" ] || { echo "bygg forst: orbit build"; exit 1; }

rm -rf "$T"; mkdir -p "$T"; cd "$T"
fail=0
ok()   { echo "  PASS  $1"; }
bad()  { echo "  FAIL  $1"; fail=1; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (fick '$2', ville '$3')"; fi; }

# binart innehall med NUL-bytes, plus text
python -c "
import random; random.seed(3)
open('bild.png','wb').write(bytes([137,80,78,71,13,10,26,10])+bytes(random.getrandbits(8) for _ in range(300000)))
open('kod.txt','w').write('hej\n'*500)
import os; os.makedirs('sub', exist_ok=True)
open('sub/djup.bin','wb').write(bytes(random.getrandbits(8) for _ in range(120000)))
open('.runeignore','w').write('skrap/\n')
os.makedirs('skrap', exist_ok=True); open('skrap/strunt.txt','w').write('x')
"
md5() { python -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"; }
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
python -c "
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
n=$(find .rune/chunks -type f | wc -l)
check "chunkar delas mellan commits" "$([ "$n" -lt 12 ] && echo ja || echo nej)" "ja"

echo "== statcachen =="
# Cachen far ALDRIG dolja en andring. Det ar hela risken med den.
check "status skriver en cache" "$([ -f .rune/stat ] && echo ja || echo nej)" "ja"
f1="$("$RUNE" status)"
check "andra korningen ger samma svar" "$("$RUNE" status)" "$f1"
python -c "
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

echo "== skrapet =="
# Ett add som aldrig blev en commit lamnar sina chunkar kvar. Man sparar,
# koar, sparar igen - och ingenting stadade det forut.
mkdir -p "$T/gc"; cd "$T/gc"
"$RUNE" init >/dev/null
for i in 1 2 3; do python -c "import os;open('a.bin','wb').write(os.urandom(500000))"; "$RUNE" add . >/dev/null; done
"$RUNE" commit ett >/dev/null
objekt(){ find .rune/chunks .rune/blobs .rune/commits .rune/manifests -type f 2>/dev/null | wc -l; }
FORE=$(objekt)
"$RUNE" gc >/dev/null
EFTER=$(objekt)
check "gc tog bort nagot" "$([ "$EFTER" -lt "$FORE" ] && echo ja || echo nej)" "ja"
check "och lagret ar sunt efterat" "$("$RUNE" fsck | grep -c 'sunt')" "1"
H=$(cat .rune/refs/heads/main)
rm a.bin; "$RUNE" checkout "$H" >/dev/null
check "commiten gar fortfarande att checka ut" "$(python -c "import os;print(os.path.getsize('a.bin'))")" "500000"
# Det KOADE far inte stadas bort under fotterna pa den som koade det.
python -c "import os;open('b.bin','wb').write(os.urandom(100000))"
"$RUNE" add b.bin >/dev/null
"$RUNE" gc >/dev/null
"$RUNE" commit tva >/dev/null
check "koat overlever en gc" "$("$RUNE" status | wc -l)" "0"
check "och lagret ar sunt" "$("$RUNE" fsck | grep -c 'sunt')" "1"
cd "$T"

echo "== lagrets sundhet =="
mkdir -p "$T/sund"; cd "$T/sund"
"$RUNE" init >/dev/null
python -c "import os;open('a.bin','wb').write(os.urandom(200000))"
"$RUNE" add . >/dev/null; "$RUNE" commit "ett" >/dev/null
check "fsck ser ett sunt lager" "$("$RUNE" fsck | grep -c 'sunt')" "1"
check "stat laser inte hela filen" "$("$RUNE" stat a.bin | grep -c 'chunkar')" "1"
# Namnet ar hashen av innehallet, sa en andrad byte gor filen till nagot
# annat an det objekt den utger sig for att vara.
F=$(find .rune/chunks -type f | head -1)
python -c "import sys;p=sys.argv[1];d=bytearray(open(p,'rb').read());d[10]^=0xFF;open(p,'wb').write(d)" "$F"
check "fsck hittar en andrad chunk" "$("$RUNE" fsck | grep -c 'TRASIGT')" "1"

echo "== en skrivning som inte gar igenom =="
# .rune/chunks som FIL i stallet for mapp: da misslyckas varje objekt.
# Forut hamnade blob-id:t i kon anda, och commiten gick inte att checka ut.
mkdir -p "$T/full"; cd "$T/full"
"$RUNE" init >/dev/null
printf 'x
' > a.txt
rm -rf .rune/chunks; printf 'inte en mapp' > .rune/chunks
check "add sager ifran" "$("$RUNE" add . | grep -c 'KUNDE INTE LAGRAS')" "1"
check "och koar ingenting" "$(cat .rune/index | wc -c)" "0"
cd "$T"

cd "$ROOT"; rm -rf "$T"
[ "$fail" = 0 ] && echo "rune: allt gront" || { echo "rune: NAGOT GICK FEL"; exit 1; }
