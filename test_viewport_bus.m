#import "ViewportBus.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* macOS fake: xcrun clang -fobjc-arc -DSTH_VIEWPORT_BUS_TEST -Wall -Wextra
 *   -Werror test_viewport_bus.m ViewportBus.m -framework Foundation -o /tmp/vbus
 * Portable fake: clang -x c -std=c11 -DSTH_VIEWPORT_BUS_TEST -Wall -Wextra
 *   -Werror test_viewport_bus.m ViewportBus.m -lm -o /tmp/vbus
 * Real notifyd: omit -DSTH_VIEWPORT_BUS_TEST from the macOS command. */

static STHVRect cardFor(unsigned i) {
    return (STHVRect){40 + (i % 20) * .25, 120 + (i % 17) * .25, 330, 710};
}
static STHVRect keyFor(unsigned i) {
    return i ? (STHVRect){0, 500 + (i % 80) * .25, 430, 300 - (i % 80) * .25}
             : (STHVRect){0};
}
static void sameRect(STHVRect a, STHVRect b) { assert(STHVNear(a, b, 0)); }
static void checkLayout(NSString *bundle, unsigned i, BOOL active) {
    STHVSnapshot s;
    assert(STHVReadLayout(bundle, &s));
    assert(s.owner == STHVKey(bundle) && s.serial && s.active == active);
    sameRect(s.card, cardFor(i));
    sameRect(s.keyboard, keyFor(i));
}

#ifdef STH_VIEWPORT_BUS_TEST
#if defined(__APPLE__)
#define STR(s) @s
#define CALLBACK(fn) ^{ fn(); }
#else
#define STR(s) s
#define CALLBACK(fn) fn
#endif
static NSString *const A = STR("test.stheno.viewport32.A");
static NSString *const B = STR("test.stheno.viewport32.B");
#define PFX "com.nx.stheno.viewport32"
#define CAP 4096
static struct { char name[128]; uint64_t value, posts; } words[CAP];
static int wordCount, tokenCount, tokenWord[CAP];
static char observerNames[32][128];
static dispatch_block_t observers[32];
static BOOL pending[32];
static unsigned observerCount, requestEvents, layoutEvents;
static uint64_t clockMS = 1000000, getCount, sets, registrations, ownerWrites;
static uint64_t failGet, failSet, failRegister;
static BOOL mainThread = YES, inHook, denyOwner, tracing;
static char trace[32][128];
static unsigned traceCount;
static void (*afterRead)(const char *), (*afterWrite)(const char *);

