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

# A single attempt at install used to be a session long failure whenever the
# loader happened to order the two libraries the other way. The install is now a
# function with an idempotence flag and a bounded retry, and the retry is what
# removes the "respring until it works" symptom.
assert 'static void installGeometry(NSString *trigger)' in host
assert 'geometryInstalled=YES' in host and 'if(geometryInstalled)return' in host
assert 'installGeometry(@"launch")' in host and 'installGeometry([NSString stringWithFormat:@"retry-%d"' in host
assert 'attempts>=20' in host and 'host-runtime-wait' in host

# The client records the one measurement a keyboard session is judged by, the
# clearance between the edited field and the delivered keyboard, plus every event
# it refuses. None of these entries changes delivery.
for token in ['client-editing-began', 'client-editing-ended', 'client-ignored', 'client-host-skip',
              'clearance', 'clearanceWorst', 'inputBottom', 'keyboardTop']:
    assert token in client, token
for reason in ['non-local', 'no-scene', 'not-main-screen', 'not-portrait', 'no-end-frame',
               'foreign-screen', 'no-responder']:
    assert '"' + reason + '"' in client, ('Unrecorded refusal', reason)

# One file has to hold both halves of a keyboard session. A sandboxed application
# cannot open /var/mobile/Documents, so its record is forwarded over a message
# port and appended by springboard as received, keeping its own pid and process.
assert 'CFMessagePortCreateLocal' in diag and 'CFMessagePortSetDispatchQueue' in diag
assert 'CFMessagePortCreateRemote' in diag and 'kCFMessagePortSendNoReply' in diag
assert 'if(!logSharedWritable&&!logRelayHost)forward=line;' in diag, 'forwarding must be one condition'
assert 'static void appendForwarded(NSData *line)' in diag
# The forwarded line is written byte for byte; re-encoding would lose the very
# pid and process fields that identify the sender.
assert 'fwrite(line.bytes,1,line.length,logSinks[i]);' in diag
# A process that can open the shared file does not forward, including the host.
assert 'if([path isEqualToString:shared])logSharedWritable=YES;' in diag
assert 'if(logRelayHost)return;' in diag
# The relay is opened before the first record, so an application that loads later
# can already reach the file.
assert host.index('STHVLogInstallRelay();') < host.index('STHVLog(@"host-runtime"')
assert 'log-relay-listen' in diag and 'log-relay-client' in diag
print('Log completeness contract: append only with no line or size cap; springboard records a keyboard without the geometry runtime; every refusal and the input to keyboard clearance are recorded; an application record reaches the shared file over a message port')
