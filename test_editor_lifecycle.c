#include <assert.h>
#include <stdio.h>
#include "EditorSession.h"
#include "EditorAssembly.h"
int main(void){
 STHEditorSession s={0};
 for(int i=0;i<100;i++){
  uint64_t before=s.generation;
  assert(STHEditorShow(&s));assert(s.active&&!s.closing&&s.generation==before+1);
  assert(!STHEditorShow(&s)); // WillShow, DidShow share one generation
  assert(STHEditorWillHide(&s));assert(!s.active&&s.closing);
  assert(STHEditorShow(&s)); // next WillShow before old DidHide
  uint64_t fresh=s.generation;
  assert(!STHEditorDidHide(&s));assert(s.active&&s.generation==fresh);
  assert(STHEditorWillHide(&s));assert(STHEditorDidHide(&s));assert(!s.active);
 }
 STHEditorInvalidate(&s);assert(!s.active&&!s.closing);
 assert(STHEditorContainer(400,58,430,731,false));
 assert(!STHEditorContainer(430,731,430,731,false));
 assert(!STHEditorContainer(400,58,430,731,true));
 // A comment toolbar can have an unknown private class. Geometric connection
 // and control evidence suffice; multi-pass grouping can join another row.
 STHRect input={10,410,400,50},toolbar={10,460,400,40},emoji={10,500,400,70};
 assert(STHEditorAttachedRow(input,toolbar,731,true));
 STHRect joined={10,410,400,90};assert(STHEditorAttachedRow(joined,emoji,731,true));
 assert(STHEditorAttachedRow(joined,(STHRect){10,500,400,200},731,true)); // bounded emoji collection
 assert(!STHEditorAttachedRow(input,emoji,731,true)); // not contiguous until toolbar joins
 assert(!STHEditorAttachedRow(input,(STHRect){10,50,400,50},731,true));
 assert(!STHEditorAttachedRow(input,(STHRect){10,460,400,400},731,true));
 assert(!STHEditorAttachedRow(input,(STHRect){450,460,400,50},731,true));
 assert(STHComposerLift(410,570,490,731)==80);
 assert(STHComposerLift(410,485,490,731)==0);
 puts("100 editor show cycles and late-hide interleavings passed; private nested toolbar/emoji rows stay contiguous and scoped");
 return 0;
}
