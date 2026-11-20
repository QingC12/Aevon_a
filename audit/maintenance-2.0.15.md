# stheno 2.0.15 — source cleanup and package maintenance

## Precisely removed

- `ci-gesture/GestureRules.h`, `test_gesture_rules.c`: obsolete hold-to-close placeholders (two comment lines and one comment line in the 2.0.14 baseline). They contained no active implementation and were not included by the production build or workflow. Current yellow-zone release remains routed to the original native edge-middle gesture class/threshold.
- `ci-gesture/KeyboardInsetMath.h`, `test_keyboard_inset.c`: the pre-scene app/window intersection-reduction formula. `KeyboardInset.m` no longer calls this function; the header's include was its only production reference, and CI no longer invokes its obsolete test. Current paths use scene-only canonical occlusion, physical-card mapping and the selected keyboard-plane policy.
- `ci-gesture/EditorVisibility.m`: a superseded per-app-helper implementation. It was not among either production helper's compiler source arguments. The shared `EditorVisibilityMath.h` remains included by `EditorAssembly.h` and is still used.
- Unused Python `sys` and `shutil` imports in `build.py`, based on AST name-use scan; generated `__pycache__`, `.pyc`, `build/`, object and dSYM outputs are now ignored.
- Removed the unreferenced `_STHNativeAnimatePhysicalKeyboard` bridge from `native.S` and the test-only `STHKeyboardCenterDelta` formula from `KeyboardGeometry.h`. Their declarations/callers were absent from the production closure. Other tuple-scale wrappers were already absent. Active scale/offset/geometry, lifecycle, animation-entry and gesture bridges remain.
- One-off patch-authoring scripts in the analysis workspace. They generated already-committed source changes but are not required by build or runtime.

These removed source files were committed as deletions from the private source repository. No original toggle, UI label/resource, default bit, hook, tweak bundle, install/uninstall script, or plist entry is removed.

## Kept because live or required for audit

- `LayoutProbe.m/h` has both a SpringBoard observer and an application reporter reachable from `CompositeRows.inc`; it remains useful to identify an existing private control by class name and geometry without inspecting text.
- `NotificationPolicy.m` remains a read-only diagnostic for the unresolved foreground-notification sound report; it does not change a setting or play/mute audio.
- The various per-app editor profiles, native keyboard measurements, cross-process layout bus, and QQ/Minis/WeChat compatibility path are all referenced by the explicit helper build source list.
- All settings bundles, strings, original binary functionality switches and inherited install scripts remain byte-for-byte preserved from the pinned base rows/control archive. `test_maintenance_contract.py` verifies this for the DEB before upload.

## Size optimization

`build.py` still creates the same deterministic GNU TAR rows. It recompresses only the resulting data TAR with standard XZ/LZMA2 parameters `preset=6, lc=0, lp=2, pb=2` and asserts `lzma.decompress(optimized)==originalTar` before assembling the DEB. On the 2.0.14 payload this saved 5,428 bytes (1.16% of the overall DEB). The final 2.0.15 size and saving must be taken from its own completed build manifest. The manifest records compressed default/optimized data-archive lengths and the identical uncompressed TAR length and SHA-256. This is a container-size optimization only: no installed file content/mode/permissions or Mach-O code page changes because of compression.

The larger private runtime and proprietary Stheno core contain required symbols and Objective-C/Swift metadata. Stripping or rewriting them was deliberately avoided. Additional native dead-stripping would need a per-target linker map, export comparison and device regression; it is not claimed safe here.

## Global audit result and risk

All user-facing feature toggles remain. No menu control is hidden, no mask bit is changed and no behavior is forcibly disabled. The static audit did find a pre-existing installer risk: `postinst` can copy the complete preference template under its fallback rules, potentially resetting user mask/app preferences. It has not been changed; treat a future preference migration/merge as its own backed-up, user-reviewed update.

Final acceptance completed: CI run `44666083190` on commit `9b4c8008f2a68728ccb2610cb66302a2e50e34e5` passed every step; artifact `14598230183` was downloaded and independently verified with `verify_gesture_deb.py`. All 11 arm64e binaries have valid code-page hashes, all 79 private Orion imports resolve, the license is retained and no external Orion package is required. The actual DEB also passes the local maintenance test. Compared directly with the delivered 2.0.14, all entry paths and TAR metadata are unchanged and 30 of the 31 regular files are byte-identical, including `SthenoKeyboardInset.dylib`, `Stheno.dylib`, `SthenoKeyboard.dylib`, private Orion and all settings resources. Only `SthenoGesture.dylib` changes (144144 to 144064 bytes). Final DEB: 463620 bytes, SHA-256 `7162b1f6d7558865d03cb37e743860acd51ae0be9d9407e5226da948ebf0784a`; net reduction vs 2.0.14: 5524 bytes. XZ alone saves 5432 bytes on this build's payload.

No installation script is run by CI or this audit. These are static/host build checks, not true iOS device validation. This maintenance release does not claim fixes to the frozen residual keyboard behavior or intermittent notification sound.
