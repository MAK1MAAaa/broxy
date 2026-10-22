#!/bin/sh
set -eu
BROXY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for BROXY_SUITE in rules combat ui flow feedback simulation_shop; do
  "$BROXY_ROOT/tools/run.sh" --headless --script "res://tests/test_$BROXY_SUITE.gd"
done
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/broxy-pycache" python3 -m unittest discover -s "$BROXY_ROOT/tests" -p 'test_shop_analysis.py'
