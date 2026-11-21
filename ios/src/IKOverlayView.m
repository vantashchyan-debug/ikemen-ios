// Native on-screen controls drawn above the SDL/Metal view.
//
// Input reaches the engine through IkemenTouchSetState (game buttons bitmask
// OR-ed into the selected player's input) and IkemenTouchKey (raw keys).
// All callbacks run on the main thread while the engine pumps SDL events, so
// they are synchronous with the game loop.

#import "IKOverlayView.h"
#import "IKSettingsViewController.h"
#import "IKBridge.h"
#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Root view controller lookup

UIViewController *IKRootViewController(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.rootViewController) return w.rootViewController;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in app.windows) {
        if (w.rootViewController) return w.rootViewController;
    }
#pragma clang diagnostic pop
    return nil;
}

static UIViewController *IKTopViewController(void) {
    UIViewController *vc = IKRootViewController();
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

#pragma mark - Control view

@interface IKControlView : UIView
@property (nonatomic, strong) IKControl *control;
@property (nonatomic, weak) IKGlobalSettings *settings;
@property (nonatomic) BOOL pressed;
@property (nonatomic) uint32_t dirMask;     // d-pad highlight
@property (nonatomic) CGPoint knob;         // stick knob offset (points)
@property (nonatomic) BOOL editMode;
@property (nonatomic) BOOL selected;
@end

@implementation IKControlView

- (instancetype)initWithControl:(IKControl *)c settings:(IKGlobalSettings *)s {
    if ((self = [super initWithFrame:CGRectZero])) {
        _control = c;
        _settings = s;
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    [self setNeedsDisplay];
    if (self.settings.pressAnimation && self.control.type != IKControlTypeDPad) {
        self.transform = pressed ? CGAffineTransformMakeScale(0.92, 0.92) : CGAffineTransformIdentity;
    }
}
- (void)setDirMask:(uint32_t)m { if (_dirMask != m) { _dirMask = m; [self setNeedsDisplay]; } }
- (void)setKnob:(CGPoint)k { if (!CGPointEqualToPoint(_knob, k)) { _knob = k; [self setNeedsDisplay]; } }
- (void)setEditMode:(BOOL)e { _editMode = e; [self setNeedsDisplay]; }
- (void)setSelected:(BOOL)s { _selected = s; [self setNeedsDisplay]; }

- (UIColor *)tint {
    UIColor *accent = IKColorFromHex(self.settings.accentHex, UIColor.whiteColor);
    return IKColorFromHex(self.control.colorHex, accent);
}

- (UIBezierPath *)shapePath:(CGRect)r {
    switch (self.control.shape) {
        case IKShapeCircle: return [UIBezierPath bezierPathWithOvalInRect:r];
        case IKShapeRounded: return [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:MIN(r.size.width, r.size.height) * 0.3];
        case IKShapeSquare: return [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:4];
    }
    return [UIBezierPath bezierPathWithOvalInRect:r];
}

- (void)fillStroke:(UIBezierPath *)p active:(BOOL)active {
    UIColor *c = self.tint;
    IKStyle st = self.settings.style;
    CGFloat fillA = st == IKStyleFilled ? (active ? 0.75 : 0.35) : st == IKStyleOutline ? (active ? 0.5 : 0.12) : (active ? 0.35 : 0);
    [[c colorWithAlphaComponent:fillA] setFill];
    [p fill];
    if (st != IKStyleFilled || active) {
        [[c colorWithAlphaComponent:st == IKStyleMinimal ? 0.6 : 0.95] setStroke];
        p.lineWidth = st == IKStyleMinimal ? 1 : 2;
        [p stroke];
    }
}

- (void)drawLabel:(NSString *)text inRect:(CGRect)r size:(CGFloat)fs {
    if (text.length == 0) return;
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    UIFont *font = [UIFont systemFontOfSize:fs weight:UIFontWeightBold];
    NSDictionary *attrs = @{ NSFontAttributeName : font, NSParagraphStyleAttributeName : ps,
                             NSForegroundColorAttributeName : [self.tint colorWithAlphaComponent:0.95] };
    CGSize sz = [text boundingRectWithSize:r.size options:NSStringDrawingUsesLineFragmentOrigin attributes:attrs context:nil].size;
    CGRect tr = CGRectMake(r.origin.x, CGRectGetMidY(r) - sz.height / 2, r.size.width, sz.height);
    [text drawInRect:tr withAttributes:attrs];
}

- (void)drawRect:(CGRect)rect {
    CGRect r = CGRectInset(self.bounds, 2, 2);
    IKControl *c = self.control;
    if (c.type == IKControlTypeDPad) {
        if (c.dpadMode == IKDPadMode8Way || c.dpadMode == IKDPadMode4Way) {
            [self drawDPad:r];
        } else {
            [self drawStick:r];
        }
    } else {
        UIBezierPath *p = [self shapePath:r];
        [self fillStroke:p active:self.pressed];
        if (self.settings.showLabels || c.type == IKControlTypeMenu) {
            CGFloat fs = MIN(r.size.width, r.size.height) * (c.label.length > 3 ? 0.26 : 0.4);
            [self drawLabel:c.label inRect:r size:MAX(fs, 9)];
        }
    }
    if (self.editMode) {
        UIBezierPath *b = [UIBezierPath bezierPathWithRect:CGRectInset(self.bounds, 0.5, 0.5)];
        CGFloat dash[] = { 4, 3 };
        [b setLineDash:dash count:2 phase:0];
        b.lineWidth = self.selected ? 2 : 1;
        [(self.selected ? UIColor.systemYellowColor : [UIColor colorWithWhite:1 alpha:0.6]) setStroke];
        [b stroke];
        if (!c.visible) {
            [self drawLabel:@"скрыто" inRect:CGRectMake(0, self.bounds.size.height - 14, self.bounds.size.width, 12) size:9];
        }
    }
}

- (void)drawDPad:(CGRect)r {
    CGFloat w = r.size.width, armW = w * 0.34, cx = CGRectGetMidX(r), cy = CGRectGetMidY(r);
    uint32_t m = self.dirMask;
    CGRect arms[4] = {
        CGRectMake(cx - armW / 2, r.origin.y, armW, w / 2 - armW / 2),          // U
        CGRectMake(cx - armW / 2, cy + armW / 2, armW, w / 2 - armW / 2),       // D
        CGRectMake(r.origin.x, cy - armW / 2, w / 2 - armW / 2, armW),          // L
        CGRectMake(cx + armW / 2, cy - armW / 2, w / 2 - armW / 2, armW),       // R
    };
    uint32_t bits[4] = { IKBtnU, IKBtnD, IKBtnL, IKBtnR };
    UIBezierPath *center = [UIBezierPath bezierPathWithRect:CGRectMake(cx - armW / 2, cy - armW / 2, armW, armW)];
    [self fillStroke:center active:NO];
    for (int i = 0; i < 4; i++) {
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:arms[i] cornerRadius:armW * 0.18];
        [self fillStroke:p active:(m & bits[i]) != 0];
    }
    if (self.settings.showLabels) {
        NSArray *glyphs = @[ @"▲", @"▼", @"◀", @"▶" ];
        for (int i = 0; i < 4; i++) [self drawLabel:glyphs[i] inRect:arms[i] size:armW * 0.35];
    }
}

- (void)drawStick:(CGRect)r {
    UIBezierPath *base = [UIBezierPath bezierPathWithOvalInRect:r];
    [self fillStroke:base active:NO];
    CGFloat kr = r.size.width * 0.22;
    CGPoint c = CGPointMake(CGRectGetMidX(r) + self.knob.x, CGRectGetMidY(r) + self.knob.y);
    UIBezierPath *knob = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - kr, c.y - kr, 2 * kr, 2 * kr)];
    [self fillStroke:knob active:self.dirMask != 0];
    // dead-zone ring
    CGFloat dz = r.size.width / 2 * self.control.deadzone;
    if (dz > 2) {
        UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(CGRectGetMidX(r) - dz, CGRectGetMidY(r) - dz, 2 * dz, 2 * dz)];
        [[self.tint colorWithAlphaComponent:0.25] setStroke];
        ring.lineWidth = 1;
        [ring stroke];
    }
}
@end

