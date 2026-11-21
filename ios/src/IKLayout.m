#import "IKLayout.h"
#import "IKBridge.h"
#include "SDL_keycode.h"

#pragma mark - Helpers

UIColor *IKColorFromHex(NSString *hex, UIColor *fallback) {
    if (hex.length == 0) return fallback;
    NSString *s = [hex stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]];
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:s] scanHexInt:&v]) return fallback;
    if (s.length <= 6) {
        return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
    }
    return [UIColor colorWithRed:((v >> 24) & 0xFF) / 255.0 green:((v >> 16) & 0xFF) / 255.0
                            blue:((v >> 8) & 0xFF) / 255.0 alpha:(v & 0xFF) / 255.0];
}

NSString *IKHexFromColor(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return @"#FFFFFF";
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}

NSArray<NSString *> *IKButtonNames(void) {
    static NSArray *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[ @"U", @"D", @"L", @"R", @"a", @"b", @"c", @"x", @"y", @"z", @"s", @"d", @"w", @"m" ];
    });
    return names;
}

NSString *IKButtonMaskName(uint32_t mask) {
    NSMutableArray *parts = [NSMutableArray array];
    NSArray *names = IKButtonNames();
    for (int i = 0; i < IK_BUTTON_COUNT; i++) {
        if (mask & (1u << i)) [parts addObject:names[i]];
    }
    return parts.count ? [parts componentsJoinedByString:@"+"] : @"—";
}

static NSDictionary<NSNumber *, NSString *> *IKKeyTable(void) {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [@{
            @(SDLK_ESCAPE) : @"Esc", @(SDLK_RETURN) : @"Enter", @(SDLK_SPACE) : @"Space",
            @(SDLK_TAB) : @"Tab", @(SDLK_BACKSPACE) : @"Backspace", @(SDLK_PAUSE) : @"Pause",
            @(SDLK_SCROLLLOCK) : @"ScrollLock", @(SDLK_INSERT) : @"Insert", @(SDLK_DELETE) : @"Delete",
            @(SDLK_HOME) : @"Home", @(SDLK_END) : @"End", @(SDLK_PAGEUP) : @"PageUp", @(SDLK_PAGEDOWN) : @"PageDown",
            @(SDLK_UP) : @"↑", @(SDLK_DOWN) : @"↓", @(SDLK_LEFT) : @"←", @(SDLK_RIGHT) : @"→",
        } mutableCopy];
        SDL_Keycode fkeys[] = { SDLK_F1, SDLK_F2, SDLK_F3, SDLK_F4, SDLK_F5, SDLK_F6,
                                SDLK_F7, SDLK_F8, SDLK_F9, SDLK_F10, SDLK_F11, SDLK_F12 };
        for (int i = 0; i < 12; i++) m[@(fkeys[i])] = [NSString stringWithFormat:@"F%d", i + 1];
        for (char ch = 'a'; ch <= 'z'; ch++) m[@((int)ch)] = [NSString stringWithFormat:@"%c", ch - 32];
        for (char ch = '0'; ch <= '9'; ch++) m[@((int)ch)] = [NSString stringWithFormat:@"%c", ch];
        t = m;
    });
    return t;
}

NSString *IKKeyName(NSInteger keycode) {
    return IKKeyTable()[@(keycode)] ?: [NSString stringWithFormat:@"#%ld", (long)keycode];
}

NSArray<NSNumber *> *IKSelectableKeys(void) {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *k = [@[ @(SDLK_ESCAPE), @(SDLK_RETURN), @(SDLK_SPACE), @(SDLK_TAB), @(SDLK_BACKSPACE),
                                @(SDLK_PAUSE), @(SDLK_SCROLLLOCK), @(SDLK_INSERT), @(SDLK_DELETE), @(SDLK_HOME),
                                @(SDLK_END), @(SDLK_PAGEUP), @(SDLK_PAGEDOWN),
                                @(SDLK_UP), @(SDLK_DOWN), @(SDLK_LEFT), @(SDLK_RIGHT) ] mutableCopy];
        SDL_Keycode fkeys[] = { SDLK_F1, SDLK_F2, SDLK_F3, SDLK_F4, SDLK_F5, SDLK_F6,
                                SDLK_F7, SDLK_F8, SDLK_F9, SDLK_F10, SDLK_F11, SDLK_F12 };
        for (int i = 0; i < 12; i++) [k addObject:@(fkeys[i])];
        for (char ch = 'a'; ch <= 'z'; ch++) [k addObject:@((int)ch)];
        for (char ch = '0'; ch <= '9'; ch++) [k addObject:@((int)ch)];
        keys = k;
    });
    return keys;
}