static int word(const char *name, BOOL create) {
    assert(strncmp(name, PFX ".", strlen(PFX) + 1) == 0);
    for (int i = 0; i < wordCount; ++i)
        if (!strcmp(words[i].name, name)) return i;
    if (!create) return -1;
    assert(wordCount < CAP);
    snprintf(words[wordCount].name, sizeof(words[0].name), "%s", name);
    return wordCount++;
}
static const char *tokenName(int token) {
    assert(token > 0 && token <= tokenCount && tokenWord[token] >= 0);
    return words[tokenWord[token]].name;
}
static void fire(void (*hook)(const char *), const char *name) {
    if (hook && !inHook) { inHook = YES; hook(name); inHook = NO; }
}
uint64_t STHVTestNow(void) { return clockMS; }
BOOL STHVTestIsMainThread(void) { return mainThread; }
uint32_t STHVTestRegister(const char *name, int *token) {
    if (++registrations == failRegister) { failRegister = 0; return 1; }
    assert(tokenCount + 1 < CAP);
    *token = ++tokenCount;
    tokenWord[*token] = word(name, YES);
    return 0;
}
uint32_t STHVTestCancel(int token) {
    (void)tokenName(token);
    tokenWord[token] = -1;
    return 0;
}
uint32_t STHVTestGet(int token, uint64_t *value) {
    const char *name = tokenName(token);
    if (tracing && !inHook) {
        assert(traceCount < 32);
        snprintf(trace[traceCount++], sizeof(trace[0]), "%s", name);
    }
    if (++getCount == failGet) { failGet = 0; return 1; }
    if (denyOwner && !strcmp(name, PFX ".request.owner")) return 1;
    *value = words[tokenWord[token]].value;
    fire(afterRead, name);
    return 0;
}
uint32_t STHVTestSet(int token, uint64_t value) {
    const char *name = tokenName(token);
    if (++sets == failSet) { failSet = 0; return 1; }
    words[tokenWord[token]].value = value;
    if (!strcmp(name, PFX ".request.owner")) ++ownerWrites;
    fire(afterWrite, name);
    return 0;
}
uint32_t STHVTestPost(const char *name) {
    ++words[word(name, YES)].posts;
    for (unsigned i = 0; i < observerCount; ++i)
        if (!strcmp(observerNames[i], name)) pending[i] = YES;
    return 0;
}
void STHVTestObserve(const char *name, dispatch_block_t block) {
    assert(observerCount < 32);
    snprintf(observerNames[observerCount], sizeof(observerNames[0]), "%s", name);
#if defined(__APPLE__)
    observers[observerCount] = [block copy];
#else
    observers[observerCount] = block;
#endif
    ++observerCount;
}
static void drain(void) {
    for (unsigned i = 0; i < observerCount; ++i)
        if (pending[i]) { pending[i] = NO; observers[i](); }
}
static void requestEvent(void) { ++requestEvents; }
static void layoutEvent(void) { ++layoutEvents; }
static uint64_t field(NSString *bundle, const char *stream, const char *label) {
    char name[128];
    snprintf(name, sizeof(name), PFX ".%s.%016" PRIx64 ".%s", stream, STHVKey(bundle), label);
    int i = word(name, NO);
    return i < 0 ? 0 : words[i].value;
}
static BOOL isData(const char *name, const char *stream, const char *label) {
    char prefix[128];
    snprintf(prefix, sizeof(prefix), PFX ".%s.%016" PRIx64 ".%s", stream, STHVKey(A), label);
    return strncmp(name, prefix, strlen(prefix)) == 0;
}
static void hashAndRoundTrips(void) {
    assert(STHVKey(STR("a")) == UINT64_C(0xaf63dc4c8601ec8c));
    assert(!STHVKey(NULL) && !STHVKey(STR("")) && STHVKey(A) != STHVKey(B));
    STHVSnapshot s = {0};
    assert(!STHVReadRequest(A, &s) && !STHVReadLayout(A, &s));
    STHVObserveRequests(CALLBACK(requestEvent));
    STHVObserveLayout(A, CALLBACK(layoutEvent));
    for (unsigned i = 0; i < 200; ++i) {
        ++clockMS;
        assert(STHVPublishRequest(A, YES, keyFor(i)));
        assert(STHVPublishLayout(A, i % 3 != 0, cardFor(i), keyFor(i)));
        STHVPublishProbe(A, cardFor(i), keyFor(i));
        assert(STHVReadRequest(A, &s) && s.active && STHVRequestOwner() == STHVKey(A));
        sameRect(s.card, (STHVRect){0});
        sameRect(s.keyboard, keyFor(i));
        assert(s.at == (double)clockMS / 1000.0);
        checkLayout(A, i, i % 3 != 0);
        STHVRect a, b;
        assert(STHVReadProbe(A, &a, &b));
        sameRect(a, cardFor(i)); sameRect(b, keyFor(i));
    }
    assert(!requestEvents && !layoutEvents); /* No inline notifications. */
    drain();
    assert(requestEvents == 1 && layoutEvents == 1); /* Coalescing is legal. */
    traceCount = 0; tracing = YES;
    assert(STHVReadLayout(A, &s));
    tracing = NO;
    assert(traceCount == 8 && strstr(trace[0], ".request.owner") &&
           strstr(trace[1], ".commit") && strstr(trace[2], ".card") &&
           strstr(trace[3], ".key") && strstr(trace[4], ".at") &&
           strstr(trace[5], ".authority") && !strcmp(trace[1], trace[6]) && !strcmp(trace[0], trace[7]));
}

