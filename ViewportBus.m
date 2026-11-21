#import "ViewportBus.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef STH_VIEWPORT_BUS_TEST
/* The test executable supplies these hooks; no notifyd or real clock is used. */
extern uint64_t STHVTestNow(void);
extern BOOL STHVTestIsMainThread(void);
extern uint32_t STHVTestRegister(const char *, int *);
extern uint32_t STHVTestGet(int, uint64_t *);
extern uint32_t STHVTestSet(int, uint64_t);
extern uint32_t STHVTestPost(const char *);
extern uint32_t STHVTestCancel(int);
extern void STHVTestObserve(const char *, dispatch_block_t);
#define busRegister STHVTestRegister
#define busGet STHVTestGet
#define busSet STHVTestSet
#define busPost STHVTestPost
#define busCancel STHVTestCancel
static BOOL onMain(void) { return STHVTestIsMainThread(); }
static uint64_t nowMS(void) { return STHVTestNow(); }
static void observe(const char *name, dispatch_block_t block) {
    STHVTestObserve(name, block);
}
#else
#import <notify.h>
#include <mach/mach_time.h>
#define busRegister notify_register_check
#define busGet notify_get_state
#define busSet notify_set_state
#define busPost notify_post
#define busCancel notify_cancel
static BOOL onMain(void) { return [NSThread isMainThread]; }
static uint64_t nowMS(void) {
    static mach_timebase_info_data_t scale;
    if (!scale.denom && (mach_timebase_info(&scale) != KERN_SUCCESS || !scale.denom))
        return UINT64_MAX;
    return (uint64_t)((long double)mach_continuous_time() * scale.numer /
                       scale.denom / 1000000.0L);
}
static void observe(const char *name, dispatch_block_t block) {
    int token = -1;
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int value) {
        (void)value;
        block();
    });
}
#endif

#define PREFIX "com.nx.stheno.viewport32"
#define VALID (UINT64_C(1) << 63)
#define ACTIVE (UINT64_C(1) << 62)
#define SERIAL_MASK (ACTIVE - 1)

typedef enum { Request, Layout, Probe, FrameProbe } Stream;
static const char *const streams[] = {"request", "layout", "probe", "frameprobe"};

typedef struct Channel {
    uint64_t key;
    Stream stream;
    int data[2][4];             /* card, keyboard, continuous timestamp (ms). */
    int commit;
    struct Channel *next;
} Channel;

/* Main-thread caches retain notify registrations for the process lifetime. */
static Channel *channels;
static int ownerToken = -1;

uint64_t STHVKey(NSString *bundle) {
#if defined(STH_VIEWPORT_BUS_TEST) && !defined(__APPLE__)
    const char *bytes = bundle;
    if (!bytes || !*bytes) return 0;
#else
    if (![bundle isKindOfClass:[NSString class]] || !bundle.length) return 0;
    const char *bytes = bundle.UTF8String;
    if (!bytes || strlen(bytes) != [bundle lengthOfBytesUsingEncoding:NSUTF8StringEncoding])
        return 0;              /* Reject embedded NUL rather than alias a bundle. */
#endif
    uint64_t key = UINT64_C(14695981039346656037);
    for (const unsigned char *p = (const unsigned char *)bytes; *p; ++p)
        key = (key ^ *p) * UINT64_C(1099511628211);
    return key ? key : 1;
}

static void nameFor(char name[128], Stream stream, uint64_t key, const char *field) {
    snprintf(name, 128, PREFIX ".%s.%016" PRIx64 ".%s", streams[stream], key, field);
}

static BOOL getOwnerToken(void) {
    if (ownerToken >= 0) return YES;
    int token = -1;
    if (busRegister(PREFIX ".request.owner", &token) != 0 || token < 0) return NO;
    ownerToken = token;
    return YES;
}

static Channel *getChannel(Stream stream, uint64_t key) {
    for (Channel *c = channels; c; c = c->next)
        if (c->key == key && c->stream == stream) return c;
    Channel *c = calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->key = key;
    c->stream = stream;
    c->commit = -1;
    for (unsigned slot = 0; slot < 2; ++slot)
        for (unsigned field = 0; field < 4; ++field) c->data[slot][field] = -1;
    char name[128], field[16];
    const char *const labels[] = {"card", "key", "at", "authority"};
    for (unsigned slot = 0; slot < 2; ++slot) {
        for (unsigned i = 0; i < 4; ++i) {
            snprintf(field, sizeof(field), "%s%u", labels[i], slot);
            nameFor(name, stream, key, field);
            if (busRegister(name, &c->data[slot][i]) != 0 || c->data[slot][i] < 0)
                goto failed;
        }
    }
    nameFor(name, stream, key, "commit");
    if (busRegister(name, &c->commit) != 0 || c->commit < 0) goto failed;
    c->next = channels;
    channels = c;
    return c;
failed:
    for (unsigned slot = 0; slot < 2; ++slot)
        for (unsigned i = 0; i < 4; ++i)
            if (c->data[slot][i] >= 0) busCancel(c->data[slot][i]);
    if (c->commit >= 0) busCancel(c->commit);
    free(c);
    return NULL;
}

