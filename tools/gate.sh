#!/usr/bin/env bash
# Allt som maste vara gront innan nagot slapps igenom: bygg, sviten,
# remotesviten. Ett kommando, en utgangskod - det ar det CI behover, och
# det ar samma sak du kor sjalv.
#
# Bygget gar genom orbit ur orion-repot BREDVID det har. Det ar inte ett
# beroende rune kan hamta sjalv, sa gaten sager ifran i klartext i stallet
# for att fela pa nagot obegripligt langre in.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ORBIT="$ROOT/../orion/dist/orbit.exe"
[ -x "$ORBIT" ] || ORBIT="$ROOT/../orion/dist/orbit"
if [ ! -x "$ORBIT" ]; then
    echo "gate: hittar ingen orbit i ../orion/dist - bygg orion forst"
    exit 1
fi

echo "== bygger =="
"$ORBIT" build

echo "== sviten =="
bash tools/test.sh

echo "== remotesviten =="
bash tools/remote_test.sh

echo
echo "gate: allt gront"
