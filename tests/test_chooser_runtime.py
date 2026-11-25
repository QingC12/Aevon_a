"""Compile production chooser entry/method bodies against deterministic fakes.

No hand-copied implementation: SystemActionPresent and the panel methods below
are extracted verbatim at test time. UIKit rendering is deliberately not tested;
queues, switch changes, native animation calls and final admissions are executed.
macOS: python3 tests/test_chooser_runtime.py --require-native
UI method execution: python3 tests/test_chooser_ui.py --require-native
Both scripts must be added explicitly to CI; source checks also run on Linux.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

R = Path(__file__).resolve().parent.parent


def function(source, signature):
    assert source.count(signature) == 1, ('ambiguous extraction', signature)
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end, state = 1, opening + 1, None
    while depth:
        if end >= len(source):
            raise AssertionError(('unterminated function', signature))
        pair, char = source[end:end + 2], source[end]
        if state == '//':
            if char == '\n': state = None
        elif state == '/*':
            if pair == '*/': state = None; end += 1
        elif state in ('"', "'"):
            if char == '\\': end += 1
            elif char == state: state = None
        elif pair in ('//', '/*'):
            state = pair; end += 1
        elif char in ('"', "'"):
            state = char
        else:
            depth += (char == '{') - (char == '}')
        end += 1
    return source[start:end].replace('@objc ', '')


OBJC = r'''
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "SystemActionCatalog.h"
#import "ChooserSelection.h"
#include <assert.h>
static BOOL enabled=YES,ready=YES;
static unsigned shown,actions;
static NSMutableArray *jobs;
BOOL STHSystemActionsEnabled(void){return enabled;}
BOOL STHSystemActionRuntimeReady(void){return ready;}
void *STHSystemCopyModelIdentifier(void *m){return (void *)CFRetain(m);}
void STHChooserShowFromNativeSelection(void){shown++;}
static void execute(STHSystemAction a){(void)a;actions++;}
static void enqueue(dispatch_queue_t q,dispatch_block_t b){(void)q;[jobs addObject:[b copy]];}
#define dispatch_async enqueue
__PRESENT__
static BOOL present(NSString *s){return STHSystemActionPresent((__bridge void *)s);}
static void drain(void){NSArray *batch=[jobs copy];[jobs removeAllObjects];for(dispatch_block_t b in batch)b();}
int main(void){@autoreleasepool{
 jobs=[NSMutableArray new];
 enabled=NO;assert(present(@STH_APP_CHOOSER_ID));assert(!jobs.count&&!shown);
 enabled=YES;assert(present(@STH_APP_CHOOSER_ID));assert(jobs.count==1);
 enabled=NO;drain();assert(!shown); // Disable after admission, before execution.
 enabled=YES;assert(present(@STH_APP_CHOOSER_ID));drain();assert(shown==1);
 enabled=NO;assert(!present(@"ordinary.app"));assert(!present(@"com.nx.stheno.action.app-picker.suffix"));
 assert(present(@"com.nx.stheno.action.screenshot"));drain();assert(actions==1);
 puts("Production SystemActionPresent: disabled/queued-disable/exact-ID consumption passed");
}return 0;}
'''

SWIFT = r'''
import Foundation
var enabled = true, systemBlocked = false, clock = 10.0
var rows: [[String: String]]? = [["identifier": "free.app", "name": "Free"]]
var disableInSnapshot = false, snapshotReads = 0, windowsCreated = 0
var animations: [UInt32] = [], launched: [String] = [], centerSubmits = 0
var dismissals = 0, quickHides = 0, inputOpens = 0
struct Deadline {
    let time: Double
    static func now() -> Deadline { Deadline(time: clock) }
    static func + (lhs: Deadline, rhs: Double) -> Deadline { Deadline(time: lhs.time + rhs) }
}
final class DispatchQueue {
    static let main = DispatchQueue()
    struct Job { let time: Double; let work: () -> Void }
    static var jobs: [Job] = []
    func async(execute: @escaping () -> Void) { Self.jobs.append(Job(time: clock, work: execute)) }
    func asyncAfter(deadline: Deadline, execute: @escaping () -> Void) { Self.jobs.append(Job(time: deadline.time, work: execute)) }
    static func next() {
        precondition(!jobs.isEmpty)
        let i = jobs.indices.min { jobs[$0].time < jobs[$1].time }!
        let job = jobs.remove(at: i); clock = max(clock, job.time); job.work()
    }
    static func drain() { var count = 0; while !jobs.isEmpty { next(); count += 1; precondition(count < 30) } }
}
func STHSystemActionsEnabled() -> Bool { enabled }
func STHSystemUIBlocked() -> Bool { systemBlocked }
func STHRefreshSystemVisibility() {}
func CACurrentMediaTime() -> Double { clock }
func STHChooserSnapshotUnpinned() -> [[String: String]]? { snapshotReads += 1; if disableInSnapshot { enabled = false }; return rows }
func STHCenterRunAnimation(_ change: () -> Void, _ mode: UInt32) { animations.append(mode); change() }
func STHChooserSubmitFloating(_ id: String) -> Bool { launched.append(id); return true }
func STHChooserSubmitCenterSelection() -> Bool { centerSubmits += 1; return true }
func STHSystemActionDismissRingNative() { dismissals += 1 }
func STHSystemActionHideQuickSettingNative() { quickHides += 1 }
struct Transaction { var disablesAnimations = false }
func withTransaction(_ t: Transaction, _ change: () -> Void) { change() }
struct STHChooserRingSnapshot {
    var portraitX = 0.0, offsetX = 0.0, portraitY = 0.0, offsetY = 0.0
    var iconWidth = 40.0, radius = 100.0, scale = 1.0
    var editing = 0, quickSetting = 0, showTab = 0, gestureState = 0
}
func STHChooserReadRing(_ snapshot: inout STHChooserRingSnapshot) -> Bool { true }
final class CenterState {
    var origin = CGPoint.zero, scale = 0.0, diameter = 0.0
    var ready = false, hover = false, lift: CGFloat = 0
}
final class PanelState { var visible = false }
struct AppRow { let id: String; let name: String }
class View {
    var isHidden = false, isUserInteractionEnabled = false
    var frame = CGRect.zero, bounds = CGRect(x: 0, y: 0, width: 430, height: 932)
    var backgroundColor: Color = .clear
    func layoutIfNeeded() {}
}
enum Color { case clear }
final class Surface: View { var hitArea = CGRect.zero }
final class Host { let view = View() }
final class Scene {
    enum Activation { case foregroundActive, background }
    var activationState = Activation.foregroundActive
    var windows: [UIWindow] = []
}
final class UIWindow: View {
    var isKeyWindow = false
    var windowScene: Scene?
    var rootViewController: ChooserHostingController?
    func makeKey() { windowScene?.windows.forEach { $0.isKeyWindow = false }; isKeyWindow = true }
    func endEditing(_ force: Bool) {}
}
final class ChooserInputSession {
    var closing = false, invalidated: (() -> Void)?
    func close() { closing = true }
    func bind(_ window: UIWindow) {}
    func prepareRouting() -> Bool { true }
    func open() { inputOpens += 1 }
    func finish() {}
}
struct AppPanel {
    init(items: [AppRow], state: PanelState, input: ChooserInputSession, select: @escaping (String?) -> Void) {}
}
final class ChooserHostingController {
    let view = View()
    init(rootView: AppPanel, input: ChooserInputSession) {}
}
func STHChooserInputScene(_ scene: Scene) -> Scene? { scene }
func STHCreateChooserInputWindow(_ scene: Scene) -> UIWindow? {
    windowsCreated += 1
    let w = UIWindow(); w.windowScene = scene; scene.windows.append(w); return w
}
struct CenterGlyphGeometry {
    static func visibleHitArea(center: CGPoint, diameter: Double, ringScale: CGFloat, liftedY: CGFloat, hover: Bool) -> CGRect { .zero }
}
struct Session { mutating func cancel() {} }
final class CenterController {
    var state = CenterState(), surface = Surface(), host = Host()
    var panelWindow: UIWindow?, previousKey: UIWindow?, targetWindow: UIWindow?
    var panelState: PanelState?, panelInput: ChooserInputSession?
    var presentationGeneration: UInt64 = 0, catalogRetry = 0
    var panelSelectionCancelled = false, suppressedUntil = 0.0
    var session = Session(), ringWasVisible = false, hasValidSnapshot = false
    var lastValidAt = 0.0, placementReady = false, collapseUntil = 0.0
    var last = STHChooserRingSnapshot()
    func findWindow(_ now: Double) {}
    func setGlyphVisible(_ visible: Bool) { state.ready = visible }
    func updateHover(_ hover: Bool) { state.hover = hover }
    func renderedCenter(_ p: CGPoint, in w: UIWindow) -> CGPoint { p }
__METHODS__
}
'''

def checked_run(command, *, should_fail=False):
    result = subprocess.run(command, text=True, capture_output=True)
    if should_fail:
        assert result.returncode != 0, ('negative control unexpectedly passed', command)
        assert any(word in result.stderr for word in ('Assertion', 'assertion', 'Precondition', 'precondition')), result.stderr
    elif result.returncode:
        raise AssertionError(f"Command failed: {command}\n{result.stdout}\n{result.stderr}")
    return result


def native_available():
    import sys
    return sys.platform == 'darwin' and shutil.which('xcrun') is not None


def objc_checks(directory, source):
    body = function(source, 'BOOL STHSystemActionPresent(')
    controls = {
        'dispatch-positive': body,
        'dispatch-no-entry-gate': body.replace('if(STHSystemActionsEnabled())dispatch_async', 'dispatch_async'),
        'dispatch-no-completion-gate': body.replace('if(STHSystemActionsEnabled())STHChooserShowFromNativeSelection();', 'STHChooserShowFromNativeSelection();'),
    }
    for name, implementation in controls.items():
        if name != 'dispatch-positive':
            assert implementation != body, name
        path = directory / f'{name}.m'
        executable = directory / name
        path.write_text(OBJC.replace('__PRESENT__', implementation))
        checked_run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-I', str(R), str(path), '-framework', 'Foundation', '-o', str(executable)])
        checked_run([str(executable)], should_fail=name != 'dispatch-positive')
        print(f'{name}: expected result')

    catalog = (R / 'ChooserCatalog.m').read_text()
    controls = {
        'catalog-positive': catalog,
        'catalog-no-entry-gate': catalog.replace('!STHSystemActionsEnabled() ||', '').replace('!STHSystemActionsEnabled()||', ''),
        'catalog-no-post-snapshot-gate': catalog.replace('if(!found || !STHSystemActionsEnabled())', 'if(!found)'),
        'catalog-no-post-builder-gate': catalog.replace('if(!STHSystemActionsEnabled())return NO;', ''),
    }
    for name, implementation in controls.items():
        if name != 'catalog-positive':
            assert implementation != catalog, name
        path = directory / f'{name}.m'
        executable = directory / name
        path.write_text(implementation)
        checked_run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-DSTH_CHOOSER_TEST', '-Wall', '-Wextra', '-Werror', '-I', str(R), str(R / 'test_chooser_catalog.m'), str(path), '-framework', 'Foundation', '-o', str(executable)])
        checked_run([str(executable)], should_fail=name != 'catalog-positive')
        print(f'{name}: expected result')


def scene_checks(directory):
    source = (R / 'AppSceneReflow.m').read_text()
    controls = {
        'scene-positive': source,
        'scene-no-ambiguity-forget': source.replace('hasHostedScene=NO;cacheDisarm();ensureWatch();', 'cacheDisarm();ensureWatch();'),
        'scene-unbounded-memory': source.replace('cacheExpires=fmin(reflowNow()+ttl,hostedSceneAt+60.0);', 'cacheExpires=reflowNow()+ttl;').replace('cacheArm(hostedScene,fmin(2.0,60.0-(reflowNow()-hostedSceneAt)));', 'cacheArm(hostedScene,2.0);'),
        'scene-unbounded-heartbeat': source.replace('double deadline=fmin(reflowNow()+ttl,hostedSceneAt+60.0);', 'double deadline=reflowNow()+ttl;'),
        'scene-read-before-count': source.replace('if(scene.screen!=display)continue;', 'if(scene.screen!=display)continue; (void)scene.coordinateSpace.bounds;'),
        'scene-fullscreen-keeps-old-card': source.replace('hasHostedScene=NO;stopWatch();cacheDisarm();\n   publishState(reason,NO,@"native-full-screen"', 'stopWatch();cacheDisarm();\n   publishState(reason,NO,@"native-full-screen"'),
    }
    for name, implementation in controls.items():
        if name != 'scene-positive':
            assert implementation != source, name
        path = directory / f'{name}.m'
        executable = directory / name
        path.write_text(implementation)
        checked_run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Wno-unused-parameter', '-I', str(R), f'-DSTH_REFLOW_SOURCE="{path}"', str(R / 'test_scene_reflow_runtime.m'), '-framework', 'Foundation', '-framework', 'CoreGraphics', '-framework', 'QuartzCore', '-o', str(executable)])
        checked_run([str(executable)], should_fail=name != 'scene-positive')
        print(f'{name}: expected result')


def source_checks():
    source = (R / 'SystemActions.m').read_text()
    body = function(source, 'BOOL STHSystemActionPresent(')
    assert body.count('if(STHSystemActionsEnabled())') == 2
    assert body.index('@STH_APP_CHOOSER_ID') < body.index('STHSystemActionForIdentifier')
    assert body.index('return YES;') < body.index('STHSystemActionForIdentifier')
    catalog = (R / 'ChooserCatalog.m').read_text()
    for signature in ('BOOL STHChooserSubmitFloating(', 'BOOL STHChooserSubmitCenterSelection('):
        implementation = function(catalog, signature)
        assert '!NSThread.isMainThread' in implementation
        assert implementation.index('STHSystemActionsEnabled()') < implementation.index('STHSystemMakeSwiftString')
        assert implementation.rindex('STHSystemActionsEnabled()') > implementation.index('STHChooserBuildManagerConsumed')
        assert '@finally' in implementation and 'STHChooserReleaseSwift(model)' in implementation
    # Extraction is exercised on Linux too: unfinished templates cannot silently pass.
    for signature in ('@objc func tick()', 'func selectCenter()', 'func openPanel()', 'func closePanel(selecting id: String?)', 'func hidePanel()'):
        method = function((R / 'CenterChooser.swift').read_text(), signature)
        assert method.endswith('}') and '__METHODS__' not in method
    sample = 'func sample() { let s = "}"; /* } */ // }\n if true { } } trailing'
    assert function(sample, 'func sample()') == sample.removesuffix(' trailing')
    scene = (R / 'AppSceneReflow.m').read_text()
    choice = function(scene, 'static STHRSceneChoice chooseScene(')
    assert choice.index('if(only)return') < choice.index('only.coordinateSpace.bounds')
    assert 'if(!only||!finiteRect(physical))return choice;' in choice
    assert 'cacheExpires=fmin(reflowNow()+ttl,hostedSceneAt+60.0);' in scene
    assert 'hasHostedScene=NO;cacheDisarm();ensureWatch();' in scene
    assert scene.index('STHRSceneChoice choice=chooseScene(display,physical);') < scene.index('if(!finiteRect(physical))return;')
    print('Chooser dispatch/catalog/extraction and scene ambiguity/deadline source checks passed')


def main():
    import argparse
    import resource
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-native', action='store_true', help='Fail instead of skipping outside macOS')
    parser.add_argument('--include-scenes', action='store_true', help='Also compile production scene-cache fixture and five failing mutations')
    args = parser.parse_args()
    source_checks()
    if not native_available():
        if args.require_native:
            raise SystemExit('Native chooser tests require macOS xcrun/Foundation')
        print('SKIP native Objective-C execution: macOS xcrun/Foundation unavailable')
        return
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='stheno-chooser-runtime-') as directory:
        objc_checks(Path(directory), (R / 'SystemActions.m').read_text())
        if args.include_scenes:
            scene_checks(Path(directory))


if __name__ == '__main__':
    main()
