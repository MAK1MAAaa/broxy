#!/bin/sh
set -eu
BROXY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for BROXY_SUITE in rules purchase_query combat homing ui notifications modal choice_actions upgrade_previews shop_actions shop_details shop_availability profile_modes flow feedback impact_feedback projectile_painter enemy_telegraphs simulation_shop; do
  "$BROXY_ROOT/tools/run.sh" --headless --script "res://tests/test_$BROXY_SUITE.gd"
done
for BROXY_DIAGNOSTIC in --smoke --autoplay --shop-preview --benchmark --capture-only; do
  "$BROXY_ROOT/tools/run.sh" --headless --script res://tests/test_profile_modes.gd -- "$BROXY_DIAGNOSTIC"
done
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/broxy-pycache" python3 -m unittest discover -s "$BROXY_ROOT/tests" -p 'test_shop_analysis.py'
