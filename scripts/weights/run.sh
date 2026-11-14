#!/usr/bin/env bash
# Level 60 stat weights for every talent tree wowsims/forever sims.
#
#   bash run.sh <checkout of github.com/wowsims/forever at the commit in PIN> [all|base|b]
#
#   base  the first pass: every stat around the preset baseline, to out/parts and out/weights-60.json
#   b     the second pass over the first pass's out/parts: hit and expertise a step below the baseline (below
#         the hit caps) for every tree, and threat, damage taken and TMI per stat for the tanks, to
#         out/parts-60b and out/weights-60b.json; weights-60.json is left as it is
#   all   both, in that order (the default)
#
# Needs go (the version the checkout's go.mod names), protoc and protoc-gen-go on the PATH, as the engine's own
# build does. W60_ENV may name a file to source first, for a toolchain that is not on the PATH.
# W60_ONLY=<part of class-tree, such as warrior-fury> runs only the trees that match and keeps the other parts.
# W60_EPCI (0.03) is the 90% interval each DPS EP is run down to, W60_SEED (60) the random seed.
# Pass b: W60B_TANK_EPCI (0.05) is the interval of the tank metrics, W60B_CAP_TANK (300000) and W60B_CAP_BELOW
# (600000) the most iterations a side may take there (a tree's own IterationCap wins).
#
# The harness is copied into the checkout because the spec packages keep their suite configs in test files:
# harness/sim/weights60 (the runner and the merge command) and one weights60_test.go per spec package.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${W60_ENV:-}" ]; then
	. "$W60_ENV"
fi
REPO="$(cd "${1:?usage: run.sh <checkout of wowsims/forever> [all|base|b]}" && pwd)"
PASS="${2:-all}"
case "$PASS" in all | base | b) ;; *)
	echo "the pass is all, base or b" >&2
	exit 1
	;;
esac

PIN="$(tr -d '[:space:]' < "$HERE/PIN")"
HEAD="$(git -C "$REPO" rev-parse HEAD)"
if [ "$HEAD" != "$PIN" ]; then
	echo "the checkout is at $HEAD, and the harness is written against $PIN (PIN)" >&2
	exit 1
fi
COMMIT_DATE="$(git -C "$REPO" log -1 --format=%cI)"

mkdir -p "$HERE/out"
# A path the go tool reads on Windows too.
OUT="$(cd "$HERE/out" && (pwd -W 2>/dev/null || pwd))"

cp -r "$HERE/harness/." "$REPO/"
cd "$REPO"
if [ ! -f sim/core/proto/api.pb.go ]; then
	protoc -I=./proto \
		--go_opt=Mgoogle/protobuf/descriptor.proto=google.golang.org/protobuf/types/descriptorpb \
		--go_out=./sim/core ./proto/*.proto
fi

PACKAGES=(./sim/paladin/retribution ./sim/paladin/protection ./sim/warrior/dps ./sim/warrior/protection ./sim/rogue
	./sim/hunter ./sim/mage ./sim/warlock ./sim/priest ./sim/shaman/elemental ./sim/shaman/enhancement
	./sim/druid/balance ./sim/druid/feralcat ./sim/druid/feralbear)

# run_pass <pass> <log>
run_pass() {
	local status=0
	W60_PASS="$1" W60_OUT="$OUT" go test --tags=with_db -v -p 1 -count=1 -timeout 0 -run 'TestWeights60$' \
		"${PACKAGES[@]}" > "$2" 2>&1 || status=$?
	grep -E '^(W60B? |--- FAIL|FAIL|ok |panic)' "$2" || true
	if [ "$status" -ne 0 ]; then
		echo "go test failed; see $2" >&2
		exit "$status"
	fi
}

if [ "$PASS" = all ] || [ "$PASS" = base ]; then
	if [ -z "${W60_ONLY:-}" ]; then
		rm -rf "$HERE/out/parts"
	fi
	run_pass base "$HERE/out/run.log"
	go run ./sim/weights60/merge -parts "$OUT/parts" -out "$OUT/weights-60.json" -commit "$HEAD" -commitDate "$COMMIT_DATE"
fi

if [ "$PASS" = all ] || [ "$PASS" = b ]; then
	if [ ! -d "$HERE/out/parts" ]; then
		echo "pass b reads the first pass's out/parts; run the base pass first" >&2
		exit 1
	fi
	if [ -z "${W60_ONLY:-}" ]; then
		rm -rf "$HERE/out/parts-60b"
	fi
	run_pass b "$HERE/out/run-60b.log"
	go run ./sim/weights60/merge -parts "$OUT/parts-60b" -out "$OUT/weights-60b.json" -commit "$HEAD" -commitDate "$COMMIT_DATE" -variant b
fi
