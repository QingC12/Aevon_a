#import <UIKit/UIKit.h>
#include <math.h>
#import "SystemActionCatalog.h"

// Return the icon content only. The ORIGINAL SwiftUI row/ring supplies the
// same frame, circular carrier, shadow, scale and hit target as every app.
UIImage *STHSystemActionIcon(NSString *identifier,CGFloat requestedScale){
 STHSystemAction action=STHSystemActionForIdentifier(identifier.UTF8String);
 if(action==STHSystemActionNone)return nil;
 CGFloat scale=isfinite(requestedScale)&&requestedScale>=1&&requestedScale<=4?requestedScale:UIScreen.mainScreen.scale;
 if(scale<1||scale>4)scale=2;
 static NSCache<NSString *,UIImage *> *cache;
 static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=12;});
 NSString *key=[NSString stringWithFormat:@"%d:%.2f",action,(double)scale];
 UIImage *cached=[cache objectForKey:key];if(cached)return cached;
 UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
 format.scale=scale;format.opaque=NO;
 UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60,60) format:format];
 UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx){
  CGContextRef c=ctx.CGContext;
  [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,60,60) cornerRadius:13.2] addClip];
  UIColor *top=action==STHSystemActionScreenshot?[UIColor colorWithRed:.17 green:.59 blue:1 alpha:1]:[UIColor colorWithRed:1 green:.28 blue:.36 alpha:1];
  UIColor *bottom=action==STHSystemActionScreenshot?[UIColor colorWithRed:.24 green:.31 blue:.87 alpha:1]:[UIColor colorWithRed:.81 green:.08 blue:.21 alpha:1];
  CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
  NSArray *colors=@[(__bridge id)top.CGColor,(__bridge id)bottom.CGColor];
  CGGradientRef gradient=CGGradientCreateWithColors(space,(__bridge CFArrayRef)colors,NULL);
  CGContextDrawLinearGradient(c,gradient,CGPointMake(5,0),CGPointMake(55,60),0);
  CGGradientRelease(gradient);CGColorSpaceRelease(space);
  CGContextSetStrokeColorWithColor(c,UIColor.whiteColor.CGColor);
  CGContextSetFillColorWithColor(c,UIColor.whiteColor.CGColor);
  CGContextSetLineCap(c,kCGLineCapRound);CGContextSetLineJoin(c,kCGLineJoinRound);
  if(action==STHSystemActionScreenshot){
   // Four capture corners, plus a crisp rectangular screen in the center.
   CGContextSetLineWidth(c,3.4);
   const CGFloat l=12,r=48,t=13,b=47,n=8;
   CGContextMoveToPoint(c,l,t+n);CGContextAddLineToPoint(c,l,t);CGContextAddLineToPoint(c,l+n,t);
   CGContextMoveToPoint(c,r-n,t);CGContextAddLineToPoint(c,r,t);CGContextAddLineToPoint(c,r,t+n);
   CGContextMoveToPoint(c,r,b-n);CGContextAddLineToPoint(c,r,b);CGContextAddLineToPoint(c,r-n,b);
   CGContextMoveToPoint(c,l+n,b);CGContextAddLineToPoint(c,l,b);CGContextAddLineToPoint(c,l,b-n);
   CGContextStrokePath(c);
   UIBezierPath *screen=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(20,21,20,18) cornerRadius:2];screen.lineWidth=2.3;[screen stroke];
  }else{
   CGContextSetLineWidth(c,3.6);
   CGContextStrokeEllipseInRect(c,CGRectMake(13,13,34,34));
   CGContextFillEllipseInRect(c,CGRectMake(20,20,20,20));
  }
 }];
 image=[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
 if(image)[cache setObject:image forKey:key];return image;
}
NSString *STHSystemActionDisplayName(NSString *identifier){
 switch(STHSystemActionForIdentifier(identifier.UTF8String)){
  case STHSystemActionScreenshot:return @"截图";
  case STHSystemActionScreenRecording:return @"录屏";
  default:return nil;
 }
}
