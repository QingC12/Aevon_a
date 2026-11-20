from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parent
refined=(r/'EditorRefinedGuard.m').read_text().replace(' extern BOOL STHCompositeEnabled(void);if(STHCompositeEnabled())return;\n','')
assert hashlib.sha256((r/'EditorRefinedGuard.m').read_bytes()).hexdigest()==json.loads((r/'inputs/reviewed-runtime-2.0.18.json').read_text())['EditorRefinedGuard.m']
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
assert 'STHReportLayoutProbe' not in rows
assert 'STHBoundedResidual' in new
policy=(r/'EditorPolicy.m').read_text()
assert 'if(STHCompositeEnabled())STHEditorVisibilityCompositeEvent(showing)' in policy
assert 'else if(STHRefinementEnabled())STHEditorVisibilityRefinedEvent(showing)' in policy
measure=(r/'KeyboardCompositeMeasurement.m').read_text()
assert 'UIKBKeyplaneView' in measure and 'STHReadPhysicalLayout' in measure
assert 'confidence' in measure and 'STHKeyboardConnectedRow' in measure
assert 'specific||[n containsString:@"InputSetContainer"]' not in measure
assert 'CGRectUnion(*out,r)' not in measure
assert not (r/'NotificationPolicy.m').exists()
print('Legacy/refined/composite math and native layout shields retained; diagnostic reporters removed')