static BOOL publish(Stream stream, uint64_t key, BOOL active, BOOL claim,
                    STHVRect card, STHVRect keyboard,uint64_t authority) {
    uint64_t a, b, current, stamp = nowMS();
    if (!key || stamp == UINT64_MAX || !STHVPackRect(card, &a) ||
        !STHVPackRect(keyboard, &b)) return NO;
    if (stream == Request && active && !getOwnerToken()) return NO;
    Channel *c = getChannel(stream, key);
    if (!c || busGet(c->commit, &current) != 0) return NO;
    uint64_t serial = (current & SERIAL_MASK) + 1;
    if (serial > SERIAL_MASK) return NO; /* Fail closed rather than wrap/ABA. */
    unsigned slot = (unsigned)(serial & 1);
    /* Request.card is unused geometry: carry the last real input-event
     * generation there. Renew/resume cannot turn an old physical frame into
     * a new Will event after a host hide. */
    if(stream==Request){
        if(claim)a=serial;
        else if(busGet(c->data[current & 1][0],&a)!=0)return NO;
    }
    /* An interrupted write only damages the uncommitted slot. Timestamp is
     * slot data too, leaving 62 commit bits for a restart-safe generation. */
    if (busSet(c->data[slot][0], a) != 0 ||
        busSet(c->data[slot][1], b) != 0 ||
        busSet(c->data[slot][2], stamp) != 0 ||
        busSet(c->data[slot][3], authority) != 0 ||
        busSet(c->commit, VALID | (active ? ACTIVE : 0) | serial) != 0) return NO;
    /* Never clear the shared owner. A conditional get/set clear races with
     * another application's claim because notify has no CAS. The sticky hash
     * is resolved through its fresh, active per-owner request by Owner(). */
    if (stream == Request && active && claim && busSet(ownerToken, key) != 0) return NO;
    char name[128];
    if (stream == Request) busPost(PREFIX ".request.changed");
    else {
        nameFor(name, stream, key, "changed");
        busPost(name);
    }
    return YES;
}

/* A zero request key is internal shorthand for resolving the global owner. */
static BOOL readSnapshotWithAge(Stream stream, uint64_t key, STHVSnapshot *out, BOOL allowExpired) {
    const BOOL guarded = stream == Request || stream == Layout;
    if (guarded && !getOwnerToken()) return NO;
    for (unsigned attempt = 0; attempt < 3; ++attempt) {
        uint64_t before = 0, after = 0, first, last, a, b, stamp, authority;
        if (guarded && busGet(ownerToken, &before) != 0) return NO;
        uint64_t actualKey = key ? key : before;
        if (!actualKey) return NO;
        Channel *c = getChannel(stream, actualKey);
        if (!c || busGet(c->commit, &first) != 0) return NO;
        if (!(first & VALID) || !(first & SERIAL_MASK)) return NO;
        unsigned slot = (unsigned)(first & 1);
        if (busGet(c->data[slot][0], &a) != 0 ||
            busGet(c->data[slot][1], &b) != 0 ||
            busGet(c->data[slot][2], &stamp) != 0 ||
            busGet(c->data[slot][3], &authority) != 0 ||
            busGet(c->commit, &last) != 0 ||
            (guarded && busGet(ownerToken, &after) != 0)) return NO;
        if (first != last || (guarded && before != after)) continue;
        if (guarded || stream==FrameProbe) {
            uint64_t now = nowMS(), limit = stream == Layout ? 3000 : 2000;
            if (now == UINT64_MAX || stamp > now || (!allowExpired && now - stamp > limit)) return NO;
        }
        STHVSnapshot value = {stream==Request?(STHVRect){0}:STHVUnpackRect(a), STHVUnpackRect(b), actualKey,
                             first & SERIAL_MASK, (first & ACTIVE) != 0,
                             (double)stamp / 1000.0,stream==Request?a:0,
                             (stream==Layout||stream==FrameProbe)?authority>>3:0,
                             stream==Layout&&(authority&1),
                             stream==Layout&&(authority&2),stream==Layout&&(authority&4)};
        if (out) *out = value;
        return YES;
    }
    return NO;
}

