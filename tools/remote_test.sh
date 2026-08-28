#!/usr/bin/env bash
# rune-remotesviten. Startar en server, tva klienter, och kor det som
# faktiskt kan ga fel: binart over natet, inkrementell push, tva som gar
# isar, och las som en annan maskin haller.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNE="$ROOT/build/rune_cli.exe"
T="$ROOT/build/rt"
PORT=7429
URL="http://127.0.0.1:$PORT"
[ -x "$RUNE" ] || { echo "bygg forst: orbit build"; exit 1; }

rm -rf "$T"; mkdir -p "$T/srv" "$T/a" "$T/b"; cd "$T"
fail=0
ok()   { echo "  PASS  $1"; }
bad()  { echo "  FAIL  $1"; fail=1; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (fick '$2', ville '$3')"; fi; }
has()  { if echo "$2" | grep -q "$3"; then ok "$1"; else bad "$1 (fick '$2')"; fi; }
sha()  { python -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"; }

( cd srv && "$RUNE" serve $PORT >/dev/null 2>&1 ) &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for i in $(seq 1 20); do curl -s -m 1 "$URL/ref" >/dev/null 2>&1 && break; done

echo "== push av binart =="
cd "$T/a"
python -c "
import random; random.seed(5)
open('stor.bin','wb').write(bytes(random.getrandbits(8) for _ in range(3000000)))
open('text.md','w').write('hej\n'*200)"
H_BIN=$(sha stor.bin)
"$RUNE" init >/dev/null; "$RUNE" remote "$URL" >/dev/null
"$RUNE" add . >/dev/null; "$RUNE" commit "forsta" >/dev/null
has "push gick igenom" "$("$RUNE" push)" "pushade"

echo "== pull till tomt repo, byte for byte =="
cd "$T/b"
"$RUNE" init >/dev/null; "$RUNE" remote "$URL" >/dev/null
has "pull hamtade" "$("$RUNE" pull)" "hamtade"
"$RUNE" checkout "$(curl -s -m 3 "$URL/ref")" >/dev/null
check "3 MB binar overlevde natet" "$(sha stor.bin)" "$H_BIN"

echo "== inkrementell push =="
cd "$T/a"
python -c "
d=bytearray(open('stor.bin','rb').read()); d[1500000]^=0xFF
open('stor.bin','wb').write(d)"
"$RUNE" add . >/dev/null; "$RUNE" commit "en byte" >/dev/null
check "en andrad byte i 3 MB kostar 4 objekt" "$("$RUNE" push)" "pushade 4 objekt"

echo "== tva som gar isar =="
cd "$T/b"; "$RUNE" pull >/dev/null
printf 'fran b\n' > b.txt; "$RUNE" add . >/dev/null; "$RUNE" commit "b" >/dev/null
cd "$T/a"; printf 'fran a\n' > a.txt; "$RUNE" add . >/dev/null; "$RUNE" commit "a" >/dev/null
"$RUNE" push >/dev/null
cd "$T/b"
has "push vagrar nar servern gatt fore" "$("$RUNE" push)" "pull. forst"
has "pull vagrar snabbspola over egna commits" "$("$RUNE" pull)" "gatt isar"
check "b:s egen commit ligger kvar" "$("$RUNE" log | wc -l)" "3"

echo "== las over remoten =="
# b ar en ANNAN person. Utan det testar man bara att man far ta om sitt
# eget las, vilket man ska fa.
cd "$T/a"; "$RUNE" lock stor.bin >/dev/null
has "b ser a:s las" "$(cd "$T/b" && "$RUNE" locks)" "stor.bin"
cd "$T/b"
has "b kan inte ta den" "$(USERNAME=kollega "$RUNE" lock stor.bin)" "redan last"
has "b kan inte slappa den" "$(USERNAME=kollega "$RUNE" unlock stor.bin)" "inte din"
printf 'b ror den
' >> stor.bin
has "b:s add hoppar over den lasta" "$(USERNAME=kollega "$RUNE" add .)" "last av"
cd "$T/a"; has "a kan slappa sin egen" "$("$RUNE" unlock stor.bin)" "slappt"

kill $SRV 2>/dev/null || true
cd "$ROOT"
for i in $(seq 1 20); do rm -rf "$T" 2>/dev/null && break; done
[ "$fail" = 0 ] && echo "rune remote: allt gront" || { echo "rune remote: NAGOT GICK FEL"; exit 1; }
