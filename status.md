# RAWCamera Build Status

_Source of truth (hand-maintained; `ecc` CLI not present). Updated between phases._

**Phase-0 commit:** `0c3c324` (tag `phase-0`) — all worktrees branch from here.
**Current phase:** ⛔ **Phase 4 — HARD STOP at the human device gate.** Tiers 0–2 green; integration merged. See DEVICE-CHECKLIST.md.

## Toolchain
| Tool | Status |
| --- | --- |
| Xcode 26.5 / Swift 6.3.2 | ✅ |
| Metal toolchain | ✅ installed |
| swiftlint 0.63.3 / swift-format 602 | ✅ |
| xcodegen 2.45.4 | ✅ |
| swift-reviewer agent | ✅ generated (`~/.claude/agents/swift-reviewer.md`) |

## Gate status @ phase-0
| Gate | State |
| --- | --- |
| T0-1 app compiles (iphoneos) | 🟢 |
| T0-2 metal shaders compile (+ static_assert) | 🟢 |
| T0-3 swiftlint --strict / swift-format lint | 🟢 |
| T1-6 contract conformance | 🟢 |
| T1-7 uniform ABI parity (Swift + Metal) | 🟢 |
| T1-1..T1-5 module unit tests | ⚪ stubs (workers implement) |
| T2-1 privacy keys | 🟢 |
| T2-2 no network/exfil | 🟢 |
| T2-3 no deprecated orientation API | 🟢 |
| T2-4 threading discipline | ⚪ reviewer gate (Phase 1+) |

## Worktree / PR queue
| Worktree | Branch | State | Tier-1 owned | Reviewer |
| --- | --- | --- | --- | --- |
| wt/capture | phase1/capture | ✅ merged (`f456534`) | T1-1, T1-2, T1-5 (59) | APPROVE (r2) |
| wt/metal | phase1/metal | ✅ merged (`0e9ddca`) | T1-3 (7) + T1-7 | APPROVE (r1) |
| wt/controls-ui | phase1/controls-ui | ✅ merged (`de704e2`) | none | APPROVE (r2) |
| wt/monitoring-ui | phase1/monitoring-ui | ✅ merged (`559c8a5`) | T1-4 (15) | APPROVE (r2) |
| wt/integration | phase2/integration | ✅ merged (`823540a`) | — | APPROVE |

Integrated main: **80 CameraCore tests green**, Tier 0–2 all green. Phase-3 grader
re-run on the merged branch: GREEN.

## Security gate (pre-Phase-4)
- Source scan: CLEAN — no networking/exfil, no secrets, privacy strings present+honest, no ATS bypass, no UserDefaults.
- AgentShield: no CRITICAL/HIGH; 1 MEDIUM + 1 LOW are about the local `.claude/settings.local.json` config (deny list / PreToolUse hook), not the app. **PASS.**

## Deferred MEDIUMs for integration to resolve (from Phase-1 reviews)
- **capture**: retain `PhotoCaptureProcessor` across the async Photos save (don't let it dealloc before `performChanges` completion, or `onCaptureFinished` is dropped).
- **metal**: `CVPixelBuffer` held past `onVideoFrame` via async upload (pool-stall risk) — consider sync texture upload; `HistogramProducer.onHistogram` → make `@MainActor` or lock.
- **wiring**: integration must pump `MotionManager.onAttitude` → model (roll/pitch/isLevel) on main; histogram producer → `model.histogram` on main; feed `CameraMetalView` uniforms (zebra/peaking thresholds, peakingColor, rotation, viewSize) from the model.

## Merge rule
A worktree merges only when: Tier 0 green AND its Tier 1 tests green AND
swift-reviewer APPROVES. `pass@3` before escalating a red gate to a human note here.

## Risk watch
- **#1 contract drift:** PreviewUniforms ABI — now guarded on both sides
  (T1-7 Swift + static_assert Metal). Re-check at integration.
- CameraModel monitoring-data writes land only at Phase 2 (integration owns the file).

## Log
- Phase 0 complete, committed `0c3c324`, tagged `phase-0`. Architect amendment A1 applied.