#pragma mark - Touch bookkeeping

@interface IKTouchInfo : NSObject
@property (nonatomic, copy, nullable) NSString *dpadId;           // touch drives this d-pad
@property (nonatomic, strong) NSMutableSet<NSString *> *pressed;  // button/key/macro/menu ids
@property (nonatomic) CGPoint start;
@property (nonatomic) CGPoint stickOrigin;                         // floating stick centre
@property (nonatomic) uint32_t dirMask;
@property (nonatomic) BOOL moved;
@end
@implementation IKTouchInfo
- (instancetype)init { if ((self = [super init])) _pressed = [NSMutableSet set]; return self; }
@end

@interface IKMacroRun : NSObject
@property (nonatomic, copy) NSArray<NSValue *> *steps;
@property (nonatomic) CFTimeInterval start;
@property (nonatomic) BOOL loop;
@property (nonatomic) BOOL held;
@end
@implementation IKMacroRun
@end

#pragma mark - Overlay

@interface IKOverlayView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSString *, IKControlView *> *views;
@property (nonatomic, strong) NSMapTable<UITouch *, IKTouchInfo *> *touches;
@property (nonatomic, strong) NSMutableSet<NSString *> *latched;
@property (nonatomic, strong) NSMutableDictionary<NSString *, IKMacroRun *> *macros;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *turboStart;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) uint32_t lastMask;
@property (nonatomic) NSInteger lastPlayer;
@property (nonatomic) CFTimeInterval lastTouchTime;
@property (nonatomic) BOOL gamepadConnected;
@property (nonatomic) BOOL settingsOpen;
@property (nonatomic) BOOL suspended;
@property (nonatomic, strong) UIImpactFeedbackGenerator *haptic;
@property (nonatomic) NSInteger hapticStyle;
// editing
@property (nonatomic, readwrite) BOOL editing;
@property (nonatomic, copy, nullable) NSString *selectedId;
@property (nonatomic) CGPoint dragOffset;
@property (nonatomic, weak, nullable) UITouch *dragTouch;
@property (nonatomic) BOOL dragMoved;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *undo;
@property (nonatomic, strong) UIView *toolbar;
@property (nonatomic, strong) UIView *inspector;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinch;
@property (nonatomic) CGFloat pinchBaseSize;
@property (nonatomic, strong) UIView *gridView;
@end

static IKOverlayView *gOverlay;

@implementation IKOverlayView

