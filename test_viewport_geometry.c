#include "ViewportGeometry.h"
#include <float.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
#define CHECK(condition) do { \
    ++checks; \
    if (!(condition)) { \
        fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); \
        exit(EXIT_FAILURE); \
    } \
} while (0)

static void expect_rect(STHVRect actual, STHVRect expected)
{
    ++checks;
    if (!STHVNear(actual, expected, 1e-9)) {
        fprintf(stderr, "FAIL rect: {%.17g,%.17g,%.17g,%.17g} != "
                "{%.17g,%.17g,%.17g,%.17g}\n",
                actual.x, actual.y, actual.w, actual.h,
                expected.x, expected.y, expected.w, expected.h);
        exit(EXIT_FAILURE);
    }
}

static void test_validation(void)
{
    CHECK(STHVValid((STHVRect){-20, -30, 400, 800}));
    const STHVRect invalid[] = {
        {0, 0, 0, 1}, {0, 0, 1, 0}, {0, 0, -1, 1}, {0, 0, 1, -1},
        {NAN, 0, 1, 1}, {0, INFINITY, 1, 1},
        {0, 0, INFINITY, 1}, {0, 0, 1, NAN},
        {DBL_MAX, 0, DBL_MAX, 1}
    };
    for (size_t i = 0; i < sizeof invalid / sizeof invalid[0]; ++i)
        CHECK(!STHVValid(invalid[i]));
    STHVRect r = {1, 2, 3, 0};
    CHECK(STHVNear(r, r, 0));
    CHECK(STHVNear(r, (STHVRect){1.25, 2.25, 3.25, 0.25}, 0.25));
    CHECK(!STHVNear(r, (STHVRect){1.25, 2, 3, 0}, 0.249));
    CHECK(!STHVNear(r, r, -1));
    CHECK(!STHVNear(r, r, NAN));
    CHECK(!STHVNear(r, r, INFINITY));
    CHECK(!STHVNear(r, (STHVRect){NAN, 2, 3, 0}, 1));

    STHVRect screen = {100, 50, 400, 800};
    CHECK(STHVKeyboard((STHVRect){100, 550, 400, 300}, screen));
    CHECK(STHVKeyboard((STHVRect){100, 550, 280, 300}, screen));
    CHECK(STHVKeyboard((STHVRect){100, 790, 400, 60}, screen));
    CHECK(STHVKeyboard((STHVRect){100, 250, 400, 600}, screen));
    CHECK(STHVKeyboard((STHVRect){100, 530, 400, 300}, screen));
    CHECK(STHVKeyboard((STHVRect){100, 570, 400, 300}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 550, 279.99, 300}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 790.01, 400, 59.99}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 249.99, 400, 600.01}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 529, 400, 300}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 571, 400, 300}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 49, 400, 300}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 850, 400, 60}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 650, 200, 200}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 850, 400, 0}, screen));
    CHECK(!STHVKeyboard((STHVRect){NAN, 550, 400, 300}, screen));
    CHECK(!STHVKeyboard((STHVRect){100, 550, 400, 300}, (STHVRect){0}));
}

static void test_target(void)
{
    STHVRect screen = {20, 30, 400, 800};
    STHVRect keyboard = {20, 530, 400, 300};
    STHVRect before = keyboard;
    expect_rect(STHVTarget((STHVRect){100, 200, 200, 300}, screen, keyboard),
                (STHVRect){20, 50, 400, 600});
    expect_rect(STHVTarget((STHVRect){80, 650, 200, 100}, screen, keyboard),
                (STHVRect){20, 480, 400, 200});
    expect_rect(STHVTarget((STHVRect){80, 40, 200, 200}, screen, keyboard),
                (STHVRect){20, 30, 400, 400});
    expect_rect(STHVTarget((STHVRect){60, 500, 100, 100}, screen, keyboard),
                (STHVRect){20, 350, 400, 400});
    expect_rect(STHVTarget((STHVRect){60, 500, 800, 200}, screen, keyboard),
                (STHVRect){20, 505, 400, 100});
    expect_rect(STHVTarget((STHVRect){80, 50, 100, 800}, screen, keyboard),
                (STHVRect){170, 30, 100, 800});
    expect_rect(STHVTarget((STHVRect){80, 100, 200, 20},
                           (STHVRect){20, 30, 400, 160},
                           (STHVRect){20, 70, 400, 120}),
                (STHVRect){20, 60, 400, 40});
    expect_rect(STHVTarget((STHVRect){80, 650, 200, 100}, screen,
                           (STHVRect){0}), (STHVRect){20, 600, 400, 200});
    expect_rect(STHVTarget((STHVRect){0}, screen, keyboard), (STHVRect){0});
    expect_rect(STHVTarget(screen, (STHVRect){0}, keyboard), (STHVRect){0});
    CHECK(STHVNear(keyboard, before, 0));
    STHVRect low = STHVTarget((STHVRect){40, 700, 320, 500},
                              (STHVRect){0, 0, 400, 850},
                              (STHVRect){0, 550, 400, 300});
    CHECK(low.y >= 0 && low.y + low.h <= 850);
    STHVRect lowMapped = STHVMap(low, (STHVRect){0, 550, 400, 300},
                                (STHVRect){0, 0, 400, 625});
    CHECK(STHVInset(lowMapped, (STHVRect){0, 0, 400, 625}) > 0);
}

