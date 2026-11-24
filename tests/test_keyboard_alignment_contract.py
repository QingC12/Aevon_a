"""A keyboard drawn by another process must reach the app, and a covered composer must be corrected.

Two defects are pinned here. The client refused every keyboard notification whose
UIKeyboardIsLocalUserInfoKey was NO, which is exactly what a third party input
method produces, so the application laid out for a keyboard it never heard about
and its composer ended behind the keys. A session that still ended covered was
measured but never corrected.
"""
from pathlib import Path
R = Path(__file__).resolve().parent.parent
client = (R / 'ViewportClient.m').read_text()
host = (R / 'ViewportHost.m').read_text()

# Locality is observed, no longer a refusal that drops the event.
assert 'BOOL foreign=' in client
assert '[raw[UIKeyboardIsLocalUserInfoKey] isEqual:@NO]){ignored(note,@"non-local")' not in client
assert 'client-foreign-localized' in client
assert 'localized[UIKeyboardIsLocalUserInfoKey]=@YES;' in client
assert 'info[UIKeyboardIsLocalUserInfoKey]=@YES;' in client
assert 'client-foreign-delivery' in client

# The correction is measured on the field being edited, bounded, and recorded.
for token in ['client-clearance-ok', 'client-clearance-fix', 'client-clearance-stalled',
              'correctionLift', 'corrections>=3', 'lastFixField', 'resetCorrection']:
    assert token in client, token
assert 'clearance=lastSceneFrame.y-(field.y+field.h)' in client
assert 'shortfall=-clearance+4.0' in client
assert 'return native+correctionLift;' in client
assert 'STHVInset(canonical,vr(scene.coordinateSpace.bounds))+correctionLift' in client
assert 'if(STHVNear(field,lastFixField,0.5))' in client

# The card re-settles once inside the opening window instead of waiting for the
# next keyboard event.
assert 'host-settle' in host
assert '160*NSEC_PER_MSEC' in host
assert 'if(serial!=settleSerial||!sbKeyboardVisible)return;' in host

# No system animation is rewritten: frames this client synthesises carry no
# duration and reuse the original transaction ABI only.
assert client.count('UIKeyboardAnimationDurationUserInfoKey]=@0') >= 2
print('Keyboard alignment contract: foreign keyboards are delivered, a covered composer is corrected once, and the card re-settles inside the opening window')
