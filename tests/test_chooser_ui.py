"""Extract production panel methods; execute Swift fakes on macOS, not UIKit.

Use --require-native in CI so a missing compiler cannot silently skip execution.
No animation curve is substituted: the fake records the native mode only.
"""
from pathlib import Path
import argparse
import resource
import tempfile
from test_chooser_runtime import R, SWIFT, function, checked_run, native_available

SIGNATURES = ('@objc func tick()', 'func selectCenter()', 'func openPanel()',
              'func closePanel(selecting id: String?)', 'func hidePanel()')

CASES = r'''
func fixture() -> CenterController {
    enabled = true; systemBlocked = false; clock = 10
    rows = [["identifier": "free.app", "name": "Free"]]
    disableInSnapshot = false; snapshotReads = 0; windowsCreated = 0
    animations = []; launched = []; centerSubmits = 0
    dismissals = 0; quickHides = 0; inputOpens = 0
    DispatchQueue.jobs = []
    let c = CenterController(), scene = Scene(), target = UIWindow()
    target.windowScene = scene; target.isKeyWindow = true; scene.windows = [target]
    c.targetWindow = target
    return c
}
func opened() -> CenterController {
    let c = fixture(); c.openPanel(); DispatchQueue.drain()
    precondition(c.panelWindow != nil && c.panelState?.visible == true && inputOpens == 1)
    precondition(animations == [0])
    return c
}
func unchangedLaunchCounters() {
    precondition(launched.isEmpty && dismissals == 0 && quickHides == 0)
}
let scenario = CommandLine.arguments[1]
switch scenario {
case "disabled-open":
    let c = fixture(); enabled = false; c.selectCenter(); c.openPanel()
    precondition(centerSubmits == 0 && windowsCreated == 0 && snapshotReads == 0)
case "disable-in-snapshot":
    let c = fixture(); disableInSnapshot = true; c.openPanel(); DispatchQueue.drain()
    precondition(windowsCreated == 0 && inputOpens == 0)
case "disable-before-open-completion":
    let c = fixture(); c.openPanel(); let window = c.panelWindow!
    enabled = false; DispatchQueue.next()
    precondition(inputOpens == 0 && c.panelWindow === window && animations == [1])
    DispatchQueue.drain(); precondition(c.panelWindow == nil); unchangedLaunchCounters()
case "disabled-tick-natural-close":
    let c = opened(); let window = c.panelWindow!
    enabled = false; c.tick()
    precondition(c.panelWindow === window && c.panelState?.visible == false)
    precondition(animations == [0, 1] && c.panelInput?.closing == true)
    c.tick(); precondition(animations == [0, 1]) // Repeated ticks do not restart the spring.
    DispatchQueue.drain(); precondition(c.panelWindow == nil); unchangedLaunchCounters()
case "disable-at-selection":
    let c = opened(); enabled = false; c.closePanel(selecting: "free.app")
    precondition(c.panelWindow != nil && animations == [0, 1])
    enabled = true; DispatchQueue.drain(); unchangedLaunchCounters()
case "disable-before-selection-completion":
    let c = opened(); c.closePanel(selecting: "free.app"); enabled = false
    DispatchQueue.drain(); precondition(c.panelWindow == nil); unchangedLaunchCounters()
case "disable-reenable-during-collapse":
    let c = opened(); c.closePanel(selecting: "free.app")
    enabled = false; c.tick(); enabled = true
    DispatchQueue.drain(); unchangedLaunchCounters()
case "retry-disabled":
    let c = fixture(); rows = nil; c.openPanel(); precondition(DispatchQueue.jobs.count == 1)
    enabled = false; rows = [["identifier": "free.app", "name": "Free"]]
    DispatchQueue.drain(); precondition(windowsCreated == 0 && inputOpens == 0)
case "stale-open-completion":
    let c = fixture(); c.openPanel(); c.hidePanel(); c.openPanel()
    let current = c.panelWindow!
    DispatchQueue.next(); precondition(c.panelWindow === current && inputOpens == 0)
    DispatchQueue.drain(); precondition(c.panelWindow === current && inputOpens == 1 && animations == [0])
case "stale-selection-completion":
    let c = opened(); c.closePanel(selecting: "old.app"); c.hidePanel(); c.openPanel()
    let current = c.panelWindow!
    DispatchQueue.drain(); precondition(c.panelWindow === current && c.panelState?.visible == true)
    unchangedLaunchCounters()
case "reopen-after-disabled-close":
    let c = opened(); enabled = false; c.tick(); DispatchQueue.drain(); enabled = true
    c.openPanel(); DispatchQueue.drain(); c.closePanel(selecting: "free.app"); DispatchQueue.drain()
    precondition(launched == ["free.app"] && animations == [0, 1, 0, 1])
case "positive-select":
    let c = opened(); let target = c.targetWindow!
    c.closePanel(selecting: "free.app"); precondition(launched.isEmpty && animations == [0, 1])
    DispatchQueue.drain(); precondition(launched == ["free.app"] && dismissals == 1 && quickHides == 1)
    precondition(c.panelWindow == nil && target.isKeyWindow && abs(clock - 10.15) < 0.000001)
case "positive-cancel":
    let c = opened(); c.closePanel(selecting: nil); DispatchQueue.drain()
    precondition(c.panelWindow == nil && animations == [0, 1]); unchangedLaunchCounters()
case "positive-center":
    let c = fixture(); c.selectCenter(); precondition(centerSubmits == 1)
case "system-blocked":
    let c = opened(); c.closePanel(selecting: "free.app"); systemBlocked = true
    DispatchQueue.drain(); unchangedLaunchCounters()
case "system-blocked-tick":
    let c = opened(); systemBlocked = true; c.tick()
    precondition(c.panelWindow == nil); unchangedLaunchCounters()
case "retry-positive":
    let c = fixture(); rows = nil; c.openPanel(); rows = [["identifier": "free.app", "name": "Free"]]
    DispatchQueue.drain(); precondition(c.panelWindow != nil && inputOpens == 1)
case "retry-exhaustion":
    let c = fixture(); rows = nil; c.openPanel(); DispatchQueue.drain()
    precondition(c.panelWindow == nil && snapshotReads == 6 && windowsCreated == 0)
default: fatalError("Unknown scenario: \(scenario)")
}
print("Production Swift chooser: \(scenario) passed")
'''