+ (instancetype)shared { return gOverlay; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _views = [NSMutableDictionary dictionary];
        _touches = [NSMapTable strongToStrongObjectsMapTable];
        _latched = [NSMutableSet set];
        _macros = [NSMutableDictionary dictionary];
        _turboStart = [NSMutableDictionary dictionary];
        _undo = [NSMutableArray array];
        _lastPlayer = -1;
        _hapticStyle = -1;
        _lastTouchTime = CACurrentMediaTime();

        _pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(onPinch:)];
        _pinch.enabled = NO;
        _pinch.delegate = self;
        [self addGestureRecognizer:_pinch];

        _gamepadConnected = GCController.controllers.count > 0;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(gamepadsChanged) name:GCControllerDidConnectNotification object:nil];
        [nc addObserver:self selector:@selector(gamepadsChanged) name:GCControllerDidDisconnectNotification object:nil];

        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        _link.preferredFramesPerSecond = 60;
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [self reloadLayout];
    }
    return self;
}

- (IKProfile *)profile { return IKLayoutStore.shared.active; }
- (IKGlobalSettings *)settings { return self.profile.settings; }

- (void)gamepadsChanged {
    self.gamepadConnected = GCController.controllers.count > 0;
    [self updateVisibility];
}

#pragma mark Layout

- (void)reloadLayout {
    [self releaseAll];
    for (IKControlView *v in self.views.allValues) [v removeFromSuperview];
    [self.views removeAllObjects];
    for (IKControl *c in self.profile.controls) {
        IKControlView *v = [[IKControlView alloc] initWithControl:c settings:self.settings];
        v.editMode = self.editing;
        v.selected = [c.identifier isEqualToString:self.selectedId];
        self.views[c.identifier] = v;
        [self insertSubview:v atIndex:self.gridView ? 1 : 0];
    }
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self updateVisibility];
    [self updateInspector];
}

- (CGRect)frameForControl:(IKControl *)c {
    CGFloat s = self.settings.scale;
    CGFloat w = c.size * s;
    CGFloat h = (c.type == IKControlTypeDPad) ? w : w * c.aspect;
    CGSize b = self.bounds.size;
    return CGRectMake(c.cx * b.width - w / 2, c.cy * b.height - h / 2, w, h);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    for (IKControl *c in self.profile.controls) {
        IKControlView *v = self.views[c.identifier];
        if (!v) continue;
        CGAffineTransform t = v.transform;
        v.transform = CGAffineTransformIdentity;
        v.frame = [self frameForControl:c];
        v.transform = t;
        [v setNeedsDisplay];
    }
    self.gridView.frame = self.bounds;
    [self layoutToolbar];
    [self updateInspector];
}

- (BOOL)controlShown:(IKControl *)c {
    if (self.editing) return YES;
    if (!c.visible) return NO;
    if (self.gamepadConnected && self.settings.hideWithGamepad && c.type != IKControlTypeMenu) return NO;
    if (c.showMode == IKShowAlways || c.type == IKControlTypeMenu) return YES;
    BOOL fight = IkemenGameIsRunning() != 0;
    return c.showMode == IKShowInFight ? fight : !fight;
}

- (CGFloat)baseAlphaFor:(IKControl *)c {
    if (self.editing) return c.visible ? 0.9 : 0.35;
    CGFloat a = c.opacity >= 0 ? c.opacity : self.settings.opacity;
    CGFloat idle = self.settings.idleFadeSeconds;
    if (idle > 0 && self.touches.count == 0 && CACurrentMediaTime() - self.lastTouchTime > idle) {
        a = MIN(a, self.settings.idleOpacity);
    }
    return a;
}

- (void)updateVisibility {
    for (IKControl *c in self.profile.controls) {
        IKControlView *v = self.views[c.identifier];
        BOOL shown = [self controlShown:c];
        v.hidden = !shown;
        CGFloat a = v.pressed ? MAX(self.settings.pressedOpacity, [self baseAlphaFor:c]) : [self baseAlphaFor:c];
        if (fabs(v.alpha - a) > 0.005) v.alpha = a;
    }
}

#pragma mark Hit testing

- (CGRect)hitRectFor:(IKControl *)c {
    CGRect f = [self frameForControl:c];
    CGFloat hs = c.hitScale;
    return CGRectInset(f, -f.size.width * (hs - 1) / 2, -f.size.height * (hs - 1) / 2);
}

- (BOOL)point:(CGPoint)p inControl:(IKControl *)c {
    CGRect r = [self hitRectFor:c];
    if (c.shape == IKShapeCircle || c.type == IKControlTypeDPad) {
        CGFloat dx = (p.x - CGRectGetMidX(r)) / (r.size.width / 2), dy = (p.y - CGRectGetMidY(r)) / (r.size.height / 2);
        return dx * dx + dy * dy <= 1.0;
    }
    return CGRectContainsPoint(r, p);
}

- (BOOL)inFloatingZone:(CGPoint)p control:(IKControl *)c {
    if (c.type != IKControlTypeDPad || c.dpadMode != IKDPadModeFloatingStick) return NO;
    CGFloat w = self.bounds.size.width;
    BOOL left = c.cx < 0.5;
    BOOL inX = left ? p.x < w * c.floatingZone : p.x > w * (1 - c.floatingZone);
    return inX && p.y > self.bounds.size.height * 0.12; // keep the top strip free for menus
}

