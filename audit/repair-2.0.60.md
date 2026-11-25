# 2.0.60 repair review

Baseline: `93c9c8006980403d6015133a40cfd7bb490189ad` (2.0.59).
This revision changes only the reviewed runtime seams, installer lifecycle,
deployment/diagnostic metadata and their regression/CI gates. It does not edit
the frozen core, Orion input, assets, preference UI, gesture math, dock queues,
bridge assembly or original spring implementation.

## Approved changes

- Seed absent preferences through a root-private temporary directory, with all
  content and metadata complete before an atomic, no-clobber hard-link publish.
  Pin and validate the destination directory; do not `defaults write` over an
  existing custom domain. Preserve existing bytes and metadata. Failure and
  cross-volume publication remain fail-closed; no cp/mv fallback.
- Source-control the formerly inherited `postrm`; ignore upgrade/abort phases.
  On remove/purge, restore only permitted legacy quarantine paths, without
  replacing an existing entry. Keep ledger and quarantine copies for retry.
- Match package firmware lower bound to the actual maximum Mach-O minimum,
  iOS 16.1; no assertion of iOS 16.0 support for frozen binaries.
- Enforce Inject at chooser admission, queued execution, opening, selection,
  and native launch. Observed disable cancels in-flight selection, using the
  existing animated close and retaining generation/identity guards.
- Enter the existing `STHCenterRunAnimation(...,0)` for both delayed keyboard
  shorter-frame commits. Keep the original delays, geometry, curves and native
  bridge. New same-frame confirmation invalidates an older pending shrink.
- Disarm and forget process-wide card bounds when multiple same-display scenes
  are positively ambiguous. Only transient absence may reuse unique-scene
  evidence; heartbeat renewal cannot pass its 60-second absolute deadline.
- Derive diagnostic declarations from the actual compile-time switch, default
  off. Record version and source SHA in the manifest.
- Verify all 21 final native tail stubs from real exported addresses, their
  core-base load, independent target RVAs, exact tail BR instruction and the
  companion core's executable PACIBSP entry. Mutations exist only in RAM.

## Regression evidence and boundaries

Local Linux verification before CI:

- 32 Python files parsed successfully.
- 6 preference-preservation tests passed, no skips.
- 20 install/uninstall lifecycle tests passed, no skips. Real temporary storage
  permits actual symlink, directory replacement and no-clobber race fixtures.
- Contract/frozen-base/asset checks passed; portable C scene policy executed.
- Parser self-test: 21 entries, 231 ABI corruptions rejected for each forward
  and backward ADRP layout, plus 29 malformed-input cases.
- Objective-C/Swift source extraction checks passed on Linux. Native Foundation
  and Swift execution is deliberately REQUIRED in macOS CI, not claimed local.

CI retains the prior tests and adds native chooser/scenes/UI positive/negative
execution, isolated delayed transaction cases, exact original Host negative
controls, installer lifecycle tests and final artifact policy/signature checks.
The original callback negative must compile and abort at the transaction-depth
marker for the named branch; a compiler error or arbitrary nonzero exit is not
accepted as evidence. Original baseline commit is fetched explicitly.

`inputs/reviewed-runtime-2.0.33.json` is not rewritten. A separate versioned lock
records exact approved changes with prior hashes; unrelated baseline entries
retain their original digests. A checksum update alone is not a device test.

## Conditional startup risk

No readiness retry change is made: frozen Stheno strongly links its actions
library; supported dyld dependency mapping precedes constructors and the main
queue installation. The reported two-second retry is not itself proof of a
missing supported load path. No permanent polling is introduced.

## Device validation

No device test was run. The manifest remains `device_tested:false`. Real iOS
spring rendering, keyboard/focus transitions, multi-scene timing and root/mobile
ownership should be tested after installation. Do not clear user preferences or
widget configuration. Restart/reload the tweak and reopen test applications so
old injected code is not confused with this build.