static void failuresAndEmptyLayouts(void) {
    STHVSnapshot before, after;
    assert(STHVPublishLayout(A, YES, cardFor(4), keyFor(4)));
    assert(STHVReadLayout(A, &before));
    for (unsigned step = 1; step <= 5; ++step) {
        uint64_t commit = field(A, "layout", "commit");
        failSet = sets + step;
        assert(!STHVPublishLayout(A, NO, cardFor(9), keyFor(9)));
        assert(!failSet && field(A, "layout", "commit") == commit);
        assert(STHVReadLayout(A, &after) && after.serial == before.serial && after.active);
        sameRect(after.card, before.card); sameRect(after.keyboard, before.keyboard);
    }
    for (unsigned step = 1; step <= 8; ++step) {
        memset(&after, 0xa5, sizeof(after));
        unsigned char saved[sizeof(after)]; memcpy(saved, &after, sizeof(after));
        failGet = getCount + step;
        assert(!STHVReadLayout(A, &after) && !failGet);
        assert(!memcmp(saved, &after, sizeof(after)));
    }
    const STHVRect invalid[] = {{NAN,0,1,1}, {0,INFINITY,1,1}, {0,0,-1,1},
                                {0,0,1,INFINITY}, {12288,0,1,1}, {0,0,16384,1}};
    assert(STHVPublishRequest(A, YES, keyFor(3)));
    uint64_t layoutCommit = field(A, "layout", "commit");
    uint64_t requestCommit = field(A, "request", "commit");
    uint64_t probeCommit = field(A, "probe", "commit");
    for (unsigned i = 0; i < sizeof(invalid) / sizeof(invalid[0]); ++i) {
        assert(!STHVPublishLayout(A, YES, invalid[i], keyFor(2)));
        assert(!STHVPublishLayout(A, YES, cardFor(2), invalid[i]));
        assert(!STHVPublishRequest(A, NO, invalid[i]));
        assert(!STHVRenewRequest(A, invalid[i]));
        STHVPublishProbe(A, invalid[i], (STHVRect){0});
        assert(field(A, "layout", "commit") == layoutCommit &&
               field(A, "request", "commit") == requestCommit &&
               field(A, "probe", "commit") == probeCommit);
    }
    assert(STHVPublishLayout(A, NO, cardFor(6), (STHVRect){0}));
    assert(STHVReadLayout(A, &after) && !after.active);
    sameRect(after.card, cardFor(6)); sameRect(after.keyboard, (STHVRect){0});
    assert(STHVPublishLayout(A, NO, (STHVRect){0}, (STHVRect){0}));
    assert(STHVReadLayout(A, &after) && !after.active);
    sameRect(after.card, (STHVRect){0});
    /* Registration failures are retryable, not permanently cached as invalid. */
    NSString *fresh = STR("test.stheno.viewport32.registration");
    failRegister = registrations + 3;
    assert(!STHVPublishLayout(fresh, YES, cardFor(2), keyFor(2)) && !failRegister);
    assert(STHVPublishLayout(fresh, YES, cardFor(2), keyFor(2)));
    checkLayout(fresh, 2, YES);
    /* Even if owner installation fails, the preceding commit is never mixed. */
    failSet = sets + 6;
    assert(!STHVPublishRequest(B, YES, keyFor(8)) && !failSet);
    assert(STHVRequestOwner() == STHVKey(A));
    assert(STHVReadRequest(B, &after) && after.active);
    sameRect(after.keyboard, keyFor(8));
}

static unsigned switched, generation;
static BOOL alwaysSwitch;
static void switchSlots(const char *name) {
    if (!isData(name, "layout", "card")) return;
    ++switched;
    if (!alwaysSwitch) afterRead = NULL;
    /* Two flips overwrite the slot the reader is currently sampling. */
    ++generation;
    assert(STHVPublishLayout(A, YES, cardFor(generation), keyFor(generation)));
    ++generation;
    assert(STHVPublishLayout(A, YES, cardFor(generation), keyFor(generation)));
}
static void switchOwner(const char *name) {
    if (!isData(name, "request", "key")) return;
    afterRead = NULL;
    ++switched;
    assert(STHVPublishRequest(B, YES, keyFor(77)));
}
static void claimDuringRenew(const char *name) {
    if (!isData(name, "request", "card")) return;
    afterWrite = NULL;
    assert(STHVPublishRequest(B, YES, keyFor(78)));
}
static void consistencySwitches(void) {
    assert(STHVPublishLayout(A, YES, cardFor(1), keyFor(1)));
    generation = 20; switched = 0; alwaysSwitch = NO; afterRead = switchSlots;
    STHVSnapshot s;
    assert(STHVReadLayout(A, &s) && switched == 1);
    sameRect(s.card, cardFor(generation)); sameRect(s.keyboard, keyFor(generation));
    switched = 0; alwaysSwitch = YES; afterRead = switchSlots;
    memset(&s, 0xa5, sizeof(s));
    unsigned char saved[sizeof(s)]; memcpy(saved, &s, sizeof(s));
    assert(!STHVReadLayout(A, &s) && switched == 3); /* Exactly three attempts. */
    assert(!memcmp(saved, &s, sizeof(s)));
    afterRead = NULL;
    assert(STHVPublishRequest(A, YES, keyFor(4)));
    switched = 0; afterRead = switchOwner;
    assert(STHVRequestOwner() == STHVKey(B) && switched == 1);
    assert(STHVPublishRequest(A, YES, keyFor(4)));
    afterRead = switchOwner;
    /* Per-bundle reads are not ownership filters, including inactive records. */
    assert(STHVReadRequest(A, &s) && s.owner == STHVKey(A));
    sameRect(s.keyboard, keyFor(4));
    assert(STHVRequestOwner() == STHVKey(B));
}

