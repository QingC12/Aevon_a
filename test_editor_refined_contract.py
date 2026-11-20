from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parent
legacy=(r/'EditorGuard.m').read_text()
restored=legacy.replace('STHEditorVisibilityLegacyEvent','STHEditorVisibilityEvent').replace(
 ' extern BOOL STHRefinementEnabled(void);if(STHRefinementEnabled())return;\n','')
assert hashlib.sha256(legacy.encode()).hexdigest()==json.loads((r/'inputs/reviewed-runtime-2.0.18.json').read_text())['EditorGuard.m']
assert hashlib.sha256((r/'KeyboardMeasurement.m').read_bytes()).hexdigest()=='610dad7b084df1a5f3ad5806b65824fd794eea2a441289c823b3e08e6ba31c3f'
policy=(r/'EditorPolicy.m').read_text()
assert 'else STHEditorVisibilityLegacyEvent(showing)' in policy
refined=(r/'EditorRefinedGuard.m').read_text()
assert 'STHCompactComposer' in refined and '{root=v;break;}' in refined
assert 'STHRefinedLift' in refined and 'measuredGroup(views,scene)' in refined
assert 'STHTransparentTailDrop' in refined and 'STHEditorTransparentTail' in refined
assert 'protrusions(root,root,scene' in refined
assert 'CGRectIntersection(r,clip)' in refined
assert 'STHComposerLift(' not in refined
measure=(r/'KeyboardRefinedMeasurement.m').read_text()
assert 'r.inputAccessoryView' in measure and '!wrapsAppRow(v,appRows)' in measure
assert 'STHExcludeAppAccessory' in measure
assert 'CGRect keys=CGRectIsNull(exact)?fallback:exact' in measure
build=(r/'build.py').read_text()
for source in ['EditorPolicy.m','EditorRefinedGuard.m','KeyboardRefinedMeasurement.m']:
 assert source in build
print('Legacy functional route retained; diagnostic deletion reviewed; refined profiles, compact root, clipping/emoji descendants and declared-accessory exclusion wired')
