#ifndef STH_CENTER_CHOOSER_BRIDGE_H
#define STH_CENTER_CHOOSER_BRIDGE_H
#include <stdint.h>

enum STHCenterPanPhase {
 STHCenterPanBegan = 0,
 STHCenterPanChanged = 1,
 STHCenterPanWillFinish = 2,
 STHCenterPanDidFinish = 3,
};

// Arguments are borrowed only for this call; phases are encoded in the core shim.
void STHCenterRingPan(void *ring, void *recognizer, uint32_t phase);
int64_t STHCenterRingSelected(void *ring);
#endif