static void test_map(void)
{
    STHVRect card = {100, 200, 200, 400};
    STHVRect scene = {10, 20, 400, 800};
    STHVRect empty = {10, 820, 400, 0};
    STHVRect mapped = STHVMap(card, (STHVRect){0, 500, 500, 300}, scene);
    expect_rect(mapped, (STHVRect){10, 620, 400, 200});
    CHECK(STHVInset(mapped, scene) == 200);
    mapped = STHVMap(card, (STHVRect){250, 500, 100, 300}, scene);
    expect_rect(mapped, (STHVRect){310, 620, 100, 200});
    CHECK(STHVInset(mapped, scene) == 200);
    expect_rect(STHVMap(card, (STHVRect){150, 500, 100, 300},
                        (STHVRect){10, 20, 600, 1000}),
                (STHVRect){160, 770, 300, 250});
    expect_rect(STHVMap(card, (STHVRect){0, 0, 1000, 1000}, scene), scene);
    expect_rect(STHVMap(card, (STHVRect){100, 0, 200, 100}, scene), empty);
    expect_rect(STHVMap(card, (STHVRect){100, 100, 200, 100}, scene), empty);
    expect_rect(STHVMap(card, (STHVRect){300, 500, 100, 300}, scene), empty);
    expect_rect(STHVMap(card, (STHVRect){0, 500, 100, 300}, scene), empty);
    expect_rect(STHVMap(card, (STHVRect){100, 600, 200, 100}, scene), empty);
    expect_rect(STHVMap(card, (STHVRect){0}, scene), empty);
    expect_rect(STHVMap((STHVRect){NAN, 0, 1, 1}, card, scene), empty);
    expect_rect(STHVMap(card, card, (STHVRect){0}), (STHVRect){0});
    mapped = STHVMap(card, (STHVRect){125, 300, 100, 100}, scene);
    expect_rect(mapped, (STHVRect){60, 220, 200, 200});
    CHECK(STHVInset(mapped, scene) == 0);
}

static void test_dynamic_affine(void)
{
    const double scales[] = {0.3, 0.65, 1.0, 1.75, 3.2};
    for (size_t i = 0; i < sizeof scales / sizeof scales[0]; ++i) {
        double sx = scales[i], sy = scales[4 - i];
        double tx = 13.25 * (double)i - 91, ty = 9.5 * (double)i - 70;
        STHVRect card = {150 * sx + tx, 80 * sy + ty, 200 * sx, 400 * sy};
        STHVRect key = {250 * sx + tx, 380 * sy + ty, 200 * sx, 200 * sy};
        STHVRect scene = {-200 + 13 * (double)i, 31 - 7 * (double)i,
                           300 + 20 * (double)i, 600 - 30 * (double)i};
        STHVRect mapped = STHVMap(card, key, scene);
        expect_rect(mapped, (STHVRect){scene.x + 0.5 * scene.w,
                    scene.y + 0.75 * scene.h, 0.5 * scene.w, 0.25 * scene.h});
        CHECK(fabs(STHVInset(mapped, scene) - 0.25 * scene.h) < 1e-9);
    }
}

static void test_inset(void)
{
    STHVRect scene = {10, 20, 400, 800};
    CHECK(STHVInset((STHVRect){100, 620, 30, 200}, scene) == 200);
    CHECK(STHVInset((STHVRect){-100, 620, 110, 200}, scene) == 0);
    CHECK(STHVInset((STHVRect){410, 620, 100, 200}, scene) == 0);
    CHECK(STHVInset((STHVRect){10, 620, 400, 199.75}, scene) == 0);
    CHECK(STHVInset((STHVRect){0, -100, 1000, 2000}, scene) == 800);
    CHECK(STHVInset((STHVRect){10, 820, 400, 100}, scene) == 0);
    CHECK(STHVInset((STHVRect){20, 720, 200, 300}, scene) == 100);
    CHECK(STHVInset((STHVRect){10, 620, 0, 200}, scene) == 0);
    CHECK(STHVInset((STHVRect){10, 820, 400, 0}, scene) == 0);
    CHECK(STHVInset((STHVRect){NAN, 620, 400, 200}, scene) == 0);
    CHECK(STHVInset(scene, (STHVRect){0}) == 0);
    double one_ulp_below = nextafter(820.0, -INFINITY);
    CHECK(STHVInset((STHVRect){10, 620, 400, one_ulp_below - 620}, scene)
          == 200);
}

