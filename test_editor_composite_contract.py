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
shield=(r/'NativeGeometryShield.inc').read_text()
assert 'NativeGeometryShield.inc' in structure
assert shield.index('part.transform=state.original')<shield.index('@try{native();}')<shield.index('part.transform=state.applied')
for setter in ['@selector(setFrame:)','@selector(setBounds:)','@selector(setCenter:)']:
 assert setter in shield
assert 'neutralLayoutDepth' in shield and 'class_addMethod' in shield
assert 'protectAdditionalPart(v)' in new
rows=(r/'CompositeRows.inc').read_text()
assert 'canReveal(v,root,scene)' in rows and 'STHCanReleaseComposerClip' in rows
assert '.hidden=NO' not in rows and '.alpha=1' not in rows
assert 'STHReportLayoutProbe' in rows and 'NSStringFromClass(v.class)' in rows
assert 'STHBoundedResidual' in new
policy=(r/'EditorPolicy.m').read_text()
assert 'if(STHCompositeEnabled())STHEditorVisibilityCompositeEvent(showing)' in policy
assert 'else if(STHRefinementEnabled())STHEditorVisibilityRefinedEvent(showing)' in policy
measure=(r/'KeyboardCompositeMeasurement.m').read_text()
assert 'UIKBKeyplaneView' in measure and 'STHReadPhysicalLayout' in measure
assert 'confidence' in measure and 'STHKeyboardConnectedRow' in measure
assert 'specific||[n containsString:@"InputSetContainer"]' not in measure
assert 'CGRectUnion(*out,r)' not in measure
sound=(r/'NotificationPolicy.m').read_text()
for forbidden in ['setObject:', 'setPersistentDomain:', 'AudioServicesPlay', 'UNUserNotificationCenter', 'setBool:', 'setInteger:']:
 assert forbidden not in sound
assert 'SettingMask' in sound and '1ULL<<27' in sound
print('WeChat2.0.12 code hashes preserved; composite owner/native layout shield wired; notification diagnosis is read-only')