static CGFloat num(NSDictionary *d, NSString *k, CGFloat def) {
    id v = d[k];
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : def;
}
static BOOL flag(NSDictionary *d, NSString *k, BOOL def) {
    id v = d[k];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : def;
}
static NSString *str(NSDictionary *d, NSString *k, NSString *def) {
    id v = d[k];
    return [v isKindOfClass:[NSString class]] ? v : def;
}

#pragma mark - Macro parser

NSString *const IKMacroHelp =
    @"Шаги через пробел или запятую. Шаг = части через «+», затем «:кадры» (60 кадров = 1 с, по умолчанию 2).\n"
    @"Направления: нумпад 1–9 (6 = вперёд, 4 = назад, относительно стороны персонажа), "
    @"F B UF UB DF DB (относительные), U D L R UL UR DL DR (абсолютные).\n"
    @"Кнопки: a b c x y z s d w m. Пауза: _ или 5.\n"
    @"Слитные цифры разворачиваются: «236+a» = 2, 3, 6+a.\n"
    @"Примеры: «236+a» (хадокен), «623+x», «41236+c:4», «_:30 a a a».";

static BOOL IKApplyPart(NSString *p, int facing, uint32_t *mask) {
    uint32_t fwd = facing >= 0 ? IKBtnR : IKBtnL;
    uint32_t back = facing >= 0 ? IKBtnL : IKBtnR;
    static NSDictionary *absMap;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        absMap = @{ @"U" : @(IKBtnU), @"D" : @(IKBtnD), @"L" : @(IKBtnL), @"R" : @(IKBtnR),
                 @"UL" : @(IKBtnU | IKBtnL), @"UR" : @(IKBtnU | IKBtnR),
                 @"DL" : @(IKBtnD | IKBtnL), @"DR" : @(IKBtnD | IKBtnR),
                 @"a" : @(IKBtnA), @"b" : @(IKBtnB), @"c" : @(IKBtnC), @"x" : @(IKBtnX), @"y" : @(IKBtnY),
                 @"z" : @(IKBtnZ), @"s" : @(IKBtnS), @"d" : @(IKBtnDd), @"w" : @(IKBtnW), @"m" : @(IKBtnM),
                 @"_" : @0, @"5" : @0 };
    });
    NSNumber *a = absMap[p];
    if (a) { *mask |= a.unsignedIntValue; return YES; }
    NSDictionary *rel = @{ @"F" : @(fwd), @"B" : @(back), @"UF" : @(IKBtnU | fwd), @"UB" : @(IKBtnU | back),
                           @"DF" : @(IKBtnD | fwd), @"DB" : @(IKBtnD | back),
                           @"1" : @(IKBtnD | back), @"2" : @(IKBtnD), @"3" : @(IKBtnD | fwd),
                           @"4" : @(back), @"6" : @(fwd),
                           @"7" : @(IKBtnU | back), @"8" : @(IKBtnU), @"9" : @(IKBtnU | fwd) };
    NSNumber *r = rel[p];
    if (r) { *mask |= r.unsignedIntValue; return YES; }
    return NO;
}

