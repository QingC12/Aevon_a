from pathlib import Path
import hashlib
r=Path(__file__).resolve().parent
refined=(r/'EditorRefinedGuard.m').read_text().replace(' extern BOOL STHCompositeEnabled(void);if(STHCompositeEnabled())return;\n','')
assert hashlib.sha256(refined.encode()).hexdigest()=='d8908cf73ba11a36bc2bd754b0e7306752a79e272d63e756ddb6548a21511d60'
assert hashlib.sha256((r/'KeyboardRefinedMeasurement.m').read_bytes()).hexdigest()=='74abdbc50963befd97211e8b3f63410b46273fc11393306f1c5c560a030ae5fe'
new=(r/'EditorCompositeGuard.m').read_text();structure=(r/'CompositeStructure.inc').read_text()
assert 'composerOwner(field,window,scene)' in new
assert 'STHCompositeRow' in new and 'editingField=field' in new
assert 'STHTransparentTailDrop(' not in new
assert 'native(view,selector)' in structure
assert structure.index('part.transform=state.original')<structure.index('@try{native(view,selector);}')<structure.index('part.transform=state.applied')
assert 'neutralLayoutDepth' in structure and 'class_addMethod' in structure
assert 'STHBoundedResidual' in new
policy=(r/'EditorPolicy.m').read_text()
assert 'if(STHCompositeEnabled())STHEditorVisibilityCompositeEvent(showing)' in policy
assert 'else if(STHRefinementEnabled())STHEditorVisibilityRefinedEvent(showing)' in policy
measure=(r/'KeyboardCompositeMeasurement.m').read_text()
assert 'UIKBKeyplaneView' in measure and 'CGRectIsNull(core)' in measure
sound=(r/'NotificationPolicy.m').read_text()
for forbidden in ['setObject:', 'setPersistentDomain:', 'AudioServicesPlay', 'UNUserNotificationCenter', 'setBool:', 'setInteger:']:
 assert forbidden not in sound
assert 'SettingMask' in sound and '1ULL<<27' in sound
print('WeChat2.0.12 code hashes preserved; composite owner/native layout shield wired; notification diagnosis is read-only')