static void ownerAndRenewal(void) {
    STHVSnapshot a, b;
    assert(STHVPublishRequest(A, YES, (STHVRect){0}));
    assert(STHVReadRequest(A, &a) && a.active);
    sameRect(a.keyboard, (STHVRect){0}); /* Focus-only is not a synthetic frame. */
    uint64_t writes = ownerWrites;
    for (unsigned i = 1; i <= 4; ++i) {
        clockMS += 1000;
        assert(STHVRenewRequest(A, keyFor(i)) && ownerWrites == writes);
        assert(STHVReadRequest(A, &b) && b.serial == a.serial + 1 && b.at > a.at);
        sameRect(b.keyboard, keyFor(i)); a = b;
    }
    assert(STHVPublishRequest(B, YES, keyFor(5)));
    writes = ownerWrites;
    assert(!STHVRenewRequest(A, keyFor(6)) && ownerWrites == writes);
    assert(STHVReadRequest(A, &b) && b.serial == a.serial);
    assert(STHVPublishRequest(A, NO, (STHVRect){0}));
    assert(STHVReadRequest(A, &b) && !b.active);
    assert(STHVRequestOwner() == STHVKey(B) && ownerWrites == writes);
    assert(!STHVRenewRequest(A, keyFor(6)) && ownerWrites == writes);
    assert(STHVPublishRequest(B, NO, (STHVRect){0}));
    assert(STHVReadRequest(B, &b) && !b.active && !STHVRequestOwner());
    assert(!STHVRenewRequest(B, keyFor(6)));
    /* A claim landing halfway through A's renewal must survive it. */
    assert(STHVPublishRequest(A, YES, keyFor(1)));
    writes = ownerWrites; afterWrite = claimDuringRenew;
    assert(!STHVRenewRequest(A, keyFor(2)) && !afterWrite);
    assert(ownerWrites == writes + 1 && STHVRequestOwner() == STHVKey(B));
    assert(STHVReadRequest(B, &b)); sameRect(b.keyboard, keyFor(78));
    assert(STHVPublishRequest(A, NO, (STHVRect){0}));
    assert(STHVRequestOwner() == STHVKey(B));
}

