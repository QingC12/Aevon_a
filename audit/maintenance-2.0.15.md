# stheno 2.0.15 — source cleanup and package maintenance

## Precisely removed

- `ci-gesture/GestureRules.h`, `test_gesture_rules.c`: the old experimental stationary-hold plus 24pt directional-close logic. Current yellow-zone release is routed to the original native edge-middle gesture class/threshold. Neither removed file was included by `build.py`, `.github/workflows/build.yml`, or any source include.
- `ci-gesture/KeyboardInsetMath.h`, `test_keyboard_inset.c`: the pre-scene app/window intersection-reduction formula. `KeyboardInset.m` no longer calls this function; the header's include was its only production reference, and CI no longer invokes its obsolete test. Current paths use scene-only canonical occlusion, physical-card mapping and the selected keyboard-plane policy.
- `ci-gesture/EditorVisibility.m`: a superseded per-app-helper implementation. It was not among either production helper's compiler source arguments. The shared `EditorVisibilityMath.h` remains included by `EditorAssembly.h` and is still used.
- Unused Python `sys` and `shutil` imports in `build.py`, based on AST name-use scan; generated `__pycache__`, `.pyc`, `build/`, object and dSYM outputs are now ignored.
- The source audit confirmed that tuple-scale getters/setters and the superseded second keyboard-animation bridge are not referenced by the current production source and are absent from `native.S`; this release makes no new native-bridge deletion beyond confirming them out of the active source closure.
- One-off patch-authoring scripts in the analysis workspace. They generated already-committed source changes but are not required by build or runtime.

These removed source files were committed as deletions from the private source repository. No original toggle, UI label/resource, default bit, hook, tweak bundle, install/uninstall script, or plist entry is removed.

## Kept because live or required for audit

- `LayoutProbe.m/h` has both a SpringBoard observer and an application reporter reachable from `CompositeRows.inc`; it remains useful to identify an existing private control by class name and geometry without inspecting text.
- `NotificationPolicy.m` remains a read-only diagnostic for the unresolved foreground-notification sound report; it does not change a setting or play/mute audio.
- The various per-app editor profiles, native keyboard measurements, cross-process layout bus, and QQ/Minis/WeChat compatibility path are all referenced by the explicit helper build source list.
- All settings bundles, strings, original binary functionality switches and inherited install scripts remain byte-for-byte preserved from the pinned base rows/control archive. `test_maintenance_contract.py` verifies this for the DEB before upload.

## Size optimization

`build.py` still creates the same deterministic GNU TAR rows. It recompresses only the resulting data TAR with standard XZ/LZMA2 parameters `preset=6, lc=0, lp=2, pb=2` and asserts `lzma.decompress(optimized)==originalTar` before assembling the DEB. On the last payload it saved5,428 bytes (1.16%) from the overall DEB. The built manifest records compressed default/optimized data-archive lengths and the identical uncompressed TAR length. This is a container-size optimization only: no installed file content/mode/permissions or Mach-O code page changes because of compression.

The larger private runtime and proprietary Stheno core contain required symbols and Objective-C/Swift metadata. Stripping or rewriting them was deliberately avoided. Additional native dead-stripping would need a per-target linker map, export comparison and device regression; it is not claimed safe here.

## Global audit result and risk

All user-facing feature toggles remain. No menu control is hidden, no mask bit is changed and no behavior is forcibly disabled. The static audit did find a pre-existing installer risk: `postinst` can copy the complete preference template under its fallback rules, potentially resetting user mask/app preferences. It has not been changed; treat a future preference migration/merge as its own backed-up, user-reviewed update.

Build CI and `verify_gesture_deb.py` confirm the package remains arm64e-only and signed, includes the private Orion 1.0.2 runtime and license, omits an external Orion package dependency, and contains no source, test, analysis log or Python cache files. No installation script is run by CI or this audit. Host geometry tests validate the source contracts, not real iOS behavior.
