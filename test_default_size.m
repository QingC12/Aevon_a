#define STH_DEFAULT_SIZE_TEST 1
#include <assert.h>
#include <stdio.h>
#import "DefaultSize.m"
static int shows,resets;static BOOL minimized;static int unminimized;
void STHNativePresent(void *m){assert(!minimized);shows++;}
void STHNativeInitialSize(void *m){resets++;}
BOOL STHNativeMinimized(void *m){return minimized;}
void STHNativeSetMinimized(void *m,BOOL value){minimized=value;unminimized++;}
int main(void){@autoreleasepool{
 NSObject *a=[NSObject new],*b=[NSObject new];
 STHFirstPresentation((__bridge void *)a);assert(shows==1&&resets==1);
 STHFirstPresentation((__bridge void *)a);assert(shows==2&&resets==1);
 STHFirstPresentation((__bridge void *)b);assert(shows==3&&resets==2);
 minimized=YES;STHFirstPresentation((__bridge void *)b);assert(!minimized&&unminimized==1);
 STHFirstPresentation(NULL);assert(shows==4&&resets==2);
 puts("Presentation lifecycle passed: unminimize before present; initial size only once per model");
}return 0;}
