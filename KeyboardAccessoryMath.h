#ifndef STH_KEYBOARD_ACCESSORY_MATH_H
#define STH_KEYBOARD_ACCESSORY_MATH_H
#include "LayoutMath.h"
// Only call for a responder-declared inputAccessoryView. A toolbar-like name
// or UIKit wrapper class alone is not evidence that a view belongs to the app.
static inline bool STHExcludeAppAccessory(STHRect keys,STHRect appRow,double sw,double sh,STHRect *result){
 if(!STHFiniteRect(keys)||!STHFiniteRect(appRow)||sw<=1||sh<=1)return false;
 if(appRow.w<sw*.6||appRow.h>=sh*.35||appRow.y>keys.y+2||
    appRow.y+appRow.h<=keys.y||appRow.y+appRow.h>=keys.y+keys.h-60)return false;
 *result=(STHRect){keys.x,appRow.y+appRow.h,keys.w,keys.y+keys.h-appRow.y-appRow.h};
 return true;
}
#endif