- (NSArray<IKControl *> *)controlsAt:(CGPoint)p includeDPad:(BOOL)dpad {
    NSMutableArray *hits = [NSMutableArray array];
    IKControl *best = nil;
    CGFloat bestD = CGFLOAT_MAX;
    for (IKControl *c in self.profile.controls) {
        if (![self controlShown:c]) continue;
        if (c.type == IKControlTypeDPad) {
            if (dpad && ([self point:p inControl:c] || [self inFloatingZone:p control:c])) return @[ c ];
            continue;
        }
        if (![self point:p inControl:c]) continue;
        [hits addObject:c];
        CGRect f = [self frameForControl:c];
        CGFloat d = hypot(p.x - CGRectGetMidX(f), p.y - CGRectGetMidY(f));
        if (d < bestD) { bestD = d; best = c; }
    }
    if (hits.count > 1 && !self.settings.multiHit) return @[ best ];
    if (hits.count > 1) {
        // Only combine real game buttons; keys/menus/macros never chord.
        NSMutableArray *btns = [NSMutableArray array];
        for (IKControl *c in hits) if (c.type == IKControlTypeButton) [btns addObject:c];
        return btns.count > 1 ? btns : @[ best ];
    }
    return hits;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.suspended) return nil;
    if (self.editing) {
        UIView *v = [super hitTest:point withEvent:event];
        return v ?: self;
    }
    if (self.inspector || self.toolbar) {
        UIView *v = [super hitTest:point withEvent:event];
        if (v && v != self && ![v isKindOfClass:[IKControlView class]]) return v;
    }
    return [self controlsAt:point includeDPad:YES].count ? self : nil;
}

#pragma mark Touches (play mode)

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.lastTouchTime = CACurrentMediaTime();
    if (self.editing) { [self editTouchesBegan:touches]; return; }
    for (UITouch *t in touches) {
        CGPoint p = [t locationInView:self];
        IKTouchInfo *info = [IKTouchInfo new];
        info.start = p;
        NSArray<IKControl *> *hits = [self controlsAt:p includeDPad:YES];
        if (hits.count == 1 && hits[0].type == IKControlTypeDPad) {
            IKControl *c = hits[0];
            info.dpadId = c.identifier;
            CGRect f = [self frameForControl:c];
            info.stickOrigin = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
            if (c.dpadMode == IKDPadModeFloatingStick && ![self point:p inControl:c]) {
                info.stickOrigin = p;
                IKControlView *v = self.views[c.identifier];
                v.center = p;
            }
            [self.touches setObject:info forKey:t];
            [self updateDPadTouch:t info:info];
            continue;
        }
        [self.touches setObject:info forKey:t];
        for (IKControl *c in hits) [self pressControl:c touch:info];
    }
    [self pushState];
    [self updateVisibility];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.lastTouchTime = CACurrentMediaTime();
    if (self.editing) { [self editTouchesMoved:touches]; return; }
    for (UITouch *t in touches) {
        IKTouchInfo *info = [self.touches objectForKey:t];
        if (!info) continue;
        if (info.dpadId) { [self updateDPadTouch:t info:info]; continue; }
        if (!self.settings.slideAcross) continue;
        CGPoint p = [t locationInView:self];
        NSMutableSet *now = [NSMutableSet set];
        for (IKControl *c in [self controlsAt:p includeDPad:NO]) {
            if (c.type == IKControlTypeButton) [now addObject:c.identifier];
        }
        // only slide between plain buttons; keep keys/macros/menu bound to where they started
        NSMutableSet *slidable = [NSMutableSet set];
        for (NSString *cid in info.pressed) {
            IKControl *c = [self controlWithId:cid];
            if (c.type == IKControlTypeButton) [slidable addObject:cid];
        }
        if (now.count == 0 || [now isEqualToSet:slidable]) continue;
        for (NSString *cid in slidable) {
            if (![now containsObject:cid]) [self releaseControlId:cid touch:info cancelled:NO];
        }
        for (NSString *cid in now) {
            if (![info.pressed containsObject:cid]) [self pressControl:[self controlWithId:cid] touch:info];
        }
    }
    [self pushState];
    [self updateVisibility];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self finishTouches:touches cancelled:NO];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self finishTouches:touches cancelled:YES];
}

- (void)finishTouches:(NSSet<UITouch *> *)touches cancelled:(BOOL)cancelled {
    if (self.editing) { [self editTouchesEnded:touches]; return; }
    for (UITouch *t in touches) {
        IKTouchInfo *info = [self.touches objectForKey:t];
        if (!info) continue;
        if (info.dpadId) {
            IKControl *c = [self controlWithId:info.dpadId];
            IKControlView *v = self.views[info.dpadId];
            v.dirMask = 0;
            v.knob = CGPointZero;
            if (c.dpadMode == IKDPadModeFloatingStick && c.snapBack) {
                v.center = CGPointMake(c.cx * self.bounds.size.width, c.cy * self.bounds.size.height);
            }
            if (self.settings.hapticOnRelease) [self buzz:0.5];
        }
        for (NSString *cid in [info.pressed copy]) [self releaseControlId:cid touch:info cancelled:cancelled];
        [self.touches removeObjectForKey:t];
    }
    [self pushState];
    [self updateVisibility];
}

- (IKControl *)controlWithId:(NSString *)cid {
    for (IKControl *c in self.profile.controls) if ([c.identifier isEqualToString:cid]) return c;
    return nil;
}

- (BOOL)isHeldByOtherTouch:(NSString *)cid except:(IKTouchInfo *)info {
    for (UITouch *t in self.touches) {
        IKTouchInfo *o = [self.touches objectForKey:t];
        if (o != info && [o.pressed containsObject:cid]) return YES;
    }
    return NO;
}

