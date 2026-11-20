# Stheno 2.0.15 global function-toggle and installer audit

## Scope and limits

Read-only review of the pinned original arm64e package, its arm64/arm64e disassemblies/localizations, current explicit helper-build closure, packaging scripts, and toggle-preservation tests. No plugin, install/uninstall script or device preference was executed or modified. The repository does not contain the original full Swift project; if a UI row→stored value→every consumer chain is incomplete, it is marked unresolved rather than guessed. No user-specific live plist is present.

## Feature-toggle integrity

The default template is `usr/local/share/stheno/com.nx.stheno.plist` inside the DEB.

| Setting | Stored default | Static code finding |
|---|---:|---|
| `Inject` | true, separate Boolean | Main image checks before Orion activation; camera/keyboard companions also read it and default true if absent. Exact refresh timing across all processes is not fully proven. |
| `StatusBarGroup` | true, separate Boolean | Template and compiled storage agree; status-bar hook exists. Full localization-to-binding-to-consumer chain not closed. |
| `SettingMask` | 1585815 / `0x183297` | Template agrees with main-image fallback. Set bits:0,1,2,4,7,9,12,13,19,20. Native setters found for some branches preserve other bits via read-modify-write. |
| `ForegroundNotify` | bit27 off in shipped template | Original arm64e notification-server hook conditionally changes foreground classification for floated apps. This is not an audio mute function and the template does not reveal the user's current saved value. |
| `FrontmostNotify` | bit28 off in shipped template | Separate UI/mask bit and runtime branch; full downstream presentation semantics remain partly unresolved. |
| Camera behavior | bit6 off | SthenoCamera and CameraFix both match `mediaserverd`; CameraFix has a permissive fallback branch. Hook interaction/order and complete UI mapping not established. |
| SafariViewService | bit25 off | Companion has a matching hook and reads the bit. Exact label/binding polarity not fully proven. |
| UIKit/keyboard/Universal Links | bits10,31,35 off in default | SthenoKeyboard reads these and provides keyboard/scene/URL paths. Complete one-to-one UI-key mapping and precedence are not recoverable from supplied artifacts. |
| Per-app `Apps` / `PerAppData` | empty string / separate plist | Original main and keyboard components read per-app values. The full editor→serialization→reload chain remains partly unresolved. |

Additional localized options—`BlockInterceptor` (a grouping label), `SSInterceptor`, `SSInterceptorSilence`, `SSListen`, Safari/Universal Link options, and several gesture/window options—remain present. Localized labels alone do not prove that a particular mask bit exclusively controls a hook. No option was deleted, hidden, flipped or hardwired in 2.0.15. `test_maintenance_contract.py` compares the original template, PreferenceBundle UI resources and app-support localization files byte-for-byte, and checks the shipped default mask.

## Existing installer finding — left unchanged

The inherited `control/postinst` selects a template and may copy the complete preferences plist to a target if its activation-content/size guard fails. Under that path, saved `SettingMask`, `Apps`, or other preferences may be reset; the subsequent defaults writes only address selected keys and are not a general merge. It also stops matching `cfprefsd` processes. `postrm` leaves the main plist but has overwrite-capable restoration of `.stheno-off` backups. These are concrete audit risks, not new regressions and not changed by this cleanup. Fixing them needs a separate backup-and-merge migration with upgrade/uninstall tests.

`SthenoCamera`/`CameraFix` overlap on `mediaserverd`, and `SthenoKeyboard`/`KeyboardFix` overlap on UIKit. Their filters, independent configuration reads and fallback paths exist in the pinned base; coexistence behavior is environment/load-order dependent. The original scripts and component filters were preserved byte-for-byte. The new helper builds after those base images and does not replace their preference behavior.

## Confirmed dead-source cleanup

Removed source outside the production compiler closure, together with its obsolete CI-only checks:

- `GestureRules.h` and `test_gesture_rules.c`: obsolete comment-only hold-to-close placeholders already containing no implementation in 2.0.14; the current native edge-middle release path is retained.
- `KeyboardInsetMath.h` and `test_keyboard_inset.c`: obsolete window-relative old-inset reduction formula. No current production caller remained; current scene-only, physical-plane, and input-assembly tests remain.
- `EditorVisibility.m`: superseded uncompiled implementation. `EditorVisibilityMath.h` is not removed because `EditorAssembly.h`, `EditorRefinement.h`, and active tests use it.
- Unused Python `sys`/`shutil` imports and generated Python caches/one-off analysis scripts.

This release removes the unreferenced `_STHNativeAnimatePhysicalKeyboard` bridge and test-only `STHKeyboardCenterDelta` formula. Tuple-array wrappers were already absent. Active `STHNativeGetScale`, `STHNativeGetOffset`, geometry setter, keyboard notification, first-presentation, native animation entry and gesture bridges remain. `LayoutProbe` is still called by the composite row scan and consumed by the SpringBoard diagnostic receiver, so it is not dead. `NotificationPolicy` is constructor-reachable and deliberately retained as read-only. Current-production regression tests and all setting controls/resources remain.

## DEB size and exact payload

2.0.15 re-compresses only `data.tar.xz` using deterministic LZMA2 parameters. Builder and maintenance CI decompress the optimized archive and assert that its entire GNU TAR byte stream is identical to the default-compressed stream. On the preceding payload this reduces the data archive from 465,936 to 460,508 bytes, saving **5,428 bytes** (~1.16% of the DEB), with every installed file unchanged. No symbols, code sections, assets, preferences, license or runtime components were stripped.

The installed DEB payload is separately enumerated by `build.py`; workspace `ci-artifacts`, input archives, disassembly, tests, caches and reports are not included. The core's 79 Orion imports remain resolved by the private runtime. Ad-hoc signature/`__LINKEDIT` metadata can vary by macOS signing host; code-page hashes and original instructions are checked independently.

## Future options

Further code-size reduction inside the native helpers is deliberately deferred: they share SpringBoard and app-side bus/probe symbols, and Objective-C/Swift metadata, constructors and Orion hooks are runtime roots. Only a link map plus per-binary export/call-graph verification and device regression could establish safe dead stripping. No proprietary main-binary feature toggle or inherited switch was removed here.
