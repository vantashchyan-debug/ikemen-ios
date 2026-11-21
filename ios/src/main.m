// iOS entry point: hand control to SDL, which calls the Go engine's SDL_main.
#define SDL_MAIN_HANDLED
#import <Foundation/Foundation.h>
#include "SDL.h"
#include "IKBridge.h"

const char *IKPreferredLanguage(void) {
    static char buf[32];
    NSString *lang = [NSLocale preferredLanguages].firstObject ?: @"en";
    strlcpy(buf, lang.UTF8String, sizeof(buf));
    return buf;
}

int main(int argc, char *argv[]) {
    SDL_SetMainReady();
    return SDL_UIKitRunApp(argc, argv, SDL_main);
}