NSArray<NSValue *> *IKParseMacro(NSString *script, int facing, NSString **error) {
    NSMutableArray *steps = [NSMutableArray array];
    NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:@" ,;\n\t"];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for (NSString *rawTok in [script componentsSeparatedByCharactersInSet:sep]) {
        if (rawTok.length == 0) continue;
        NSString *tok = rawTok;
        int frames = 2;
        NSRange colon = [tok rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            frames = [[tok substringFromIndex:colon.location + 1] intValue];
            tok = [tok substringToIndex:colon.location];
            if (frames < 1 || frames > 600) {
                if (error) *error = [NSString stringWithFormat:@"Неверное число кадров в «%@» (1–600)", rawTok];
                return nil;
            }
        }
        NSMutableArray<NSString *> *parts = [[tok componentsSeparatedByString:@"+"] mutableCopy];
        // Expand leading multi-digit numpad run: "236+a" -> 2, 3, then 6+a
        NSString *first = parts.firstObject;
        if (first.length > 1 && [[first stringByTrimmingCharactersInSet:digits] length] == 0) {
            for (NSUInteger i = 0; i + 1 < first.length; i++) {
                uint32_t m = 0;
                IKApplyPart([first substringWithRange:NSMakeRange(i, 1)], facing, &m);
                IKMacroStep st = { m, 2 };
                [steps addObject:[NSValue valueWithBytes:&st objCType:@encode(IKMacroStep)]];
            }
            parts[0] = [first substringFromIndex:first.length - 1];
        }
        uint32_t mask = 0;
        for (NSString *p in parts) {
            if (p.length == 0) continue;
            if (!IKApplyPart(p, facing, &mask)) {
                if (error) *error = [NSString stringWithFormat:@"Неизвестный элемент «%@» в «%@»", p, rawTok];
                return nil;
            }
        }
        IKMacroStep st = { mask, frames };
        [steps addObject:[NSValue valueWithBytes:&st objCType:@encode(IKMacroStep)]];
    }
    if (steps.count == 0) {
        if (error) *error = @"Макрос пуст";
        return nil;
    }
    if (steps.count > 256) {
        if (error) *error = @"Слишком длинный макрос (макс. 256 шагов)";
        return nil;
    }
    return steps;
}

#pragma mark - IKControl

@implementation IKControl

+ (instancetype)controlWithType:(IKControlType)type {
    IKControl *c = [IKControl new];
    c.identifier = [NSUUID UUID].UUIDString;
    c.type = type;
    c.label = @"";
    c.cx = 0.5; c.cy = 0.5;
    c.size = type == IKControlTypeDPad ? 150 : 64;
    c.aspect = 1;
    c.shape = IKShapeCircle;
    c.opacity = -1;
    c.visible = YES;
    c.showMode = IKShowAlways;
    c.hitScale = 1.15;
    c.turboHz = 15;
    c.keycodes = @[];
    c.macro = @"";
    c.dpadMode = IKDPadMode8Way;
    c.deadzone = 0.18;
    c.diagonalWidth = 45;
    c.floatingZone = 0.45;
    c.snapBack = YES;
    return c;
}

- (id)copyWithZone:(NSZone *)zone {
    return [IKControl controlFromDictionary:[self dictionary]];
}

- (NSDictionary *)dictionary {
    NSMutableDictionary *d = [@{
        @"id" : self.identifier, @"type" : @(self.type), @"label" : self.label ?: @"",
        @"cx" : @(self.cx), @"cy" : @(self.cy), @"size" : @(self.size), @"aspect" : @(self.aspect),
        @"shape" : @(self.shape), @"opacity" : @(self.opacity), @"visible" : @(self.visible),
        @"showMode" : @(self.showMode), @"hitScale" : @(self.hitScale),
        @"buttons" : @(self.buttons), @"turbo" : @(self.turbo), @"turboHz" : @(self.turboHz),
        @"toggle" : @(self.toggle), @"keys" : self.keycodes ?: @[], @"macro" : self.macro ?: @"",
        @"macroLoop" : @(self.macroLoop), @"dpadMode" : @(self.dpadMode), @"deadzone" : @(self.deadzone),
        @"diagonal" : @(self.diagonalWidth), @"floatZone" : @(self.floatingZone), @"snapBack" : @(self.snapBack),
    } mutableCopy];
    if (self.colorHex) d[@"color"] = self.colorHex;
    return d;
}

