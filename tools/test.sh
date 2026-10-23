#!/bin/sh
set -eu
BROXY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for BROXY_SUITE in rules purchase_query combat homing ui notifications modal choice_actions upgrade_previews shop_actions shop_details shop_availability profile_modes flow feedback impact_feedback projectile_painter enemy_telegraphs simulation_shop content_expansion content_presentation relic_preview relic_comparison trail_readability rune_equip_preview rune_equip_comparison enemy_hit_style shop_locks shop_lock_ui shop_lock_flow return_ring return_ring_ui return_ring_presentation projectile_capacity benchmark_seed; do
  "$BROXY_ROOT/tools/run.sh" --headless --script "res://tests/test_$BROXY_SUITE.gd"
done
for BROXY_DIAGNOSTIC in --smoke --autoplay --shop-preview --benchmark --capture-only; do
  "$BROXY_ROOT/tools/run.sh" --headless --script res://tests/test_profile_modes.gd -- "$BROXY_DIAGNOSTIC"
done
if [ -n "${BROXY_PYTHON:-}" ]; then
  BROXY_PYTHON_BIN=$BROXY_PYTHON
elif command -v python3 >/dev/null 2>&1; then
  BROXY_PYTHON_BIN=python3
else
  BROXY_PYTHON_BIN=python
fi
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/broxy-pycache" "$BROXY_PYTHON_BIN" -m unittest discover -s "$BROXY_ROOT/tests" -p 'test_*.py'