SCENARIOS = (
    'disabled-open', 'disable-in-snapshot', 'disable-before-open-completion',
    'disabled-tick-natural-close', 'disable-at-selection',
    'disable-before-selection-completion', 'disable-reenable-during-collapse',
    'retry-disabled', 'stale-open-completion', 'stale-selection-completion',
    'reopen-after-disabled-close', 'positive-select', 'positive-cancel',
    'positive-center', 'system-blocked', 'system-blocked-tick',
    'retry-positive', 'retry-exhaustion',
)


def source_checks(source):
    methods = {signature: function(source, signature) for signature in SIGNATURES}
    assert len(methods) == 5
    tick = methods[SIGNATURES[0]]
    assert 'else if !enabled { closePanel(selecting: nil) }' in tick
    close = methods[SIGNATURES[3]]
    assert close.index('panelSelectionCancelled = true') < close.index('panelInput?.closing == false')
    assert 'let selected = self.panelSelectionCancelled ? nil : id' in close
    assert 'if let id = selected, STHSystemActionsEnabled(), !STHSystemUIBlocked()' in close
    assert 'STHCenterRunAnimation({ motion.visible = false }, 1)' in close
    assert '.now() + 0.15' in close
    assert 'self.panelState === motion, self.presentationGeneration == generation' in close
    opening = methods[SIGNATURES[2]]
    assert opening.count('STHSystemActionsEnabled()') == 4
    assert 'STHCenterRunAnimation({ motion.visible = true }, 0)' in opening
    assert 'self.presentationGeneration == generation, self.panelState === motion' in opening
    assert '.animation(.spring(response: 0.34, dampingFraction: 0.88), value: motion.visible)' in source
    assert '__METHODS__' in SWIFT and 'case "positive-select"' in CASES
    print('Chooser UI extraction/gates/original animation source checks passed')


def swift_program(source):
    methods = '\n'.join(function(source, signature) for signature in SIGNATURES)
    return SWIFT.replace('__METHODS__', methods) + CASES


def native_checks(directory, source):
    def compile_program(name, implementation):
        path = directory / f'{name}.swift'
        executable = directory / name
        path.write_text(swift_program(implementation))
        checked_run(['xcrun', 'swiftc', str(path), '-o', str(executable)])
        return executable
    executable = compile_program('chooser-ui', source)
    for scenario in SCENARIOS:
        checked_run([str(executable), scenario])
        print(f'chooser-ui {scenario}: passed')
    # Each mutation must compile and fail an executed assertion, not merely a scan.
    controls = (
        ('no-open-gate', source.replace('guard STHSystemActionsEnabled(), panelWindow == nil', 'guard panelWindow == nil'), 'disabled-open'),
        ('no-async-open-gate', source.replace('guard STHSystemActionsEnabled() else { self.closePanel(selecting: nil); return }', ''), 'disable-before-open-completion'),
        ('no-selection-completion-gate', source.replace('if let id = selected, STHSystemActionsEnabled(), !STHSystemUIBlocked()', 'if let id = selected, !STHSystemUIBlocked()'), 'disable-before-selection-completion'),
        ('no-cancellation-latch', source.replace('if !STHSystemActionsEnabled() { panelSelectionCancelled = true }', ''), 'disable-reenable-during-collapse'),
        ('no-close-generation-check', source.replace('guard self.panelState === motion, self.presentationGeneration == generation else { return }', ''), 'stale-selection-completion'),
    )
    for name, implementation, scenario in controls:
        assert implementation != source, name
        executable = compile_program(name, implementation)
        checked_run([str(executable), scenario], should_fail=True)
        print(f'chooser-ui negative {name}: assertion failed as expected')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-native', action='store_true')
    args = parser.parse_args()
    source = (R / 'CenterChooser.swift').read_text()
    source_checks(source)
    if not native_available():
        if args.require_native:
            raise SystemExit('Native chooser UI tests require macOS xcrun/swiftc/Foundation')
        print('SKIP Swift execution: macOS xcrun/swiftc/Foundation unavailable')
        return
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='stheno-chooser-ui-') as directory:
        native_checks(Path(directory), source)


if __name__ == '__main__':
    main()
