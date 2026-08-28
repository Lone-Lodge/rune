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

cd "$ROOT"; rm -rf "$T"
[ "$fail" = 0 ] && echo "rune: allt gront" || { echo "rune: NAGOT GICK FEL"; exit 1; }