- (void)pressControl:(IKControl *)c touch:(IKTouchInfo *)info {
    if (!c || [info.pressed containsObject:c.identifier]) return;
    BOOL already = [self isHeldByOtherTouch:c.identifier except:info];
    [info.pressed addObject:c.identifier];
    if (already) return;
    IKControlView *v = self.views[c.identifier];
    switch (c.type) {
        case IKControlTypeButton:
            if (c.toggle) {
                if ([self.latched containsObject:c.identifier]) [self.latched removeObject:c.identifier];
                else [self.latched addObject:c.identifier];
            }
            if (c.turbo) self.turboStart[c.identifier] = @(CACurrentMediaTime());
            break;
        case IKControlTypeKey:
            for (NSNumber *k in c.keycodes) IkemenTouchKey(k.intValue, 1);
            break;
        case IKControlTypeMacro: {
            int facing = IkemenPlayerFacing((int)self.settings.player);
            NSArray *steps = IKParseMacro(c.macro, facing, NULL);
            if (steps) {
                IKMacroRun *run = [IKMacroRun new];
                run.steps = steps;
                run.start = CACurrentMediaTime();
                run.loop = c.macroLoop;
                run.held = YES;
                self.macros[c.identifier] = run;
            }
            break;
        }
        case IKControlTypeMenu:
        case IKControlTypeDPad:
            break;
    }
    v.pressed = YES;
    [self buzz:1.0];
}

- (void)releaseControlId:(NSString *)cid touch:(IKTouchInfo *)info cancelled:(BOOL)cancelled {
    [info.pressed removeObject:cid];
    if ([self isHeldByOtherTouch:cid except:info]) return;
    IKControl *c = [self controlWithId:cid];
    IKControlView *v = self.views[cid];
    if (!c) return;
    switch (c.type) {
        case IKControlTypeKey:
            for (NSNumber *k in c.keycodes) IkemenTouchKey(k.intValue, 0);
            break;
        case IKControlTypeMacro:
            self.macros[cid].held = NO;
            break;
        case IKControlTypeMenu:
            if (!cancelled) {
                CGPoint p = info.start;
                if ([self point:p inControl:c]) dispatch_async(dispatch_get_main_queue(), ^{ [self openSettings]; });
            }
            break;
        default:
            break;
    }
    [self.turboStart removeObjectForKey:cid];
    v.pressed = c.toggle && [self.latched containsObject:cid];
    if (self.settings.hapticOnRelease) [self buzz:0.5];
}

- (void)updateDPadTouch:(UITouch *)t info:(IKTouchInfo *)info {
    IKControl *c = [self controlWithId:info.dpadId];
    IKControlView *v = self.views[info.dpadId];
    if (!c) return;
    CGPoint p = [t locationInView:self];
    CGFloat radius = c.size * self.settings.scale / 2;
    CGFloat dx = p.x - info.stickOrigin.x, dy = p.y - info.stickOrigin.y;
    CGFloat dist = hypot(dx, dy);
    uint32_t m = 0;
    if (dist > radius * c.deadzone) {
        CGFloat ang = atan2(-dy, dx) * 180.0 / M_PI;  // 0 = right, 90 = up
        if (c.dpadMode == IKDPadMode4Way) {
            if (fabs(dx) > fabs(dy)) m = dx > 0 ? IKBtnR : IKBtnL;
            else m = dy > 0 ? IKBtnD : IKBtnU;
        } else {
            // A direction is active if the angle is within its cardinal sector
            // widened by the diagonal sector width on each side.
            CGFloat card = (90.0 - c.diagonalWidth) / 2.0;   // half-width of pure cardinal
            CGFloat lim = card + c.diagonalWidth;             // half-width incl. diagonals
            CGFloat a = ang;
            if (fabs(a) < lim) m |= IKBtnR;
            if (fabs(fabs(a) - 180) < lim) m |= IKBtnL;
            if (fabs(a - 90) < lim) m |= IKBtnU;
            if (fabs(a + 90) < lim) m |= IKBtnD;
        }
    }
    if (m != info.dirMask) {
        if (self.settings.hapticOnDirection && m) [self buzz:0.6];
        info.dirMask = m;
    }
    v.dirMask = m;
    if (c.dpadMode == IKDPadModeStick || c.dpadMode == IKDPadModeFloatingStick) {
        CGFloat maxR = radius * 0.6;
        CGFloat k = dist > maxR ? maxR / dist : 1;
        v.knob = CGPointMake(dx * k, dy * k);
        // drag the floating base along when the thumb overshoots a lot
        if (c.dpadMode == IKDPadModeFloatingStick && dist > radius * 1.4) {
            CGFloat pull = (dist - radius * 1.4) / dist;
            info.stickOrigin = CGPointMake(info.stickOrigin.x + dx * pull, info.stickOrigin.y + dy * pull);
            v.center = info.stickOrigin;
        }
    }
}

#pragma mark State output

