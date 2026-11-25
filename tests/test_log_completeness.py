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
assert 'CFMessagePortCreateRemote' in diag and 'CFMessagePortSendRequest' in diag
assert 'CFSTR("no reply")' in diag, 'the no reply mode is a CFString literal on iOS'
assert 'if(!logSharedWritable&&!logRelayHost)forward=line;' in diag, 'forwarding must be one condition'
assert 'static void appendForwarded(NSData *line)' in diag
# The forwarded line is written byte for byte; re-encoding would lose the very
# pid and process fields that identify the sender.
assert 'fwrite(line.bytes,1,line.length,logSinks[i]);' in diag
# A process that can open the shared file does not forward, including the host.
assert "if([path isEqualToString:shared]){" in diag
assert 'logSharedWritable=YES;' in diag
assert 'if(logRelayHost)return;' in diag
# The relay is opened before the first record, so an application that loads later
# can already reach the file.
assert host.index('STHVLogInstallRelay();') < host.index('STHVLog(@"host-runtime"')
assert 'log-relay-listen' in diag and 'log-relay-client' in diag

# Neither route works from a store signed application: the shared file is not in
# its sandbox and neither is a foreign Mach service. It does write its own
# container, which springboard may read, so a collector copies whole records out
# of those files into the shared one. That is the route the collected file
# depends on, so its properties are pinned here.
assert 'collectorSweep' in host and 'collectorRescan' in host
assert '/var/mobile/Containers/Data/Application' in host
assert 'STHVLogAppendFromFile' in diag
for token in ['collector-start', 'collector-scan', 'collector-adopt', 'collector-reset',
              'collector-denied']:
    assert token in host, token
# Whole records only: a half written line is left for the next sweep.
assert "if(bytes[i]=='\\n')whole=i+1;" in host
assert 'if(!whole)continue;' in host
# The offset is durable, so a respring does not copy the same records again.
assert '.stheno-collector.json' in host and 'collectorSave()' in host
assert 'STHVLogAppendFromFile([data subdataWithRange:NSMakeRange(0,whole)]);' in host
# A file written before this springboard started is adopted at its end; a file
# created after it is the current session and is read from the beginning.
assert 'BOOL fresh=collectorStarted&&modified&&' in host
assert 'offset=fresh?0:size;' in host
# The collector runs off the main thread, where file reads cannot stall the shell.
assert 'com.nx.stheno.viewport32.collector' in host
# When the shared file opens, the container copy is not written at all, otherwise
# the collector would copy it back out and every record would appear twice.
assert 'logSharedWritable=YES;' in diag
assert diag.index('logSharedWritable=YES;') < diag.index('if(logSinkCount>=')

# The keyboard path is frozen, so the evidence is switched off rather than
# removed: one compile time switch decides whether any recorder, port or
# collector runs. Switched off, a shipped build pays one branch and opens no
# file, creates no Mach port and holds no timer, and setting the switch back to
# 1 restores every route exactly as it is pinned above.
diagh = (R / 'ViewportDiagnostics.h').read_text()
assert '#define STH_DIAGNOSTICS 0' in diagh
assert 'static inline BOOL STHVDiagnosticsEnabled(void){return STH_DIAGNOSTICS!=0;}' in diagh
assert 'void STHVLog(NSString *event,NSString *bundle,NSDictionary *values){\n if(!STHVDiagnosticsEnabled())return;' in diag
assert 'static void openSinks(void){\n if(!STHVDiagnosticsEnabled())return;' in diag
assert 'void STHVLogInstallRelay(void){\n if(!STHVDiagnosticsEnabled())return;' in diag
assert 'void STHVLogAppendFromFile(NSData *data){\n if(!STHVDiagnosticsEnabled())return;' in diag
assert 'static void appendForwarded(NSData *line){\n if(!STHVDiagnosticsEnabled())return;' in diag
# The collector is a two second timer over every application container and the
# port is a live Mach service: neither may exist when nothing is recorded.
assert 'static void startCollector(void){\n if(!STHVDiagnosticsEnabled())return;' in host
assert 'if(STHVDiagnosticsEnabled()){\n  STHVLogInstallRelay();\n  startCollector();\n }' in host
# The two per event paths that build large dictionaries return before they do.
assert 'static void probe(NSString *event,NSDictionary *extra){\n if(!STHVDiagnosticsEnabled())return;' in client
assert 'static void recordProbe(NSString *bundle){\n // Nothing here feeds geometry' in host
assert 'if(!STHVDiagnosticsEnabled())return;\n static NSMutableDictionary *lastFrames' in host
# Switched off is not deleted: every recorder named above still exists.
for token in ['client-source', 'client-union', 'client-settled', 'sb-keyboard-commit',
              'sb-keyboard-seen', 'collectorSweep', 'collectorRescan', 'collector-adopt',
              'relayReceive']:
    assert token in diag or token in host or token in client, ('Evidence removed', token)
print('Log completeness contract: append only with no line or size cap; springboard records a keyboard without the geometry runtime; every refusal and the input to keyboard clearance are recorded; an application record reaches the shared file through a collector, because neither the shared file nor a foreign Mach service is in its sandbox')
