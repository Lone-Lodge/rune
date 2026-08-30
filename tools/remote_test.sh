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
skrivbart(){ python -c "import sys
try:
    open(sys.argv[1],'ab').close(); print('ja')
except PermissionError:
    print('nej')" "$1"; }
skydd(){ python -c "import os,stat,sys;m=os.stat(sys.argv[1]).st_mode;print('skrivbar' if m & stat.S_IWRITE else 'skyddad')" "$1"; }

HEMLIS="delad-hemlighet-123"
( cd srv && "$RUNE" init >/dev/null && "$RUNE" secret "$HEMLIS" >/dev/null )
has "serve vagrar utan hemlighet" "$(cd a && "$RUNE" init >/dev/null && "$RUNE" serve 7431)" "ingen hemlighet"
rm -rf a; mkdir -p a
( cd srv && exec "$RUNE" serve $PORT >/dev/null 2>&1 ) &
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
"$RUNE" init >/dev/null; "$RUNE" remote "$URL" >/dev/null; "$RUNE" secret "$HEMLIS" >/dev/null
"$RUNE" add . >/dev/null; "$RUNE" commit "forsta" >/dev/null
has "push gick igenom" "$("$RUNE" push)" "pushade"

echo "== clone till tom mapp, byte for byte =="
cd "$T/b"
has "fel hemlighet nekas" "$("$RUNE" clone "$URL" "fel-hemlighet" 2>&1)" "fel eller saknad hemlighet"
rm -rf "$T/b"; mkdir -p "$T/b"; cd "$T/b"
has "clone hamtade och skrev" "$("$RUNE" clone "$URL" "$HEMLIS")" "skrev"
check "3 MB binar overlevde natet" "$(sha stor.bin)" "$H_BIN"
has "clone vagrar over ett befintligt repo" "$("$RUNE" clone "$URL" "$HEMLIS")" "finns redan"

echo "== inkrementell push =="
cd "$T/a"
python -c "
d=bytearray(open('stor.bin','rb').read()); d[1500000]^=0xFF
open('stor.bin','wb').write(d)"
"$RUNE" add . >/dev/null; "$RUNE" commit "en byte" >/dev/null
check "en andrad byte i 3 MB kostar 4 objekt" "$("$RUNE" push)" "pushade 4 objekt"

echo "== pull skriver arbetstradet =="
# Pull rorde inte tradet forut: du fick hamta hem objekten och sedan
# sjalv klistra in ett 64 tecken langt id i checkout. Nu gor den bada,
# och vagrar helt om du har nagot okommitterat som skulle skrivas over.
cd "$T/a"
printf 'andrad
' > text.md
printf 'ny fil
' > extra.md
"$RUNE" add . >/dev/null; "$RUNE" commit "andring och en ny" >/dev/null
"$RUNE" push >/dev/null
cd "$T/b"
has "pull skriver filerna" "$("$RUNE" pull)" "skrev"
check "andringen kom fram" "$(cat text.md)" "andrad"
check "den nya filen kom fram" "$(cat extra.md)" "ny fil"
check "tradet ar rent efter pull" "$("$RUNE" status | wc -l)" "0"
cd "$T/a"
rm extra.md
"$RUNE" add . >/dev/null; "$RUNE" commit "bort med extra" >/dev/null
"$RUNE" push >/dev/null
cd "$T/b"
"$RUNE" pull >/dev/null
check "borttagningen kom fram" "$([ -f extra.md ] && echo finns || echo borta)" "borta"

echo "== pull vagrar over okommitterat =="
printf 'okoat
' > mitt.txt
cd "$T/a"
printf 'annu en
' > text.md
"$RUNE" add . >/dev/null; "$RUNE" commit "annu en" >/dev/null
"$RUNE" push >/dev/null
cd "$T/b"
has "pull vagrar" "$("$RUNE" pull)" "inte ar committade"
check "min egen fil ar kvar" "$(cat mitt.txt)" "okoat"
rm mitt.txt

echo "== tva som gar isar =="
cd "$T/b"; "$RUNE" pull >/dev/null
printf 'fran b\n' > b.txt; "$RUNE" add . >/dev/null; "$RUNE" commit "b" >/dev/null
cd "$T/a"; printf 'fran a\n' > a.txt; "$RUNE" add . >/dev/null; "$RUNE" commit "a" >/dev/null
"$RUNE" push >/dev/null
cd "$T/b"
has "push vagrar nar servern gatt fore" "$("$RUNE" push)" "pull. forst"
has "pull vagrar snabbspola over egna commits" "$("$RUNE" pull)" "gatt isar"
check "b:s egen commit ligger kvar" "$("$RUNE" log | wc -l)" "6"

echo "== init respekterar en befintlig git =="
mkdir -p "$T/g" && cd "$T/g" && git init -q . && printf 'x
' > f.txt
"$RUNE" init >/dev/null
check "init la .rune/ i .gitignore" "$(grep -c '^.rune/$' .gitignore)" "1"
"$RUNE" init >/dev/null 2>&1
check "andra init dubblerar inte raden" "$(grep -c '^.rune/$' .gitignore)" "1"
cd "$T/b"

echo "== lasa ur lagret utan att kanna det =="
# Servern har ALDRIG skrivit ut nagon fil till sin egen arbetsyta. Att den
# anda kan svara med innehall ar hela poangen: den laser ur objekten.
AUTH="Authorization: Bearer $HEMLIS"
cd "$T/a"
check "tree listar sokvagarna" "$(curl -s -H "$AUTH" "$URL/tree" | grep -c 'stor.bin')" "1"
curl -s -H "$AUTH" "$URL/file?path=stor.bin" -o hel.tmp
check "file ger hela filen, byte for byte" "$(sha hel.tmp)" "$(sha stor.bin)"
curl -s -H "$AUTH" "$URL/file?path=stor.bin&from=1500000&to=1500016" -o bit.tmp
check "ett intervall mitt i en 3 MB-binar" "$(python -c "
d=open('stor.bin','rb').read()[1500000:1500016]
g=open('bit.tmp','rb').read()
print('lika' if d==g else 'skiljer')")" "lika"
check "okand sokvag ger 404" "$(curl -s -o /dev/null -w '%{http_code}' -H "$AUTH" "$URL/file?path=finns-inte.bin")" "404"
check "hist ger filens versioner" "$(curl -s -H "$AUTH" "$URL/hist?path=text.md" | wc -l)" "3"
rm -f hel.tmp bit.tmp

echo "== skriva in i lagret utifran =="
# Ett innehall in, en commit ut. Ingen ko: den ar en delad fil, och en
# server som stagar at en klient hade lagt nagon annans arbete i din commit.
cd "$T/a"
python -c "
import os
b = bytearray(os.urandom(300000))
b[1000:1004] = b'\r\n\r\n'   # sekvensen som kapar en naiv HTTP-lasare
open('ny.dat','wb').write(bytes(b))"
C1=$(curl -s -H "$AUTH" -X POST --data-binary @ny.dat "$URL/file?path=under/ny.dat&who=alice&msg=forsta")
curl -s -H "$AUTH" "$URL/file?path=under/ny.dat" -o ater.dat
check "binar med CRLFCRLF tur och retur" "$(sha ater.dat)" "$(sha ny.dat)"
C2=$(curl -s -H "$AUTH" -X POST --data-binary @ny.dat "$URL/file?path=under/ny.dat&who=alice&msg=igen")
check "samma innehall ger ingen ny commit" "$C2" "$C1"
# Lassparren ligger i lagret, inte i den som svarar pa requesten.
printf 'under/ny.dat
kollega' | curl -s -H "$AUTH" -X POST --data-binary @- "$URL/lock" >/dev/null
check "annans las nekar skrivningen" "$(curl -s -o /dev/null -w '%{http_code}' -H "$AUTH" -X POST --data-binary @ny.dat "$URL/file?path=under/ny.dat&who=alice")" "409"
has "och sager vem som haller den" "$(curl -s -H "$AUTH" -X POST --data-binary @ny.dat "$URL/file?path=under/ny.dat&who=alice")" "last av kollega"
check "hallaren far skriva" "$(curl -s -o /dev/null -w '%{http_code}' -H "$AUTH" -X POST --data-binary "annat" "$URL/file?path=under/ny.dat&who=kollega&msg=min")" "200"
printf 'under/ny.dat
kollega' | curl -s -H "$AUTH" -X POST --data-binary @- "$URL/unlock" >/dev/null
rm -f ny.dat ater.dat

echo "== las over remoten =="
# b ar en ANNAN person. Utan det testar man bara att man far ta om sitt
# eget las, vilket man ska fa.
cd "$T/b"; printf 'b ror den
' >> stor.bin   # medan den ar fri
cd "$T/a"; "$RUNE" lock stor.bin >/dev/null
has "b ser a:s las" "$(cd "$T/b" && "$RUNE" locks)" "stor.bin"
cd "$T/b"
has "b kan inte ta den" "$(USERNAME=kollega "$RUNE" lock stor.bin)" "redan last"
has "b kan inte slappa den" "$(USERNAME=kollega "$RUNE" unlock stor.bin)" "inte din"
has "b:s add hoppar over den lasta" "$(USERNAME=kollega "$RUNE" add .)" "last av"
# Sparret i add kommer forst nar jobbet redan ar gjort. Skyddet pa disk
# sager ifran i programmet man faktiskt ritar i, innan man borjar.
check "b:s kopia ar skrivskyddad" "$(skydd stor.bin)" "skyddad"
check "och gar faktiskt inte att skriva" "$(skrivbart stor.bin)" "nej"
check "b:s egen fil ar orord" "$(skydd text.md)" "skrivbar"
cd "$T/a"; has "a kan slappa sin egen" "$("$RUNE" unlock stor.bin)" "slappt"
cd "$T/b"; USERNAME=kollega "$RUNE" add . >/dev/null 2>&1 || true
check "skyddet slapper med laset" "$(skydd stor.bin)" "skrivbar"
check "och gar att skriva igen" "$(skrivbart stor.bin)" "ja"

kill $SRV 2>/dev/null || true
cd "$ROOT"
for i in $(seq 1 20); do rm -rf "$T" 2>/dev/null && break; done
[ "$fail" = 0 ] && echo "rune remote: allt gront" || { echo "rune remote: NAGOT GICK FEL"; exit 1; }