static void freshnessAndProbes(void) {
    STHVSnapshot s;
    assert(STHVPublishRequest(A, YES, keyFor(1)));
    assert(STHVPublishLayout(A, YES, cardFor(1), keyFor(1)));
    uint64_t start = clockMS, rc = field(A, "request", "commit");
    uint64_t lc = field(A, "layout", "commit");
    clockMS = start + 2000;
    assert(STHVReadRequest(A, &s) && STHVRequestOwner() == STHVKey(A));
    clockMS++;
    assert(!STHVReadRequest(A, &s) && !STHVRequestOwner());
    assert(!STHVRenewRequest(A, keyFor(1))); /* No resurrection of an expired lease. */
    clockMS = start + 3000;
    assert(STHVReadLayout(A, &s));
    clockMS++;
    assert(!STHVReadLayout(A, &s));
    drain();
    assert(field(A, "request", "commit") == rc && field(A, "layout", "commit") == lc);
    assert(STHVPublishRequest(A, NO, (STHVRect){0}));
    assert(STHVReadRequest(A, &s) && !s.active);
    assert(STHVPublishLayout(A, NO, cardFor(3), (STHVRect){0}));
    --clockMS; /* Future timestamps are rejected, not treated as recent. */
    assert(!STHVReadRequest(A, &s) && !STHVReadLayout(A, &s));
    ++clockMS;
    drain();
    unsigned re = requestEvents, le = layoutEvents;
    lc = field(A, "layout", "commit"); rc = field(A, "request", "commit");
    STHVPublishProbe(A, (STHVRect){0}, (STHVRect){0});
    STHVRect a, b;
    assert(STHVReadProbe(A, &a, &b));
    sameRect(a, (STHVRect){0}); sameRect(b, (STHVRect){0});
    STHVPublishProbe(A, cardFor(4), cardFor(4));
    uint64_t pc = field(A, "probe", "commit");
    failSet = sets + 2;
    STHVPublishProbe(A, cardFor(5), keyFor(5));
    assert(!failSet && field(A, "probe", "commit") == pc);
    clockMS += 100000000;
    denyOwner = YES; tracing = YES; traceCount = 0;
    assert(STHVReadProbe(A, &a, &b));
    tracing = NO; denyOwner = NO;
    assert(traceCount == 6); /* commit/data/commit, no owner or age dependency. */
    sameRect(a, cardFor(4)); sameRect(b, cardFor(4));
    uint64_t savedClock = clockMS; clockMS = UINT64_MAX;
    assert(STHVReadProbe(A, NULL, NULL)); clockMS = savedClock;
    drain();
    assert(re == requestEvents && le == layoutEvents &&
           lc == field(A, "layout", "commit") && rc == field(A, "request", "commit"));
}

static void mainThreadAndGeneration(void) {
    uint64_t r = registrations, g = getCount, w = sets;
    unsigned observersBefore = observerCount;
    STHVSnapshot s;
    STHVRect a = cardFor(1), b = keyFor(1);
    mainThread = NO;
    assert(STHVKey(A));
    assert(!STHVPublishRequest(A, YES, b) && !STHVRenewRequest(A, b));
    assert(!STHVReadRequest(A, &s) && !STHVRequestOwner());
    assert(!STHVPublishLayout(A, YES, a, b) && !STHVReadLayout(A, &s));
    STHVPublishProbe(A, a, b);
    assert(!STHVReadProbe(A, &a, &b));
    STHVObserveRequests(CALLBACK(requestEvent));
    STHVObserveLayout(A, CALLBACK(layoutEvent));
    mainThread = YES;
    assert(registrations == r && getCount == g && sets == w && observerCount == observersBefore);
    sameRect(a, cardFor(1)); sameRect(b, keyFor(1));
    assert(!STHVPublishRequest(NULL, YES, a) && !STHVReadRequest(STR(""), &s));
    /* Adopt the shared generation, not a process-local writer counter. */
    assert(STHVPublishLayout(A, YES, cardFor(1), keyFor(1)));
    char name[128];
    snprintf(name, sizeof(name), PFX ".layout.%016" PRIx64 ".commit", STHVKey(A));
    int index = word(name, NO); assert(index >= 0);
    words[index].value = (UINT64_C(1) << 63) | 1000;
    assert(STHVPublishLayout(A, YES, cardFor(2), keyFor(2)));
    assert(STHVReadLayout(A, &s) && s.serial == 1001);
    words[index].value = UINT64_MAX; /* Saturation fails before any data write. */
    w = sets;
    assert(!STHVPublishLayout(A, YES, cardFor(3), keyFor(3)) && sets == w);
}

