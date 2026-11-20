#define STH_DEFAULT_SIZE_TEST 1
#include <assert.h>
#include <stdio.h>
#import "DefaultSize.m"
static int shows,resets;
void STHNativePresent(void *m){shows++;}
void STHNativeInitialSize(void *m){resets++;}
int main(void){@autoreleasepool{
 NSObject *a=[NSObject new],*b=[NSObject new];
 STHFirstPresentation((__bridge void *)a);assert(shows==1&&resets==1);
 STHFirstPresentation((__bridge void *)a);assert(shows==2&&resets==1);
 STHFirstPresentation((__bridge void *)b);assert(shows==3&&resets==2);
 STHFirstPresentation(NULL);assert(shows==3&&resets==2);
 puts("Initial size/center lifecycle passed: each fresh model only; repeated presentation and restored models untouched");
}return 0;}