static void test_pack(void)
{
    const STHVRect exact[] = {
        {-4096, -4096, 0, 0}, {12287.75, 12287.75, 16383.75, 16383.75},
        {-123.5, -0.25, 390, 0}, {0, 0, 0, 0},
        {-4096, 12287.75, 16383.75, 0}, {12287.75, -4096, 0, 16383.75}
    };
    uint64_t payload;
    for (size_t i = 0; i < sizeof exact / sizeof exact[0]; ++i) {
        CHECK(STHVPackRect(exact[i], &payload));
        CHECK(STHVNear(STHVUnpackRect(payload), exact[i], 0));
    }
    CHECK(STHVPackRect(exact[0], &payload));
    CHECK(payload == 0);
    CHECK(STHVPackRect(exact[1], &payload));
    CHECK(payload == UINT64_MAX);
    CHECK(STHVPackRect((STHVRect){-4095.75, -4095.5, 0.75, 1}, &payload));
    CHECK(payload == UINT64_C(0x0004000300020001));
    CHECK(STHVPackRect((STHVRect){-1.125, -123.625, 25.125, 10.375}, &payload));
    expect_rect(STHVUnpackRect(payload), (STHVRect){-1, -123.5, 25.25, 10.5});
    STHVRect fractional = {-12.13, 36.14, 99.99, 0.01};
    CHECK(STHVPackRect(fractional, &payload));
    CHECK(STHVNear(fractional, STHVUnpackRect(payload), 0.125));

    const STHVRect bad[] = {
        {-4096.001, 0, 1, 1}, {12287.751, 0, 1, 1},
        {0, -4096.001, 1, 1}, {0, 12287.751, 1, 1},
        {0, 0, -0.001, 1}, {0, 0, 16383.751, 1},
        {0, 0, 1, -0.001}, {0, 0, 1, 16383.751},
        {NAN, 0, 1, 1}, {0, INFINITY, 1, 1},
        {0, 0, -INFINITY, 1}, {0, 0, 1, NAN},
        {nextafter(-4096.0, -INFINITY), 0, 1, 1},
        {nextafter(12287.75, INFINITY), 0, 1, 1},
        {0, 0, -DBL_MIN, 1}, {0, 0, 1, nextafter(16383.75, INFINITY)}
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; ++i) {
        payload = UINT64_MAX;
        CHECK(!STHVPackRect(bad[i], &payload));
        CHECK(payload == 0);
    }
    CHECK(!STHVPackRect(exact[0], NULL));
}

static void test_repeat(void)
{
    const STHVRect original = {100, 200, 200, 300};
    const STHVRect screen = {20, 30, 400, 800};
    const STHVRect keyboard = {20, 530, 400, 300};
    const STHVRect scene = {-5, 11, 400, 600};
    const STHVRect target = STHVTarget(original, screen, keyboard);
    const STHVRect mapped = STHVMap(target, keyboard, scene);
    const double inset = STHVInset(mapped, scene);
    expect_rect(target, (STHVRect){20, 50, 400, 600});
    expect_rect(mapped, (STHVRect){-5, 491, 400, 120});
    CHECK(inset == 120);
    STHVRect state = original, transported = keyboard;
    for (unsigned i = 0; i < 1000; ++i) {
        state = STHVTarget(state, screen, keyboard);
        CHECK(STHVNear(state, target, 0));
        CHECK(STHVNear(STHVTarget(original, screen, keyboard), target, 0));
        STHVRect next = STHVMap(state, keyboard, scene);
        CHECK(STHVNear(next, mapped, 0));
        CHECK(STHVInset(next, scene) == inset);
        uint64_t payload;
        CHECK(STHVPackRect(transported, &payload));
        transported = STHVUnpackRect(payload);
        CHECK(STHVNear(transported, keyboard, 0));
    }
    CHECK(STHVNear(keyboard, (STHVRect){20, 530, 400, 300}, 0));
    CHECK(STHVNear(original, (STHVRect){100, 200, 200, 300}, 0));
}

int main(void)
{
    test_validation();
    test_target();
    test_map();
    test_dynamic_affine();
    test_inset();
    test_pack();
    test_repeat();
    printf("PASS: %u checks; 1000 repeat cycles; pure C viewport geometry\n", checks);
    return EXIT_SUCCESS;
}
