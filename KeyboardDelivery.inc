// Included by KeyboardCoordinates.m so preparation happens at DELIVERY, not
// independently during each app observer's userInfo read.
static void (*centerPost)(id,SEL,NSNotification *);
static void (*centerPostName)(id,SEL,NSString *,id,NSDictionary *);
static __thread BOOL delivering;
static BOOL heldSession,awaitingDidHide;
static BOOL keyboardEvent(NSString *name){return [name hasPrefix:@"UIKeyboard"]&&
 ([name isEqualToString:UIKeyboardWillShowNotification]||[name isEqualToString:UIKeyboardDidShowNotification]||
  [name isEqualToString:UIKeyboardWillChangeFrameNotification]||[name isEqualToString:UIKeyboardDidChangeFrameNotification]||
  [name isEqualToString:UIKeyboardWillHideNotification]||[name isEqualToString:UIKeyboardDidHideNotification]);}
static BOOL hideEvent(NSString *n){return [n isEqualToString:UIKeyboardWillHideNotification]||[n isEqualToString:UIKeyboardDidHideNotification];}
static void deliverFrozen(NSNotificationCenter *center,NSNotification *note){
 NSDictionary *info=normalizedInfo(note,@selector(userInfo));
 // One immutable dictionary for every callback during this post. Original
 // KeyboardFix's postName rewrite is bypassed only for an active hosted app.
 NSNotification *frozen=[NSNotification notificationWithName:note.name object:note.object userInfo:info];
 objc_setAssociatedObject(frozen,&normalizedKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 BOOL was=delivering;delivering=YES;
 @try{centerPost(center,@selector(postNotification:),frozen);}@finally{delivering=was;}
}
static void discardHeld(void){}
static BOOL interceptNotification(NSNotificationCenter *center,NSNotification *note){
 if(center!=NSNotificationCenter.defaultCenter||delivering||![NSThread isMainThread]||!keyboardEvent(note.name)||objc_getAssociatedObject(note,&normalizedKey))return NO;
 BOOL will=[note.name isEqualToString:UIKeyboardWillShowNotification]||[note.name isEqualToString:UIKeyboardWillChangeFrameNotification];
 if(will){publishActualInputFocus(NO);publishActualKeyboardFrame(note);}
 else if([note.name isEqualToString:UIKeyboardWillHideNotification])publishActualInputFocus(YES);
 int status=STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier);
 BOOL hide=hideEvent(note.name);
 if(hide){
  if(!status&&!heldSession&&!session.visible&&!session.hasSceneFrame&&!awaitingDidHide)return NO;
  if(!prepareKeyboardLifecycle(note.name,status))return YES;
  awaitingDidHide=[note.name isEqualToString:UIKeyboardWillHideNotification];
  discardHeld();heldSession=NO;deliverFrozen(center,note);return YES;
 }
 awaitingDidHide=NO;
 if(status==1||status==2){
  if(!prepareKeyboardLifecycle(note.name,status))return YES;
  // Synchronous original Will timing. Pending uses a validated physical frame
  // plus predicted full-width card, or returns native data untouched.
  heldSession=YES;deliverFrozen(center,note);return YES;
 }
 return NO;
}
static void stablePost(id center,SEL selector,NSNotification *note){
 if(!interceptNotification(center,note))centerPost(center,selector,note);
}
static void stablePostName(id center,SEL selector,NSString *name,id object,NSDictionary *info){
 if(!delivering&&[NSThread isMainThread]&&keyboardEvent(name)){
  NSNotification *note=[NSNotification notificationWithName:name object:object userInfo:info];
  if(interceptNotification(center,note))return;
 }
 centerPostName(center,selector,name,object,info);
}
static void installDelivery(void){
 Method p=class_getInstanceMethod(NSNotificationCenter.class,@selector(postNotification:));
 Method n=class_getInstanceMethod(NSNotificationCenter.class,@selector(postNotificationName:object:userInfo:));
 if(!p||!n)return;
 centerPost=(void *)method_getImplementation(p);centerPostName=(void *)method_getImplementation(n);
 method_setImplementation(p,(IMP)stablePost);method_setImplementation(n,(IMP)stablePostName);
}