+ (instancetype)controlFromDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    IKControl *c = [IKControl controlWithType:(IKControlType)num(d, @"type", IKControlTypeButton)];
    if (c.type < IKControlTypeDPad || c.type > IKControlTypeMenu) return nil;
    c.identifier = str(d, @"id", c.identifier);
    c.label = str(d, @"label", @"");
    c.cx = MIN(MAX(num(d, @"cx", 0.5), 0), 1);
    c.cy = MIN(MAX(num(d, @"cy", 0.5), 0), 1);
    c.size = MIN(MAX(num(d, @"size", c.size), 16), 400);
    c.aspect = MIN(MAX(num(d, @"aspect", 1), 0.25), 4);
    c.shape = (IKShape)num(d, @"shape", IKShapeCircle);
    c.opacity = num(d, @"opacity", -1);
    c.colorHex = [d[@"color"] isKindOfClass:[NSString class]] ? d[@"color"] : nil;
    c.visible = flag(d, @"visible", YES);
    c.showMode = (IKShowMode)num(d, @"showMode", IKShowAlways);
    c.hitScale = MIN(MAX(num(d, @"hitScale", 1.15), 0.5), 2.5);
    c.buttons = (uint32_t)num(d, @"buttons", 0) & ((1u << IK_BUTTON_COUNT) - 1);
    c.turbo = flag(d, @"turbo", NO);
    c.turboHz = MIN(MAX(num(d, @"turboHz", 15), 2), 30);
    c.toggle = flag(d, @"toggle", NO);
    NSMutableArray *keys = [NSMutableArray array];
    for (id k in ([d[@"keys"] isKindOfClass:[NSArray class]] ? d[@"keys"] : @[])) {
        if ([k isKindOfClass:[NSNumber class]]) [keys addObject:k];
    }
    c.keycodes = keys;
    c.macro = str(d, @"macro", @"");
    c.macroLoop = flag(d, @"macroLoop", NO);
    c.dpadMode = (IKDPadMode)num(d, @"dpadMode", IKDPadMode8Way);
    c.deadzone = MIN(MAX(num(d, @"deadzone", 0.18), 0), 0.9);
    c.diagonalWidth = MIN(MAX(num(d, @"diagonal", 45), 10), 80);
    c.floatingZone = MIN(MAX(num(d, @"floatZone", 0.45), 0.15), 0.9);
    c.snapBack = flag(d, @"snapBack", YES);
    return c;
}

- (NSString *)summary {
    switch (self.type) {
        case IKControlTypeDPad: {
            NSArray *modes = @[ @"Крестовина 8", @"Крестовина 4", @"Стик", @"Плавающий стик" ];
            return modes[MIN(MAX(self.dpadMode, 0), 3)];
        }
        case IKControlTypeButton: return [NSString stringWithFormat:@"Кнопки: %@", IKButtonMaskName(self.buttons)];
        case IKControlTypeKey: {
            NSMutableArray *n = [NSMutableArray array];
            for (NSNumber *k in self.keycodes) [n addObject:IKKeyName(k.integerValue)];
            return [NSString stringWithFormat:@"Клавиши: %@", n.count ? [n componentsJoinedByString:@"+"] : @"—"];
        }
        case IKControlTypeMacro: return [NSString stringWithFormat:@"Макрос: %@", self.macro.length ? self.macro : @"—"];
        case IKControlTypeMenu: return @"Меню настроек";
    }
    return @"";
}
@end

#pragma mark - IKGlobalSettings

@implementation IKGlobalSettings

