#!/usr/bin/env bash
# Records every trailer take in a row (see record.sh). Takes a while: ~10-25 min each.
set -uo pipefail
cd "$(dirname "$0")/../.."
tools/trailer/record.sh opening
tools/trailer/record.sh turret_toss
tools/trailer/record.sh turret_toss toss=20
tools/trailer/record.sh playground
tools/trailer/record.sh playground cam=chase
tools/trailer/record.sh column
tools/trailer/record.sh column cam=drone
tools/trailer/record.sh ambush
tools/trailer/record.sh ambush cam=wide
tools/trailer/record.sh smoke
tools/trailer/record.sh kv2_plow
tools/trailer/record.sh kv2_plow end=kv
tools/trailer/record.sh advance
tools/trailer/record.sh advance cam=drone