static BOOL readSnapshot(Stream stream,uint64_t key,STHVSnapshot *out){return readSnapshotWithAge(stream,key,out,NO);}

BOOL STHVPublishRequest(NSString *bundle, BOOL active, STHVRect physical) {
    return onMain() && publish(Request, STHVKey(bundle), active, YES, (STHVRect){0}, physical,0);
}

BOOL STHVRenewRequest(NSString *bundle, STHVRect physical) {
    uint64_t key, after;
    STHVSnapshot current;
    if (!onMain() || !(key = STHVKey(bundle)) ||
        !readSnapshot(Request, 0, &current) || current.owner != key || !current.active)
        return NO;
    if (!publish(Request, key, YES, NO, (STHVRect){0}, physical,0)) return NO;
    /* A concurrent claim may make this renewal irrelevant, but is never
     * overwritten. The caller must not fall back to claiming on renewal failure. */
    return busGet(ownerToken, &after) == 0 && after == key;
}

BOOL STHVResumeRequest(NSString *bundle,STHVRect physical){
    uint64_t key,before,after;STHVSnapshot prior;
    if(!onMain()||!(key=STHVKey(bundle))||!getOwnerToken()||
       busGet(ownerToken,&before)!=0||before!=key||
       !readSnapshotWithAge(Request,key,&prior,YES)||!prior.active)return NO;
    if(!publish(Request,key,YES,NO,(STHVRect){0},physical,0))return NO;
    return busGet(ownerToken,&after)==0&&after==key;
}

BOOL STHVReadRequest(NSString *bundle, STHVSnapshot *out) {
    uint64_t key;
    return onMain() && (key = STHVKey(bundle)) && readSnapshot(Request, key, out);
}

uint64_t STHVRequestOwner(void) {
    STHVSnapshot value;
    return onMain() && readSnapshot(Request, 0, &value) && value.active ? value.owner : 0;
}

void STHVObserveRequests(dispatch_block_t block) {
    if (onMain() && block) observe(PREFIX ".request.changed", block);
}

BOOL STHVPublishLayout(NSString *bundle, BOOL active, STHVRect card, STHVRect physical) {
    return onMain() && publish(Layout, STHVKey(bundle), active, NO, card, physical,STHVValid(card)?2:0);
}

BOOL STHVPublishLayoutPolicyState(NSString *bundle,BOOL active,STHVRect card,STHVRect physical,uint64_t generation,BOOL visible,BOOL reflow){
    if(!onMain()||generation>(UINT64_MAX>>3)||((visible||active)&&(!generation||!visible||!STHVValid(physical))))return NO;
    uint64_t metadata=(generation<<3)|(visible?1:0)|(STHVValid(card)?2:0)|(reflow?4:0);
    return publish(Layout,STHVKey(bundle),active,NO,card,physical,metadata);
}
BOOL STHVPublishLayoutState(NSString *bundle,BOOL active,STHVRect card,STHVRect physical,uint64_t generation,BOOL visible){return STHVPublishLayoutPolicyState(bundle,active,card,physical,generation,visible,NO);}

BOOL STHVReadLayout(NSString *bundle, STHVSnapshot *out) {
    uint64_t key;
    return onMain() && (key = STHVKey(bundle)) && readSnapshot(Layout, key, out);
}

void STHVObserveLayout(NSString *bundle, dispatch_block_t block) {
    if (!onMain() || !block) return;
    uint64_t key = STHVKey(bundle);
    if (!key) return;
    char name[128];
    nameFor(name, Layout, key, "changed");
    observe(name, block);
}

void STHVPublishProbe(NSString *bundle, STHVRect responder, STHVRect parent) {
    if (onMain()) publish(Probe, STHVKey(bundle), YES, NO, responder, parent,0);
}

BOOL STHVReadProbe(NSString *bundle, STHVRect *responder, STHVRect *parent) {
    uint64_t key;
    STHVSnapshot value;
    if (!onMain() || !(key = STHVKey(bundle)) || !readSnapshot(Probe, key, &value)) return NO;
    if (responder) *responder = value.card;
    if (parent) *parent = value.keyboard;
    return YES;
}

void STHVPublishClientFrames(NSString *bundle,STHVRect raw,STHVRect mapped,uint64_t generation){
 if(onMain()&&generation<=(UINT64_MAX>>3))publish(FrameProbe,STHVKey(bundle),YES,NO,raw,mapped,generation<<3);
}
BOOL STHVReadClientFrames(NSString *bundle,STHVSnapshot *out){
 return onMain()&&STHVKey(bundle)&&readSnapshot(FrameProbe,STHVKey(bundle),out);
}