+ (instancetype)settingsFromDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) d = @{};
    IKGlobalSettings *s = [IKGlobalSettings new];
    s.opacity = MIN(MAX(num(d, @"opacity", 0.55), 0.05), 1);
    s.pressedOpacity = MIN(MAX(num(d, @"pressedOpacity", 0.9), 0.05), 1);
    s.scale = MIN(MAX(num(d, @"scale", 1), 0.4), 2.5);
    s.style = (IKStyle)num(d, @"style", IKStyleOutline);
    s.showLabels = flag(d, @"labels", YES);
    s.accentHex = str(d, @"accent", @"#FFFFFF");
    s.idleFadeSeconds = MIN(MAX(num(d, @"idleFade", 0), 0), 60);
    s.idleOpacity = MIN(MAX(num(d, @"idleOpacity", 0.15), 0), 1);
    s.player = MIN(MAX((NSInteger)num(d, @"player", 0), 0), 3);
    s.slideAcross = flag(d, @"slide", YES);
    s.multiHit = flag(d, @"multiHit", YES);
    s.haptic = MIN(MAX((NSInteger)num(d, @"haptic", 1), 0), 5);
    s.hapticIntensity = MIN(MAX(num(d, @"hapticIntensity", 0.8), 0.1), 1);
    s.hapticOnRelease = flag(d, @"hapticRelease", NO);
    s.hapticOnDirection = flag(d, @"hapticDirection", NO);
    s.hideWithGamepad = flag(d, @"hideWithGamepad", YES);
    s.snapToGrid = flag(d, @"snap", NO);
    s.gridSize = MIN(MAX(num(d, @"grid", 8), 2), 64);
    s.pressAnimation = flag(d, @"pressAnim", YES);
    return s;
}

- (id)copyWithZone:(NSZone *)zone {
    return [IKGlobalSettings settingsFromDictionary:[self dictionary]];
}

- (NSDictionary *)dictionary {
    return @{
        @"opacity" : @(self.opacity), @"pressedOpacity" : @(self.pressedOpacity), @"scale" : @(self.scale),
        @"style" : @(self.style), @"labels" : @(self.showLabels), @"accent" : self.accentHex ?: @"#FFFFFF",
        @"idleFade" : @(self.idleFadeSeconds), @"idleOpacity" : @(self.idleOpacity), @"player" : @(self.player),
        @"slide" : @(self.slideAcross), @"multiHit" : @(self.multiHit), @"haptic" : @(self.haptic),
        @"hapticIntensity" : @(self.hapticIntensity), @"hapticRelease" : @(self.hapticOnRelease),
        @"hapticDirection" : @(self.hapticOnDirection), @"hideWithGamepad" : @(self.hideWithGamepad),
        @"snap" : @(self.snapToGrid), @"grid" : @(self.gridSize), @"pressAnim" : @(self.pressAnimation),
    };
}
@end

#pragma mark - IKProfile

@implementation IKProfile

- (id)copyWithZone:(NSZone *)zone {
    IKProfile *p = [IKProfile profileFromDictionary:[self dictionary]];
    for (IKControl *c in p.controls) c.identifier = [NSUUID UUID].UUIDString;
    return p;
}

- (NSDictionary *)dictionary {
    NSMutableArray *cs = [NSMutableArray array];
    for (IKControl *c in self.controls) [cs addObject:[c dictionary]];
    return @{ @"name" : self.name ?: @"Профиль", @"settings" : [self.settings dictionary], @"controls" : cs };
}

+ (instancetype)profileFromDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    IKProfile *p = [IKProfile new];
    p.name = str(d, @"name", @"Профиль");
    p.settings = [IKGlobalSettings settingsFromDictionary:d[@"settings"]];
    p.controls = [NSMutableArray array];
    for (id cd in ([d[@"controls"] isKindOfClass:[NSArray class]] ? d[@"controls"] : @[])) {
        IKControl *c = [IKControl controlFromDictionary:cd];
        if (c) [p.controls addObject:c];
    }
    // There must always be a way back into the settings.
    BOOL hasMenu = NO;
    for (IKControl *c in p.controls) hasMenu |= c.type == IKControlTypeMenu;
    if (!hasMenu) {
        IKControl *m = [IKControl controlWithType:IKControlTypeMenu];
        m.label = @"⚙︎"; m.cx = 0.5; m.cy = 0.07; m.size = 34; m.shape = IKShapeRounded;
        [p.controls addObject:m];
    }
    return p;
}

