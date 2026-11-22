// Bridge between the native iOS shell and the Go engine (exports in
// engine/src/util_ios.go, resolved at final link from libikemen.a).
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Go -> native
void        IKOverlayInstall(void);
void        IKOverlayInstallWindow(void *sdlWindow);   // SDL_Window* of the game window
void        IKOverlaySetSuspended(int suspended);
const char *IKPreferredLanguage(void);

// native -> Go
extern int  SDL_main(int argc, char **argv);
extern void IkemenTouchSetState(int player, uint32_t mask);
extern void IkemenTouchKey(int keycode, int down);
extern int  IkemenGameIsRunning(void);
extern int  IkemenPlayerFacing(int player);

#ifdef __cplusplus
}
#endif

// Game button bits (same order as the engine's [14]bool input arrays).
enum {
    IKBtnU = 1u << 0, IKBtnD = 1u << 1, IKBtnL = 1u << 2, IKBtnR = 1u << 3,
    IKBtnA = 1u << 4, IKBtnB = 1u << 5, IKBtnC = 1u << 6,
    IKBtnX = 1u << 7, IKBtnY = 1u << 8, IKBtnZ = 1u << 9,
    IKBtnS = 1u << 10, IKBtnDd = 1u << 11, IKBtnW = 1u << 12, IKBtnM = 1u << 13,
};
#define IK_DIR_MASK (IKBtnU | IKBtnD | IKBtnL | IKBtnR)
#define IK_BUTTON_COUNT 14
