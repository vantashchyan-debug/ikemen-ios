// Touch layout data model: profiles, global settings and individual controls.
// Persisted as JSON in Documents/Ikemen/save/touch_layout.json.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IKControlType) {
    IKControlTypeDPad = 0,   // directional pad / stick (modes below)
    IKControlTypeButton,     // presses one or more game buttons together
    IKControlTypeKey,        // presses raw keyboard keys (Esc, F1, Pause...)
    IKControlTypeMacro,      // plays a timed input sequence
    IKControlTypeMenu,       // opens touch-controls settings
};

typedef NS_ENUM(NSInteger, IKDPadMode) {
    IKDPadMode8Way = 0,
    IKDPadMode4Way,
    IKDPadModeStick,         // fixed analog-style stick, digital output
    IKDPadModeFloatingStick, // stick appears where the thumb lands
};

typedef NS_ENUM(NSInteger, IKShape) {
    IKShapeCircle = 0,
    IKShapeRounded,
    IKShapeSquare,
};

typedef NS_ENUM(NSInteger, IKShowMode) {
    IKShowAlways = 0,
    IKShowInFight,
    IKShowInMenus,
};

typedef NS_ENUM(NSInteger, IKStyle) {
    IKStyleOutline = 0,
    IKStyleFilled,
    IKStyleMinimal,
};

@interface IKControl : NSObject <NSCopying>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) IKControlType type;
@property (nonatomic, copy) NSString *label;
@property (nonatomic) CGFloat cx, cy;            // centre, normalised 0..1
@property (nonatomic) CGFloat size;              // width in points (before global scale)
@property (nonatomic) CGFloat aspect;            // height = size * aspect
@property (nonatomic) IKShape shape;
@property (nonatomic) CGFloat opacity;           // <0 = use global
@property (nonatomic, copy, nullable) NSString *colorHex; // nil = theme colour
@property (nonatomic) BOOL visible;
@property (nonatomic) IKShowMode showMode;
@property (nonatomic) CGFloat hitScale;          // touch area multiplier
// Button
@property (nonatomic) uint32_t buttons;          // IKBtn* mask
@property (nonatomic) BOOL turbo;
@property (nonatomic) CGFloat turboHz;
@property (nonatomic) BOOL toggle;               // latch on/off with each tap
// Key
@property (nonatomic, copy) NSArray<NSNumber *> *keycodes; // SDL keycodes
// Macro
@property (nonatomic, copy) NSString *macro;
@property (nonatomic) BOOL macroLoop;            // repeat while held
// D-pad
@property (nonatomic) IKDPadMode dpadMode;
@property (nonatomic) CGFloat deadzone;          // 0..0.9 of radius
@property (nonatomic) CGFloat diagonalWidth;     // degrees of the diagonal sectors (10..80)
@property (nonatomic) CGFloat floatingZone;      // floating stick: fraction of screen width from the control's side
@property (nonatomic) BOOL snapBack;             // floating stick returns to home position on release

+ (instancetype)controlWithType:(IKControlType)type;
- (NSDictionary *)dictionary;
+ (nullable instancetype)controlFromDictionary:(NSDictionary *)d;
- (NSString *)summary;
@end

@interface IKGlobalSettings : NSObject <NSCopying>
@property (nonatomic) CGFloat opacity;
@property (nonatomic) CGFloat pressedOpacity;
@property (nonatomic) CGFloat scale;
@property (nonatomic) IKStyle style;
@property (nonatomic) BOOL showLabels;
@property (nonatomic, copy) NSString *accentHex;
@property (nonatomic) CGFloat idleFadeSeconds;   // 0 = off
@property (nonatomic) CGFloat idleOpacity;
@property (nonatomic) NSInteger player;          // 0-based
@property (nonatomic) BOOL slideAcross;          // finger can slide between buttons
@property (nonatomic) BOOL multiHit;             // overlapping hit areas press both
@property (nonatomic) NSInteger haptic;          // 0 off, 1 light, 2 medium, 3 heavy, 4 rigid, 5 soft
@property (nonatomic) CGFloat hapticIntensity;   // 0.1..1
@property (nonatomic) BOOL hapticOnRelease;
@property (nonatomic) BOOL hapticOnDirection;
@property (nonatomic) BOOL hideWithGamepad;
@property (nonatomic) BOOL snapToGrid;
@property (nonatomic) CGFloat gridSize;          // points
@property (nonatomic) BOOL pressAnimation;
- (NSDictionary *)dictionary;
+ (instancetype)settingsFromDictionary:(nullable NSDictionary *)d;
@end

@interface IKProfile : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) IKGlobalSettings *settings;
@property (nonatomic, strong) NSMutableArray<IKControl *> *controls;
- (NSDictionary *)dictionary;
+ (nullable instancetype)profileFromDictionary:(NSDictionary *)d;
- (void)mirrorHorizontally;
@end

@interface IKLayoutStore : NSObject
@property (nonatomic, strong) NSMutableArray<IKProfile *> *profiles;
@property (nonatomic) NSInteger activeIndex;
@property (nonatomic, readonly) IKProfile *active;

+ (instancetype)shared;
- (void)load;
- (void)save;
- (NSString *)exportJSON:(BOOL)allProfiles;
- (BOOL)importJSON:(NSString *)json error:(NSString *_Nullable *_Nullable)err;

+ (NSArray<NSString *> *)presetNames;
+ (IKProfile *)presetNamed:(NSString *)name;
@end

// Helpers
UIColor *IKColorFromHex(NSString *_Nullable hex, UIColor *fallback);
NSString *IKHexFromColor(UIColor *c);
NSString *IKButtonMaskName(uint32_t mask);
NSArray<NSString *> *IKButtonNames(void);      // index -> "U","D",...,"m"
NSString *IKKeyName(NSInteger keycode);
NSArray<NSNumber *> *IKSelectableKeys(void);

// Macro script: "2 3 6+a:4  _:10  F+x" (see IKMacroHelp)
typedef struct { uint32_t mask; int frames; } IKMacroStep;
NSArray<NSValue *> *_Nullable IKParseMacro(NSString *script, int facing, NSString *_Nullable *_Nullable error);
extern NSString *const IKMacroHelp;

NS_ASSUME_NONNULL_END