- (void)mirrorHorizontally {
    for (IKControl *c in self.controls) {
        c.cx = 1.0 - c.cx;
        if (c.type == IKControlTypeButton) {
            // keep directional semantics (L<->R) of buttons that send directions
            uint32_t b = c.buttons, l = b & IKBtnL, r = b & IKBtnR;
            b &= ~(IKBtnL | IKBtnR);
            if (l) b |= IKBtnR;
            if (r) b |= IKBtnL;
            c.buttons = b;
        }
    }
}
@end

#pragma mark - Store

@implementation IKLayoutStore

+ (instancetype)shared {
    static IKLayoutStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IKLayoutStore new]; [s load]; });
    return s;
}

- (IKProfile *)active {
    if (self.profiles.count == 0) [self.profiles addObject:[IKLayoutStore presetNamed:IKLayoutStore.presetNames[0]]];
    self.activeIndex = MIN(MAX(self.activeIndex, 0), (NSInteger)self.profiles.count - 1);
    return self.profiles[self.activeIndex];
}

+ (NSString *)path {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [docs stringByAppendingPathComponent:@"Ikemen/save"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"touch_layout.json"];
}

- (void)load {
    self.profiles = [NSMutableArray array];
    NSData *data = [NSData dataWithContentsOfFile:[IKLayoutStore path]];
    if (!data) {
        // First launch: optional default shipped inside the bundle (game/save/touch_layout.json)
        NSString *bundled = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"game/save/touch_layout.json"];
        data = [NSData dataWithContentsOfFile:bundled];
    }
    if (data) {
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([root isKindOfClass:[NSDictionary class]]) {
            for (id pd in ([root[@"profiles"] isKindOfClass:[NSArray class]] ? root[@"profiles"] : @[])) {
                IKProfile *p = [IKProfile profileFromDictionary:pd];
                if (p) [self.profiles addObject:p];
            }
            self.activeIndex = (NSInteger)num(root, @"active", 0);
        }
    }
    if (self.profiles.count == 0) {
        for (NSString *n in @[ IKLayoutStore.presetNames[0], IKLayoutStore.presetNames[2] ]) {
            [self.profiles addObject:[IKLayoutStore presetNamed:n]];
        }
        self.activeIndex = 0;
    }
    (void)self.active;
}

- (NSDictionary *)rootDictionary:(BOOL)all {
    NSMutableArray *ps = [NSMutableArray array];
    if (all) {
        for (IKProfile *p in self.profiles) [ps addObject:[p dictionary]];
    } else {
        [ps addObject:[self.active dictionary]];
    }
    return @{ @"format" : @"ikemen-touch", @"version" : @1, @"active" : @(all ? self.activeIndex : 0), @"profiles" : ps };
}

- (void)save {
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self rootDictionary:YES]
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    [data writeToFile:[IKLayoutStore path] atomically:YES];
}

- (NSString *)exportJSON:(BOOL)allProfiles {
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self rootDictionary:allProfiles]
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (BOOL)importJSON:(NSString *)json error:(NSString **)err {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSArray *list = nil;
    if ([root isKindOfClass:[NSDictionary class]] && [root[@"profiles"] isKindOfClass:[NSArray class]]) {
        list = root[@"profiles"];
    } else if ([root isKindOfClass:[NSDictionary class]] && root[@"controls"]) {
        list = @[ root ];
    }
    if (!list.count) {
        if (err) *err = @"Это не раскладка Ikemen (ожидается JSON с \"profiles\").";
        return NO;
    }
    NSInteger added = 0;
    for (id pd in list) {
        IKProfile *p = [IKProfile profileFromDictionary:pd];
        if (!p) continue;
        p.name = [p.name stringByAppendingString:@" (импорт)"];
        [self.profiles addObject:p];
        added++;
    }
    if (!added) {
        if (err) *err = @"Не найдено ни одного корректного профиля.";
        return NO;
    }
    self.activeIndex = self.profiles.count - 1;
    [self save];
    return YES;
}

#pragma mark Presets

+ (NSArray<NSString *> *)presetNames {
    return @[ @"Классика (6 кнопок)", @"4 кнопки", @"Плавающий стик", @"Крупные кнопки", @"Для левши", @"Минимум (только меню)" ];
}

