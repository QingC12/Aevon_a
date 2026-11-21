void STHUpdateLayout(void){
 if(![NSThread isMainThread])return;
 id m=observedModel;
 if(m&&settling.active&&!settling.haveCommitted){
  // Keyboard.m calls here AFTER setting the full-width target, in the same
  // original WillShow transaction. Publish it immediately, do not wait160ms.
  STHNativeRefreshGeometry((__bridge void *)m);
  CGRect card=STHNativeRect((__bridge void *)m);
  // Will already supplied a validated physical frame. Avoid a keyboard-view
  // hierarchy walk on the first animation transaction.
  CGRect keys=usable(keyboardFrame,UIScreen.mainScreen.bounds)?keyboardFrame:physicalKeys();
  if(usable(keys,UIScreen.mainScreen.bounds)&&STHFiniteRect(rr(card))&&card.size.width>=40&&card.size.height>=40){
   settling.haveCommitted=YES;settling.committedCard=rr(card);settling.committedKeys=rr(keys);
   STHPublishLayout(observedBundle,card,keys,YES);lastHeartbeat=CACurrentMediaTime();

  }
  // The existing timer performs the next sample; do not repeat this work
  // synchronously before the first animation frame can render.
  return;
 }
 tick();
}