- (uint32_t)currentMask {
    uint32_t mask = 0;
    CFTimeInterval now = CACurrentMediaTime();
    for (UITouch *t in self.touches) {
        IKTouchInfo *info = [self.touches objectForKey:t];
        mask |= info.dirMask;
        for (NSString *cid in info.pressed) {
            IKControl *c = [self controlWithId:cid];
            if (c.type != IKControlTypeButton || c.toggle) continue;
            if (c.turbo) {
                CFTimeInterval st = [self.turboStart[cid] doubleValue];
                long phase = (long)floor((now - st) * c.turboHz * 2.0);
                if (phase % 2 == 0) mask |= c.buttons;
            } else {
                mask |= c.buttons;
            }
        }
    }
    for (NSString *cid in self.latched) mask |= [self controlWithId:cid].buttons;
    for (NSString *cid in [self.macros allKeys]) {
        IKMacroRun *run = self.macros[cid];
        long frame = (long)floor((now - run.start) * 60.0);
        long total = 0;
        for (NSValue *v in run.steps) { IKMacroStep st; [v getValue:&st]; total += st.frames; }
        if (total <= 0) { [self.macros removeObjectForKey:cid]; continue; }
        if (frame >= total) {
            if (run.loop && run.held) {
                frame %= total;
            } else {
                [self.macros removeObjectForKey:cid];
                continue;
            }
        }
        for (NSValue *v in run.steps) {
            IKMacroStep st; [v getValue:&st];
            if (frame < st.frames) { mask |= st.mask; break; }
            frame -= st.frames;
        }
    }
    return mask;
}

- (void)pushState {
    NSInteger player = self.settings.player;
    uint32_t mask = (self.editing || self.settingsOpen || self.suspended) ? 0 : [self currentMask];
    if (mask != self.lastMask || player != self.lastPlayer) {
        IkemenTouchSetState((int)player, mask);
        self.lastMask = mask;
        self.lastPlayer = player;
    }
}

- (void)releaseAll {
    for (UITouch *t in self.touches) {
        IKTouchInfo *info = [self.touches objectForKey:t];
        for (NSString *cid in info.pressed) {
            IKControl *c = [self controlWithId:cid];
            if (c.type == IKControlTypeKey) for (NSNumber *k in c.keycodes) IkemenTouchKey(k.intValue, 0);
        }
    }
    [self.touches removeAllObjects];
    [self.latched removeAllObjects];
    [self.macros removeAllObjects];
    [self.turboStart removeAllObjects];
    for (IKControlView *v in self.views.allValues) { v.pressed = NO; v.dirMask = 0; v.knob = CGPointZero; }
    self.lastMask = 0xFFFFFFFF; // force push
    [self pushState];
}

- (void)setSuspended:(BOOL)suspended {
    _suspended = suspended;
    self.link.paused = suspended;
    if (suspended) [self releaseAll];
}

- (void)tick:(CADisplayLink *)link {
    if (self.superview && self.superview.subviews.lastObject != self) [self.superview bringSubviewToFront:self];
    if (!CGRectEqualToRect(self.frame, self.superview.bounds) && self.superview) self.frame = self.superview.bounds;
    [self pushState];
    [self updateVisibility];
}

- (void)buzz:(CGFloat)scale {
    NSInteger style = self.settings.haptic;
    if (style <= 0) return;
    if (style != self.hapticStyle || !self.haptic) {
        UIImpactFeedbackStyle s = UIImpactFeedbackStyleLight;
        switch (style) {
            case 2: s = UIImpactFeedbackStyleMedium; break;
            case 3: s = UIImpactFeedbackStyleHeavy; break;
            case 4: s = UIImpactFeedbackStyleRigid; break;
            case 5: s = UIImpactFeedbackStyleSoft; break;
            default: break;
        }
        self.haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:s];
        self.hapticStyle = style;
    }
    [self.haptic impactOccurredWithIntensity:MIN(1, self.settings.hapticIntensity * scale)];
    [self.haptic prepare];
}

#pragma mark Settings

- (void)openSettings {
    if (self.settingsOpen) return;
    UIViewController *top = IKTopViewController();
    if (!top) return;
    self.settingsOpen = YES;
    [self releaseAll];
    __weak typeof(self) ws = self;
    [IKSettingsViewController presentFrom:top
        onChange:^{ [ws reloadLayout]; }
        onEditLayout:^{ [ws setEditing:YES]; }
        onDismiss:^{ ws.settingsOpen = NO; [ws reloadLayout]; }];
}

#pragma mark - Editing

- (void)snapshot {
    [self.undo addObject:[self.profile dictionary]];
    if (self.undo.count > 60) [self.undo removeObjectAtIndex:0];
}

- (void)undoLast {
    NSDictionary *d = self.undo.lastObject;
    if (!d) return;
    [self.undo removeLastObject];
    IKProfile *p = [IKProfile profileFromDictionary:d];
    IKLayoutStore *store = IKLayoutStore.shared;
    store.profiles[store.activeIndex] = p;
    [self reloadLayout];
}

- (void)setEditing:(BOOL)editing {
    if (_editing == editing) return;
    [self releaseAll];
    _editing = editing;
    self.pinch.enabled = editing;
    self.selectedId = nil;
    [self.undo removeAllObjects];
    if (editing) {
        [self buildToolbar];
        [self buildGrid];
    } else {
        [self.toolbar removeFromSuperview];
        self.toolbar = nil;
        [self.gridView removeFromSuperview];
        self.gridView = nil;
        [IKLayoutStore.shared save];
    }
    [self reloadLayout];
}