static IKControl *IKBtn(NSString *label, uint32_t mask, CGFloat cx, CGFloat cy, CGFloat size) {
    IKControl *c = [IKControl controlWithType:IKControlTypeButton];
    c.label = label; c.buttons = mask; c.cx = cx; c.cy = cy; c.size = size;
    return c;
}

static IKControl *IKKey(NSString *label, NSInteger key, CGFloat cx, CGFloat cy) {
    IKControl *c = [IKControl controlWithType:IKControlTypeKey];
    c.label = label; c.keycodes = @[ @(key) ]; c.cx = cx; c.cy = cy; c.size = 54; c.aspect = 0.55;
    c.shape = IKShapeRounded;
    return c;
}

+ (IKProfile *)presetNamed:(NSString *)name {
    IKProfile *p = [IKProfile new];
    p.name = name;
    p.settings = [IKGlobalSettings settingsFromDictionary:nil];
    p.controls = [NSMutableArray array];
    NSArray *names = [self presetNames];
    NSUInteger idx = [names indexOfObject:name];
    if (idx == NSNotFound) idx = 0;

    IKControl *menu = [IKControl controlWithType:IKControlTypeMenu];
    menu.label = @"⚙︎"; menu.cx = 0.5; menu.cy = 0.07; menu.size = 34; menu.shape = IKShapeRounded;

    if (idx == 5) {
        [p.controls addObject:menu];
        return p;
    }

    IKControl *pad = [IKControl controlWithType:IKControlTypeDPad];
    pad.cx = 0.135; pad.cy = 0.68; pad.size = 150;
    if (idx == 2) {
        pad.dpadMode = IKDPadModeFloatingStick;
        pad.size = 140;
    }
    [p.controls addObject:pad];

    CGFloat s = idx == 3 ? 78 : 62;
    if (idx == 1) {
        [p.controls addObjectsFromArray:@[
            IKBtn(@"A", IKBtnA, 0.78, 0.82, 70), IKBtn(@"B", IKBtnB, 0.89, 0.66, 70),
            IKBtn(@"X", IKBtnX, 0.67, 0.66, 70), IKBtn(@"Y", IKBtnY, 0.78, 0.50, 70),
        ]];
    } else {
        CGFloat dx = idx == 3 ? 0.105 : 0.088, dy = idx == 3 ? 0.235 : 0.2;
        CGFloat x0 = idx == 3 ? 0.66 : 0.70, y1 = 0.83, y0 = y1 - dy;
        [p.controls addObjectsFromArray:@[
            IKBtn(@"X", IKBtnX, x0, y0 + 0.03, s), IKBtn(@"Y", IKBtnY, x0 + dx, y0, s), IKBtn(@"Z", IKBtnZ, x0 + 2 * dx, y0 - 0.015, s),
            IKBtn(@"A", IKBtnA, x0, y1 + 0.03, s), IKBtn(@"B", IKBtnB, x0 + dx, y1, s), IKBtn(@"C", IKBtnC, x0 + 2 * dx, y1 - 0.015, s),
        ]];
    }
    IKControl *d = IKBtn(@"D", IKBtnDd, 0.93, 0.36, 48); d.visible = NO;
    IKControl *w = IKBtn(@"W", IKBtnW, 0.86, 0.36, 48); w.visible = NO;
    [p.controls addObjectsFromArray:@[ d, w ]];

    IKControl *start = IKBtn(@"START", IKBtnS, 0.575, 0.93, 60);
    start.aspect = 0.5; start.shape = IKShapeRounded;
    [p.controls addObject:start];
    [p.controls addObject:IKKey(@"ESC", SDLK_ESCAPE, 0.425, 0.93)];

    IKControl *hado = [IKControl controlWithType:IKControlTypeMacro];
    hado.label = @"236A"; hado.macro = @"236+a"; hado.cx = 0.62; hado.cy = 0.42; hado.size = 50; hado.visible = NO;
    hado.showMode = IKShowInFight;
    [p.controls addObject:hado];

    [p.controls addObject:menu];
    if (idx == 4) [p mirrorHorizontally];
    return p;
}
@end