static void safeResumeAndEvent(void){
    assert(STHVPublishRequest(A,YES,keyFor(1)));STHVSnapshot first,after;
    assert(STHVReadRequest(A,&first)&&first.event);
    clockMS+=2501;assert(!STHVRenewRequest(A,keyFor(1)));
    uint64_t ownerBefore=ownerWrites;
    assert(STHVResumeRequest(A,keyFor(1))&&ownerWrites==ownerBefore);
    assert(STHVReadRequest(A,&after)&&after.event==first.event&&after.active);
    assert(STHVPublishRequest(B,YES,keyFor(2)));
    assert(!STHVResumeRequest(A,keyFor(1))&&STHVRequestOwner()==STHVKey(B));
    assert(STHVPublishRequest(B,NO,(STHVRect){0}));
    assert(!STHVResumeRequest(B,keyFor(2)));
    assert(STHVPublishRequest(A,YES,keyFor(3)));
    assert(STHVReadRequest(A,&after)&&after.event>first.event);
}
static int fakeMain(void) {
    hashAndRoundTrips();
    failuresAndEmptyLayouts();
    consistencySwitches();
    ownerAndRenewal();
    freshnessAndProbes();
    safeResumeAndEvent();
    STHVSnapshot authority={0};
    assert(STHVPublishLayoutState(A,YES,cardFor(2),keyFor(2),456,YES));
    assert(STHVReadLayout(A,&authority)&&authority.hosted&&authority.keyboardVisible&&authority.physicalGeneration==456);
    uint64_t previous=field(A,"layout","commit");
    for(unsigned step=1;step<=5;step++){
        failSet=sets+step;
        assert(!STHVPublishLayoutState(A,NO,cardFor(3),(STHVRect){0},457,NO));
        assert(field(A,"layout","commit")==previous);
        assert(STHVReadLayout(A,&authority)&&authority.keyboardVisible&&authority.physicalGeneration==456);
    }
    assert(STHVPublishLayoutState(A,NO,cardFor(3),(STHVRect){0},457,NO));
    assert(STHVReadLayout(A,&authority)&&authority.hosted&&!authority.keyboardVisible&&authority.physicalGeneration==457);
    assert(!STHVPublishLayoutState(A,YES,cardFor(3),keyFor(3),0,YES));
    mainThreadAndGeneration();
    puts("ViewportBus fake: 200 round trips, torn writes, owner/commit retries, inactive baselines, safe renewal, freshness and probe isolation passed");
    return 0;
}
#if defined(__APPLE__)
int main(void) { @autoreleasepool { return fakeMain(); } }
#else
int main(void) { return fakeMain(); }
#endif

#else /* Real Darwin transport regression; run on macOS, not the portable host. */
#include <spawn.h>
#include <sys/wait.h>
extern char **environ;
static void child(const char *executable, NSString *bundle, unsigned index) {
    char number[24]; snprintf(number, sizeof(number), "%u", index);
    char *arguments[] = {(char *)executable, (char *)"--read",
                         (char *)bundle.UTF8String, number, NULL};
    pid_t pid;
    assert(posix_spawnp(&pid, executable, NULL, NULL, arguments, environ) == 0);
    int status;
    assert(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 4 && !strcmp(argv[1], "--read")) {
            NSString *bundle = [NSString stringWithUTF8String:argv[2]];
            unsigned i = (unsigned)strtoul(argv[3], NULL, 10);
            STHVSnapshot s;
            assert(STHVReadRequest(bundle, &s) && s.active);
            assert(STHVRequestOwner() == STHVKey(bundle));
            sameRect(s.keyboard, keyFor(i));
            checkLayout(bundle, i, i % 3 != 0);
            STHVRect a, b;
            assert(STHVReadProbe(bundle, &a, &b));
            sameRect(a, cardFor(i)); sameRect(b, keyFor(i));
            return 0;
        }
        NSString *a = [@"test.stheno.viewport32." stringByAppendingString:NSUUID.UUID.UUIDString];
        for (unsigned i = 0; i < 200; ++i) {
            assert(STHVPublishRequest(a, YES, keyFor(i)));
            assert(STHVPublishLayout(a, i % 3 != 0, cardFor(i), keyFor(i)));
            STHVPublishProbe(a, cardFor(i), keyFor(i));
            child(argv[0], a, i); /* Separate address space, fresh registrations. */
        }
        NSString *b = [a stringByAppendingString:@".other"];
        assert(STHVPublishRequest(b, YES, keyFor(7)));
        assert(!STHVRenewRequest(a, keyFor(8)));
        assert(STHVPublishRequest(a, NO, (STHVRect){0}));
        STHVSnapshot s;
        assert(STHVReadRequest(a, &s) && !s.active && STHVRequestOwner() == STHVKey(b));
        assert(STHVPublishLayout(b, YES, cardFor(7), keyFor(7)));
        STHVPublishProbe(b, cardFor(7), keyFor(7));
        child(argv[0], b, 7);
        assert(STHVPublishRequest(b, NO, (STHVRect){0}) && !STHVRequestOwner());
        puts("ViewportBus notifyd: 200 separate-process readers and late inactive/renew handoff passed");
    }
    return 0;
}
#endif
