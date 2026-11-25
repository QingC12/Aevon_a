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

# Two processes describe the same keyboard and neither has the whole picture.
# SpringBoard reports the key plane, the application's own UIKit adds the rows an
# input method draws inside its own window. The composer has to clear both, so the
# higher top always wins and neither side may pull the other down.
assert 'static STHVRect unionTop(' in client
assert 'if(!STHVValid(delivered)||!STHVValid(own)||own.y>=delivered.y-0.5)return delivered;' in client
assert 'canonical=unionTop(canonical,ownTopInScene(canonical,appOwnFrame,host.keyboard,lastOwnScreen));' in client
assert 'STHVRect unified=unionTop(canonical,own);' in client
assert 'client-union' in client
assert 'appOwnFrame=(STHVRect){0};' in client
# A union merges two descriptions of one docked keyboard, so both end on the
# same edge. A frame that ends somewhere else was measured in another space, and
# merging it would move the top while the bottom it belongs to stayed behind.
assert 'if(fabs((own.y+own.h)-bottom)>2.0)return delivered;' in client
# The conversion above cannot be the only reading. A scene whose origin is not
# where it is assumed to be makes the conversion agree with itself, the union
# silently returns the panel, and the composer keeps the last row of the panel
# over it. Both processes report the same keyboard in screen points, so the two
# tops are also compared there: the panel is raised by exactly the difference,
# which needs no mapping beyond the panel's own placement.
assert 'static STHVRect ownTopInScene(' in client
assert 'CGFloat delta=ownScreen.y-panelScreen.y;' in client
assert 'STHVRect viaPanel={delivered.x,delivered.y+delta,delivered.w,delivered.h-delta};' in client
assert 'if(delta>-0.5||delta<-160.0)return ownScene;' in client
assert 'lastOwnScreen=(STHVRect){0};' in client
# And one number no mapping can flatter: the field and the panel both converted
# to screen points by UIKit, recorded so the next log proves where the composer
# really ends.
assert 'inputScreen' in client and 'clearanceScreen' in client
assert 'physicalFrame.y-(screenField.y+screenField.h)' in client
# The carded window never learns where its viewport sits on the display, so the
# conversion to the screen returns the scene rectangle unchanged and the number
# above used to read a whole card origin too high. The host card origin is added
# only when the window reply still matches the scene, which is that identity.
assert 'BOOL identity=STHVValid(windowScreen)&&fabs(windowScreen.h-sceneBounds.h)<1.0' in client
assert 'screenField=(STHVRect){screenField.x+card.x,screenField.y+card.y' in client
# The inset answered to UIKit carries the same rule, so a layout pass that never
# sees a notification still clears both numbers.
assert 'double amount=fmax((double)native,canonicalAmount);' in client

# The card re-settles once inside the opening window instead of waiting for the
# next keyboard event.
assert 'host-settle' in host
assert '160*NSEC_PER_MSEC' in host
assert 'if(serial!=settleSerial||!sbKeyboardVisible)return;' in host

# A keyboard drawn by another process announces itself in steps. Two rules keep
# the card and the application from settling on a shorter panel than the one on
# screen: a trial rectangle far too short to be keys is not a keyboard at all,
# and a small step down is held for a second before it is believed.
assert 'sb-keyboard-trial' in host and 'sb-keyboard-hold' in host
assert 'requested.h<0.18*screen.h' in host
assert 'physical-shorter-settled' in host and 'drop>60.0' in host
assert 'physical-taller' in host and 'physical-smaller' in host
# The trial test cannot be gated on the shape test: a 75 point strip passes every
# other keyboard rule, which is how it used to reach the application.
assert host.index('BOOL trial=docked') < host.index('BOOL shaped=STHVKeyboard(requested,screen);')
assert 'BOOL docked=STHVValid(requested)&&STHVValid(screen)&&requested.w>=0.7*screen.w' in host
# Inside the opening window the panel is still being assembled and reported out
# of order, so no shrink of any size is adopted before it closes.
assert 'sb-keyboard-opening-hold' in host
assert 'hostNow()-keyboardShownAt<0.30' in host
assert 'if(visible&&!was)keyboardShownAt=hostNow();' in host
# Grow immediately, shrink only on proof.
taller = host.index('requested.y<physicalKeyboard.y-0.5')
hold = host.index('pendingShorter=requested;')
assert taller < hold, 'a taller frame must be adopted before any hold is considered'

# An application's own keyboard frame is not the panel: for a keyboard hosted by
# another process UIKit subtracts the rows that input method draws for itself.
# When the canonical mapping is unavailable the physical frame is mapped into the
# scene and used whenever it stands higher than the application's own frame.
assert 'STHVPhysicalFloor' in client and 'client-physical-floor' in client
assert 'floorTop<screenFrame.origin.y-0.5' in client
assert 'if(!authority->hosted||!authority->keyboardVisible)return NO;' in client

# One measurement is not enough: the application finishes its own avoidance
# after the last keyboard event, so the check stays armed for a bounded window.
assert 'armReconcile' in client and 'reconcilePasses>=3' in client
assert 'armReconcile(180)' in client and 'armReconcile(260)' in client

# No system animation is rewritten: frames this client synthesises carry no
# duration and reuse the original transaction ABI only.
assert client.count('UIKeyboardAnimationDurationUserInfoKey]=@0') >= 2
print('Keyboard alignment contract: foreign keyboards are delivered, the physical panel bounds what the application is told, a shrunken report is held, and a covered composer is re-measured inside the opening window')
