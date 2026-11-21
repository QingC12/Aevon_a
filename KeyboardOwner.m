#import <Foundation/Foundation.h>
#import "KeyboardFocusBus.h"
extern void *STHDockCopyFloating(void);
extern size_t STHChooserManagersCount(void *);
extern void *STHChooserCopyManagerAt(size_t,void *);
extern void STHChooserReleaseArray(void *),STHChooserReleaseSwift(void *);
extern BOOL STHDockNativeMinimized(void *);
extern void *STHSystemCopyModelIdentifier(void *);
// The returned model is +1. Claims from non-floating apps never select a card.
void *STHCopyInputFocusedModelWithFrame(STHRect *frame){
 if(frame)*frame=(STHRect){0,0,0,0};
 if(!NSThread.isMainThread)return NULL;
 void *array=STHDockCopyFloating();if(!array)return NULL;
 void *result=NULL;
 @try{
  size_t count=STHChooserManagersCount(array);if(count>4096)return NULL;
  for(size_t i=0;i<count;i++){
   void *model=STHChooserCopyManagerAt(i,array);if(!model)continue;
   BOOL match=NO;
   @try{
    if(!STHDockNativeMinimized(model)){
     NSString *bundle=CFBridgingRelease(STHSystemCopyModelIdentifier(model));
     match=STHReadInputFocus(bundle);
     if(match&&frame)STHReadInputKeyboard(bundle,frame);
    }
   }@finally{if(!match)STHChooserReleaseSwift(model);}
   if(match){result=model;break;}
  }
 }@finally{STHChooserReleaseArray(array);}
 return result;
}
void *STHCopyInputFocusedModel(void){return STHCopyInputFocusedModelWithFrame(NULL);}