- (UIButton *)toolButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
    b.layer.cornerRadius = 8;
    b.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    if (sel) [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buildToolbar {
    UIStackView *bar = [[UIStackView alloc] init];
    bar.axis = UILayoutConstraintAxisHorizontal;
    bar.spacing = 8;

    UIButton *add = [self toolButton:@"＋ Добавить" action:nil];
    __weak typeof(self) ws = self;
    NSArray *items = @[
        [UIAction actionWithTitle:@"Кнопка (игровая)" image:nil identifier:nil handler:^(UIAction *a) { [ws addControl:IKControlTypeButton]; }],
        [UIAction actionWithTitle:@"Клавиша (Esc, F1…)" image:nil identifier:nil handler:^(UIAction *a) { [ws addControl:IKControlTypeKey]; }],
        [UIAction actionWithTitle:@"Макрос (комбо)" image:nil identifier:nil handler:^(UIAction *a) { [ws addControl:IKControlTypeMacro]; }],
        [UIAction actionWithTitle:@"Крестовина / стик" image:nil identifier:nil handler:^(UIAction *a) { [ws addControl:IKControlTypeDPad]; }],
    ];
    add.menu = [UIMenu menuWithTitle:@"Добавить элемент" children:items];
    add.showsMenuAsPrimaryAction = YES;

    UIButton *grid = [self toolButton:self.settings.snapToGrid ? @"Сетка: вкл" : @"Сетка: выкл" action:@selector(toggleGrid:)];
    UIButton *undo = [self toolButton:@"↶ Отменить" action:@selector(undoLast)];
    UIButton *opts = [self toolButton:@"Настройки" action:@selector(openSettings)];
    UIButton *done = [self toolButton:@"Готово" action:@selector(finishEditing)];
    done.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.9];
    for (UIView *v in @[ add, grid, undo, opts, done ]) [bar addArrangedSubview:v];
    [self addSubview:bar];
    self.toolbar = bar;
    [self layoutToolbar];
}

