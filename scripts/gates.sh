#!/usr/bin/env bash
# RAWCamera automated gate runner (Tier 0-2). Source of truth for the merge rule.
# Usage: scripts/gates.sh [tier0|tier1|tier2|all]
set -uo pipefail
export PATH="/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TIER="${1:-all}"
FAIL=0
pass() { printf "  \033[32m✔ %s\033[0m\n" "$1"; }
fail() { printf "  \033[31m✘ %s\033[0m\n" "$1"; FAIL=1; }

tier0() {
  echo "== Tier 0 — build gates =="
  # Regenerate the Xcode project from project.yml (xcodeproj is gitignored).
  xcodegen generate >/tmp/t0gen.log 2>&1 || { fail "xcodegen generate FAILED"; tail -5 /tmp/t0gen.log; }
  # T0-1 app compiles for device SDK
  if xcodebuild -scheme RAWCamera -sdk iphoneos -destination 'generic/platform=iOS' \
       -derivedDataPath .build-xc CODE_SIGNING_ALLOWED=NO build >/tmp/t01.log 2>&1; then
    pass "T0-1 app compiles (iphoneos)"
  else
    fail "T0-1 app compile FAILED (see /tmp/t01.log)"; tail -5 /tmp/t01.log
  fi
  # T0-2 metal shaders compile
  if xcrun -sdk iphoneos metal -c App/Monitoring/CameraShaders.metal -o /dev/null >/tmp/t02.log 2>&1; then
    pass "T0-2 metal shaders compile"
  else
    fail "T0-2 metal compile FAILED (see /tmp/t02.log)"; tail -5 /tmp/t02.log
  fi
  # T0-3 lint/format
  if swiftlint --strict --quiet >/tmp/t03a.log 2>&1; then
    pass "T0-3a swiftlint --strict clean"
  else
    fail "T0-3a swiftlint --strict FAILED (see /tmp/t03a.log)"; tail -15 /tmp/t03a.log
  fi
  if swift-format lint --strict --recursive App CameraCore/Sources CameraCore/Tests >/tmp/t03b.log 2>&1; then
    pass "T0-3b swift-format lint clean"
  else
    fail "T0-3b swift-format lint FAILED (see /tmp/t03b.log)"; tail -15 /tmp/t03b.log
  fi
}

tier1() {
  echo "== Tier 1 — CameraCore unit tests =="
  if (cd CameraCore && swift test >/tmp/t1.log 2>&1); then
    pass "T1 CameraCore tests (T1-1..T1-7)"
    grep -E "Test run with|Suite .* passed" /tmp/t1.log | tail -3 | sed 's/^/    /'
  else
    fail "T1 CameraCore tests FAILED (see /tmp/t1.log)"; tail -20 /tmp/t1.log
  fi
}

tier2() {
  echo "== Tier 2 — static / structural =="
  # T2-1 privacy keys
  if grep -q NSCameraUsageDescription App/Info.plist && grep -q NSPhotoLibraryAddUsageDescription App/Info.plist; then
    pass "T2-1 privacy keys present"
  else
    fail "T2-1 privacy keys MISSING"
  fi
  # T2-2 no network / exfil
  if grep -rREn "URLSession|Network\.framework|import Network|CFSocket|analytics|Firebase|Mixpanel|Amplitude" App CameraCore/Sources >/tmp/t22.log 2>&1; then
    fail "T2-2 networking/exfil reference found:"; cat /tmp/t22.log | sed 's/^/    /'
  else
    pass "T2-2 no networking / exfil"
  fi
  # T2-3 no deprecated orientation API
  if grep -rREn "\.videoOrientation|AVCaptureVideoOrientation" App >/tmp/t23.log 2>&1; then
    fail "T2-3 deprecated videoOrientation API found:"; cat /tmp/t23.log | sed 's/^/    /'
  else
    pass "T2-3 uses videoRotationAngle (no deprecated orientation API)"
  fi
}

case "$TIER" in
  tier0) tier0 ;;
  tier1) tier1 ;;
  tier2) tier2 ;;
  all) tier0; tier1; tier2 ;;
  *) echo "unknown tier: $TIER"; exit 2 ;;
esac

echo
if [ "$FAIL" -eq 0 ]; then printf "\033[32mGATES GREEN\033[0m\n"; else printf "\033[31mGATES RED\033[0m\n"; fi
exit "$FAIL"
