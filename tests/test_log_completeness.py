"""Keyboard evidence must survive: no caps, no silent refusals, alignment recorded.

The log is the only artefact that survives a session. A line budget or a file
ceiling deletes exactly the session that would explain a failure, and a silent
early return leaves a working keyboard with no record at all.
"""
from pathlib import Path
R = Path(__file__).resolve().parent.parent
diag = (R / 'ViewportDiagnostics.m').read_text()
host = (R / 'ViewportHost.m').read_text()
client = (R / 'ViewportClient.m').read_text()

# Append only, from any thread, with no volume ceiling of any kind.
for token in ['16000', '768*1024', '"wb"', 'count++']:
    assert token not in diag, ('Log volume cap returned', token)
for token in ['"ab"', 'logSequence', 'pid', 'process', 'isMainThread', 'STHVRectJSON']:
    assert token in diag, token
assert '/var/mobile/Documents' in diag and 'chmod(raw,0600)' in diag

# SpringBoard must record a keyboard even in the session where the geometry
# runtime declined to install, otherwise the failing session leaves an empty log
# and cannot be compared with a working one.
seen = host.index('sb-keyboard-seen')
assert seen < host.index('host-core-not-ready'), 'keyboard observation must not sit behind the runtime gate'
for name in ['UIKeyboardWillShowNotification', 'UIKeyboardDidShowNotification',
             'UIKeyboardWillChangeFrameNotification', 'UIKeyboardDidChangeFrameNotification',
             'UIKeyboardWillHideNotification', 'UIKeyboardDidHideNotification']:
    assert name in host[:seen + 1600], name
assert 'host-runtime' in host
for reason in ['local-barrier', 'no-visible-keyboard', 'local-input', 'minimized', 'orientation',
               'not-keyboard-shaped', 'invalid-card', 'invalid-scale', 'invalid-target']:
    assert '"' + reason + '"' in host, ('Unrecorded refusal', reason)
assert 'host-owner-skip' in host and 'keyboardClearance' in host

# The client records the one measurement a keyboard session is judged by, the
# clearance between the edited field and the delivered keyboard, plus every event
# it refuses. None of these entries changes delivery.
for token in ['client-editing-began', 'client-editing-ended', 'client-ignored', 'client-host-skip',
              'clearance', 'clearanceWorst', 'inputBottom', 'keyboardTop']:
    assert token in client, token
for reason in ['non-local', 'no-scene', 'not-main-screen', 'not-portrait', 'no-end-frame',
               'foreign-screen', 'no-responder']:
    assert '"' + reason + '"' in client, ('Unrecorded refusal', reason)
print('Log completeness contract: append only with no line or size cap; springboard records a keyboard without the geometry runtime; every refusal and the input to keyboard clearance are recorded')