- (void)layoutToolbar {
    if (!self.toolbar) return;
    CGSize s = [self.toolbar systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    CGFloat top = MAX(self.safeAreaInsets.top, 6) + 2;
    self.toolbar.frame = CGRectMake((self.bounds.size.width - s.width) / 2, top, s.width, s.height);
    [self bringSubviewToFront:self.toolbar];
}

- (void)buildGrid {
    [self.gridView removeFromSuperview];
    self.gridView = nil;
    if (!self.settings.snapToGrid) return;
    UIView *g = [[UIView alloc] initWithFrame:self.bounds];
    g.userInteractionEnabled = NO;
    CAShapeLayer *l = [CAShapeLayer layer];
    UIBezierPath *p = [UIBezierPath bezierPath];
    CGFloat step = MAX(self.settings.gridSize, 4) * 2;
    for (CGFloat x = 0; x < self.bounds.size.width; x += step) { [p moveToPoint:CGPointMake(x, 0)]; [p addLineToPoint:CGPointMake(x, self.bounds.size.height)]; }
    for (CGFloat y = 0; y < self.bounds.size.height; y += step) { [p moveToPoint:CGPointMake(0, y)]; [p addLineToPoint:CGPointMake(self.bounds.size.width, y)]; }
    l.path = p.CGPath;
    l.strokeColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    l.lineWidth = 1;
    [g.layer addSublayer:l];
    [self insertSubview:g atIndex:0];
    self.gridView = g;
}

- (void)toggleGrid:(UIButton *)b {
    self.settings.snapToGrid = !self.settings.snapToGrid;
    [b setTitle:self.settings.snapToGrid ? @"Сетка: вкл" : @"Сетка: выкл" forState:UIControlStateNormal];
    [self buildGrid];
    [self layoutToolbar];
}

- (void)finishEditing { [self setEditing:NO]; }

- (void)addControl:(IKControlType)type {
    [self snapshot];
    IKControl *c = [IKControl controlWithType:type];
    c.cx = 0.5; c.cy = 0.5;
    switch (type) {
        case IKControlTypeButton: c.label = @"A+B"; c.buttons = IKBtnA | IKBtnB; break;
        case IKControlTypeKey: c.label = @"F1"; c.keycodes = @[ @(0x4000003A) ]; c.shape = IKShapeRounded; c.size = 54; c.aspect = 0.55; break;
        case IKControlTypeMacro: c.label = @"236A"; c.macro = @"236+a"; c.showMode = IKShowInFight; break;
        case IKControlTypeDPad: c.size = 140; c.dpadMode = IKDPadModeStick; break;
        default: break;
    }
    [self.profile.controls addObject:c];
    self.selectedId = c.identifier;
    [self reloadLayout];
}

- (IKControl *)editableAt:(CGPoint)p {
    // topmost (last drawn) first
    for (IKControl *c in self.profile.controls.reverseObjectEnumerator) {
        if (CGRectContainsPoint(CGRectInset([self frameForControl:c], -6, -6), p)) return c;
    }
    return nil;
}

- (void)editTouchesBegan:(NSSet<UITouch *> *)touches {
    if (self.dragTouch) return;
    UITouch *t = touches.anyObject;
    CGPoint p = [t locationInView:self];
    IKControl *c = [self editableAt:p];
    self.selectedId = c.identifier;
    if (c) {
        CGRect f = [self frameForControl:c];
        self.dragOffset = CGPointMake(p.x - CGRectGetMidX(f), p.y - CGRectGetMidY(f));
        self.dragTouch = t;
        self.dragMoved = NO;
        [self snapshot];
    }
    for (IKControlView *v in self.views.allValues) v.selected = [v.control.identifier isEqualToString:self.selectedId];
    [self updateInspector];
}

- (void)editTouchesMoved:(NSSet<UITouch *> *)touches {
    if (!self.dragTouch || ![touches containsObject:self.dragTouch] || self.pinch.state == UIGestureRecognizerStateChanged) return;
    IKControl *c = [self controlWithId:self.selectedId];
    if (!c) return;
    CGPoint p = [self.dragTouch locationInView:self];
    CGFloat x = p.x - self.dragOffset.x, y = p.y - self.dragOffset.y;
    if (self.settings.snapToGrid) {
        CGFloat g = MAX(self.settings.gridSize, 2);
        x = round(x / g) * g;
        y = round(y / g) * g;
    }
    CGSize b = self.bounds.size;
    c.cx = MIN(MAX(x / b.width, 0), 1);
    c.cy = MIN(MAX(y / b.height, 0), 1);
    self.dragMoved = YES;
    self.inspector.hidden = YES;
    [self setNeedsLayout];
}

- (void)editTouchesEnded:(NSSet<UITouch *> *)touches {
    if (self.dragTouch && [touches containsObject:self.dragTouch]) {
        if (!self.dragMoved) [self.undo removeLastObject];
        self.dragTouch = nil;
        self.inspector.hidden = NO;
        [self updateInspector];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o {
    return YES;
}

- (void)onPinch:(UIPinchGestureRecognizer *)g {
    IKControl *c = [self controlWithId:self.selectedId];
    if (!c) {
        CGPoint p = [g locationInView:self];
        c = [self editableAt:p];
        if (!c) return;
        self.selectedId = c.identifier;
    }
    if (g.state == UIGestureRecognizerStateBegan) {
        [self snapshot];
        self.pinchBaseSize = c.size;
        self.dragTouch = nil;
    }
    c.size = MIN(MAX(self.pinchBaseSize * g.scale, 16), 400);
    self.inspector.hidden = g.state == UIGestureRecognizerStateChanged;
    [self setNeedsLayout];
}

- (void)updateInspector {
    [self.inspector removeFromSuperview];
    self.inspector = nil;
    IKControl *c = self.editing ? [self controlWithId:self.selectedId] : nil;
    if (!c) return;
    UIStackView *bar = [[UIStackView alloc] init];
    bar.axis = UILayoutConstraintAxisHorizontal;
    bar.spacing = 4;
    NSMutableArray *btns = [NSMutableArray arrayWithArray:@[
        [self toolButton:@"−" action:@selector(shrinkSelected)],
        [self toolButton:@"+" action:@selector(growSelected)],
        [self toolButton:@"Свойства" action:@selector(inspectSelected)],
        [self toolButton:@"Копия" action:@selector(duplicateSelected)],
        [self toolButton:c.visible ? @"Скрыть" : @"Показать" action:@selector(toggleSelectedVisible)],
    ]];
    if (c.type != IKControlTypeMenu) [btns addObject:[self toolButton:@"Удалить" action:@selector(deleteSelected)]];
    for (UIButton *b in btns) { b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]; [bar addArrangedSubview:b]; }
    CGSize s = [bar systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    CGRect f = [self frameForControl:c];
    CGFloat x = MIN(MAX(CGRectGetMidX(f) - s.width / 2, 4), self.bounds.size.width - s.width - 4);
    CGFloat y = f.origin.y - s.height - 6;
    if (y < 50) y = CGRectGetMaxY(f) + 6;
    bar.frame = CGRectMake(x, y, s.width, s.height);
    [self addSubview:bar];
    self.inspector = bar;
}

- (void)shrinkSelected { [self resizeSelected:-6]; }
- (void)growSelected { [self resizeSelected:6]; }
- (void)resizeSelected:(CGFloat)d {
    IKControl *c = [self controlWithId:self.selectedId];
    if (!c) return;
    [self snapshot];
    c.size = MIN(MAX(c.size + d, 16), 400);
    [self setNeedsLayout];
}

- (void)duplicateSelected {
    IKControl *c = [self controlWithId:self.selectedId];
    if (!c || c.type == IKControlTypeMenu) return;
    [self snapshot];
    IKControl *n = [c copy];
    n.identifier = [NSUUID UUID].UUIDString;
    n.cx = MIN(c.cx + 0.05, 1);
    n.cy = MIN(c.cy + 0.05, 1);
    [self.profile.controls addObject:n];
    self.selectedId = n.identifier;
    [self reloadLayout];
}

- (void)toggleSelectedVisible {
    IKControl *c = [self controlWithId:self.selectedId];
    if (!c) return;
    [self snapshot];
    c.visible = !c.visible;
    [self reloadLayout];
}

- (void)deleteSelected {
    IKControl *c = [self controlWithId:self.selectedId];
    if (!c || c.type == IKControlTypeMenu) return;
    [self snapshot];
    [self.profile.controls removeObject:c];
    self.selectedId = nil;
    [self reloadLayout];
}

- (void)inspectSelected {
    IKControl *c = [self controlWithId:self.selectedId];
    UIViewController *top = IKTopViewController();
    if (!c || !top) return;
    [self snapshot];
    __weak typeof(self) ws = self;
    [IKSettingsViewController presentEditorForControl:c from:top
        onChange:^{ [ws reloadLayout]; }
        onDelete:^{ [ws deleteSelected]; }];
}

@end

#pragma mark - C entry points (called from Go)

void IKOverlayInstall(void) {
    if (gOverlay) return;
    UIViewController *root = IKRootViewController();
    if (!root) return;
    IKOverlayView *v = [[IKOverlayView alloc] initWithFrame:root.view.bounds];
    [root.view addSubview:v];
    gOverlay = v;
}

void IKOverlaySetSuspended(int suspended) {
    [gOverlay setSuspended:suspended != 0];
    if (suspended) [IKLayoutStore.shared save];
}
