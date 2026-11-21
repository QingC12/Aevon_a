#ifndef STH_VIEWPORT_BUS_H
#define STH_VIEWPORT_BUS_H

/* The portable branch is only a stand-in for the deterministic C test runner. */
#if defined(STH_VIEWPORT_BUS_TEST) && !defined(__APPLE__)
#include <stdbool.h>
typedef const char NSString;
typedef bool BOOL;
#define YES true
#define NO false
typedef void (*dispatch_block_t)(void);
#else
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#endif
#include "ViewportGeometry.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Stable, case-sensitive FNV-1a of UTF-8; zero means an invalid bundle.
 * This pure helper is the only API that may be called off the main thread. */
uint64_t STHVKey(NSString *bundle);

typedef struct {
    STHVRect card, keyboard;
    uint64_t owner, serial;
    BOOL active;
    double at;                 /* Continuous boot-time seconds, not wall time. */
    uint64_t event;             /* Request claim generation; renewals preserve it. */
    uint64_t physicalGeneration;
    BOOL keyboardVisible, hosted, reflowEnabled;
} STHVSnapshot;

/* All transport/observation APIs are main-thread-only, otherwise fail/no-op.
 * One writer per bundle per stream is required; notify has no compare-and-swap.
 * No reads or observers renew freshness. Request/layout snapshots expire after
 * 2/3 seconds. Only an explicit Publish or Renew writes a new timestamp;
 * the bus creates no timer. Publish(active=YES) claims real focus, whereas
 * Renew may maintain the current owner's request without claiming ownership.
 * Zero-size rectangles are valid payloads. Bad rectangles do not change commit.
 * Reads attempt at most three consistent transactions and leave outputs intact
 * on failure. NULL output pointers are allowed.
 * YES means committed (and, for active requests, owner installed). Posting is
 * best effort: notify_post failure cannot roll back an already-visible commit.
 */
BOOL STHVPublishRequest(NSString *bundle, BOOL active, STHVRect physical);
/* Renew never writes global owner; a handoff during renewal may return NO.
 * A stale/inactive/non-current bundle cannot be resurrected by renewal. */
BOOL STHVRenewRequest(NSString *bundle, STHVRect physical);
/* Resume an expired active claim only while the sticky global owner is still
 * this same bundle. Never writes global owner; callers verify live input. */
BOOL STHVResumeRequest(NSString *bundle, STHVRect physical);
/* Fresh inactive requests remain readable even if another bundle owns focus. */
BOOL STHVReadRequest(NSString *bundle, STHVSnapshot *out);
uint64_t STHVRequestOwner(void); /* Fresh, active effective owner, or zero. */
void STHVObserveRequests(dispatch_block_t block);

/* Inactive layouts remain readable and carry their baseline card. Layouts
 * are per-bundle facts, not gated by ownership of the current request. */
BOOL STHVPublishLayout(NSString *bundle, BOOL active,
                       STHVRect card, STHVRect physical);
/* Only the SB producer supplies these authority facts; app requests are diagnostic. */
BOOL STHVPublishLayoutState(NSString *bundle,BOOL active,STHVRect card,STHVRect physical,
                           uint64_t physicalGeneration,BOOL keyboardVisible);
BOOL STHVPublishLayoutPolicyState(NSString *bundle,BOOL active,STHVRect card,STHVRect physical,
 uint64_t physicalGeneration,BOOL keyboardVisible,BOOL reflowEnabled);
BOOL STHVReadLayout(NSString *bundle, STHVSnapshot *out);
void STHVObserveLayout(NSString *bundle, dispatch_block_t block);

/* Diagnostic stream with its own slots/commit, deliberately not gated by
 * request ownership or age. Equal/empty rectangles are accepted. It never
 * changes layout/request state or their notifications. */
void STHVPublishProbe(NSString *bundle, STHVRect responder, STHVRect parent);
BOOL STHVReadProbe(NSString *bundle, STHVRect *responder, STHVRect *parent);
void STHVPublishClientFrames(NSString *bundle,STHVRect raw,STHVRect mapped,uint64_t physicalGeneration);
BOOL STHVReadClientFrames(NSString *bundle,STHVSnapshot *out);

/* Each observation adds a process-lifetime observer, delivered on main queue.
 * Consumers must re-read: Darwin notifications may be coalesced. */

#ifdef __cplusplus
}
#endif
#endif
