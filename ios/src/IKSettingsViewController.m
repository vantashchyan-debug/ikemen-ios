// Settings UI for the touch controls (UIKit, insetGrouped table forms).

#import "IKSettingsViewController.h"
#import "IKBridge.h"

#pragma mark - Form model

typedef NS_ENUM(NSInteger, IKRowKind) {
    IKRowAction, IKRowDisclosure, IKRowSwitch, IKRowSlider, IKRowSegment, IKRowText, IKRowColor, IKRowCheck, IKRowInfo,
};

@interface IKRow : NSObject
@property (nonatomic) IKRowKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic) BOOL destructive;
// values
@property (nonatomic, copy, nullable) BOOL (^getBool)(void);
@property (nonatomic, copy, nullable) void (^setBool)(BOOL v);
@property (nonatomic, copy, nullable) double (^getNum)(void);
@property (nonatomic, copy, nullable) void (^setNum)(double v);
@property (nonatomic) double minValue, maxValue, step;
@property (nonatomic, copy, nullable) NSString *format;   // value label format, e.g. @"%.0f%%"
@property (nonatomic) double displayScale;                // value shown = v * displayScale
@property (nonatomic, copy, nullable) NSArray<NSString *> *segments;
@property (nonatomic, copy, nullable) NSString * (^getText)(void);
@property (nonatomic, copy, nullable) void (^setText)(NSString *v);
@property (nonatomic, copy, nullable) NSString *placeholder;
@property (nonatomic, copy, nullable) UIColor * (^getColor)(void);
@property (nonatomic, copy, nullable) void (^setColor)(UIColor *c);
@property (nonatomic, copy, nullable) void (^action)(void);
@property (nonatomic) BOOL reloadOnChange;
@end
@implementation IKRow
- (instancetype)init { if ((self = [super init])) { _step = 0; _displayScale = 1; } return self; }
@end

@interface IKSection : NSObject
@property (nonatomic, copy, nullable) NSString *title, *footer;
@property (nonatomic, strong) NSMutableArray<IKRow *> *rows;
@end
@implementation IKSection
@end

@interface IKNav : UINavigationController
@end
@implementation IKNav
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
@end

@interface IKSettingsViewController () <UIAdaptivePresentationControllerDelegate, UITextFieldDelegate>
@property (nonatomic, copy) void (^builder)(IKSettingsViewController *vc);
@property (nonatomic, strong) NSMutableArray<IKSection *> *sections;
@property (nonatomic, copy, nullable) void (^onChange)(void);
@property (nonatomic, copy, nullable) void (^onDismiss)(void);
@property (nonatomic, copy, nullable) void (^onEditLayout)(void);
@end

@implementation IKSettingsViewController

- (instancetype)initWithTitle:(NSString *)title builder:(void (^)(IKSettingsViewController *))builder {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = title;
        _builder = [builder copy];
        _sections = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)rebuild {
    [self.sections removeAllObjects];
    if (self.builder) self.builder(self);
    [self.tableView reloadData];
}

- (IKSection *)section:(NSString *)title footer:(NSString *)footer {
    IKSection *s = [IKSection new];
    s.title = title;
    s.footer = footer;
    s.rows = [NSMutableArray array];
    [self.sections addObject:s];
    return s;
}

- (void)changed {
    // propagate up to the root form, which owns the callback
    UIViewController *root = self.navigationController.viewControllers.firstObject ?: self;
    IKSettingsViewController *r = [root isKindOfClass:[IKSettingsViewController class]] ? (IKSettingsViewController *)root : self;
    if (r.onChange) r.onChange();
    else if (self.onChange) self.onChange();
}

- (void)close {
    [self.view endEditing:YES];
    [IKLayoutStore.shared save];
    UIViewController *root = self.navigationController.viewControllers.firstObject ?: self;
    IKSettingsViewController *r = [root isKindOfClass:[IKSettingsViewController class]] ? (IKSettingsViewController *)root : self;
    void (^dismiss)(void) = r.onDismiss;
    [self.navigationController dismissViewControllerAnimated:YES completion:^{ if (dismiss) dismiss(); }];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)pc {
    [IKLayoutStore.shared save];
    if (self.onDismiss) self.onDismiss();
}

#pragma mark Row factories

static IKRow *RAction(NSString *t, NSString *d, void (^a)(void)) {
    IKRow *r = [IKRow new]; r.kind = IKRowAction; r.title = t; r.detail = d; r.action = a; return r;
}
static IKRow *RDisclosure(NSString *t, NSString *d, void (^a)(void)) {
    IKRow *r = RAction(t, d, a); r.kind = IKRowDisclosure; return r;
}
static IKRow *RSwitch(NSString *t, BOOL (^g)(void), void (^s)(BOOL)) {
    IKRow *r = [IKRow new]; r.kind = IKRowSwitch; r.title = t; r.getBool = g; r.setBool = s; return r;
}
static IKRow *RSlider(NSString *t, double mn, double mx, NSString *fmt, double (^g)(void), void (^s)(double)) {
    IKRow *r = [IKRow new]; r.kind = IKRowSlider; r.title = t; r.minValue = mn; r.maxValue = mx; r.format = fmt; r.getNum = g; r.setNum = s; return r;
}
static IKRow *RSegment(NSString *t, NSArray *segs, double (^g)(void), void (^s)(double)) {
    IKRow *r = [IKRow new]; r.kind = IKRowSegment; r.title = t; r.segments = segs; r.getNum = g; r.setNum = s; return r;
}
static IKRow *RText(NSString *t, NSString *ph, NSString * (^g)(void), void (^s)(NSString *)) {
    IKRow *r = [IKRow new]; r.kind = IKRowText; r.title = t; r.placeholder = ph; r.getText = g; r.setText = s; return r;
}
static IKRow *RColor(NSString *t, UIColor * (^g)(void), void (^s)(UIColor *)) {
    IKRow *r = [IKRow new]; r.kind = IKRowColor; r.title = t; r.getColor = g; r.setColor = s; return r;
}
static IKRow *RCheck(NSString *t, NSString *d, BOOL (^g)(void), void (^s)(BOOL)) {
    IKRow *r = [IKRow new]; r.kind = IKRowCheck; r.title = t; r.detail = d; r.getBool = g; r.setBool = s; return r;
}
static IKRow *RInfo(NSString *t, NSString *d) {
    IKRow *r = [IKRow new]; r.kind = IKRowInfo; r.title = t; r.detail = d; return r;
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.sections[s].rows.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return self.sections[s].title; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return self.sections[s].footer; }

- (IKRow *)rowAt:(NSIndexPath *)ip { return self.sections[ip.section].rows[ip.row]; }

- (NSString *)valueText:(IKRow *)r value:(double)v {
    return [NSString stringWithFormat:r.format ?: @"%.2f", v * r.displayScale];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    IKRow *r = [self rowAt:ip];
    UITableViewCellStyle style = (r.kind == IKRowInfo || r.kind == IKRowCheck || r.kind == IKRowAction) && r.detail
                                     ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.textLabel.text = r.title;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSInteger tag = ip.section * 1000 + ip.row;

    switch (r.kind) {
        case IKRowAction:
            cell.textLabel.textColor = r.destructive ? UIColor.systemRedColor : UIColor.systemBlueColor;
            cell.detailTextLabel.text = r.detail;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        case IKRowDisclosure:
            cell.detailTextLabel.text = r.detail;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        case IKRowInfo:
            cell.detailTextLabel.text = r.detail;
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            break;
        case IKRowSwitch: {
            UISwitch *sw = [UISwitch new];
            sw.on = r.getBool ? r.getBool() : NO;
            sw.tag = tag;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
        }
        case IKRowCheck:
            cell.detailTextLabel.text = r.detail;
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            cell.accessoryType = (r.getBool && r.getBool()) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        case IKRowSlider: {
            double v = r.getNum ? r.getNum() : 0;
            cell.detailTextLabel.text = [self valueText:r value:v];
            UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 220, 30)];
            sl.minimumValue = r.minValue;
            sl.maximumValue = r.maxValue;
            sl.value = v;
            sl.tag = tag;
            [sl addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sl;
            break;
        }
        case IKRowSegment: {
            UISegmentedControl *sc = [[UISegmentedControl alloc] initWithItems:r.segments];
            sc.selectedSegmentIndex = r.getNum ? (NSInteger)r.getNum() : 0;
            sc.tag = tag;
            [sc addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
            [sc sizeToFit];
            cell.accessoryView = sc;
            break;
        }
        case IKRowText: {
            UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 260, 30)];
            tf.text = r.getText ? r.getText() : @"";
            tf.placeholder = r.placeholder;
            tf.textAlignment = NSTextAlignmentRight;
            tf.autocorrectionType = UITextAutocorrectionTypeNo;
            tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            tf.spellCheckingType = UITextSpellCheckingTypeNo;
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
            tf.returnKeyType = UIReturnKeyDone;
            tf.delegate = self;
            tf.tag = tag;
            [tf addTarget:self action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
            cell.accessoryView = tf;
            break;
        }
        case IKRowColor: {
            UIColorWell *well = [[UIColorWell alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
            well.supportsAlpha = NO;
            well.selectedColor = r.getColor ? r.getColor() : UIColor.whiteColor;
            well.tag = tag;
            [well addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = well;
            break;
        }
    }
    return cell;
}

- (IKRow *)rowForTag:(NSInteger)tag {
    NSInteger s = tag / 1000, r = tag % 1000;
    if (s >= (NSInteger)self.sections.count || r >= (NSInteger)self.sections[s].rows.count) return nil;
    return self.sections[s].rows[r];
}

- (void)after:(IKRow *)r {
    [self changed];
    if (r.reloadOnChange) [self rebuild];
}

- (void)switchChanged:(UISwitch *)sw {
    IKRow *r = [self rowForTag:sw.tag];
    if (r.setBool) r.setBool(sw.on);
    [self after:r];
}

- (void)sliderChanged:(UISlider *)sl {
    IKRow *r = [self rowForTag:sl.tag];
    double v = sl.value;
    if (r.step > 0) v = round(v / r.step) * r.step;
    if (r.setNum) r.setNum(v);
    NSIndexPath *ip = [NSIndexPath indexPathForRow:sl.tag % 1000 inSection:sl.tag / 1000];
    [self.tableView cellForRowAtIndexPath:ip].detailTextLabel.text = [self valueText:r value:v];
    [self changed];
}

- (void)segmentChanged:(UISegmentedControl *)sc {
    IKRow *r = [self rowForTag:sc.tag];
    if (r.setNum) r.setNum(sc.selectedSegmentIndex);
    [self after:r];
}

- (void)textChanged:(UITextField *)tf {
    IKRow *r = [self rowForTag:tf.tag];
    if (r.setText) r.setText(tf.text ?: @"");
    [self changed];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

- (void)colorChanged:(UIColorWell *)well {
    IKRow *r = [self rowForTag:well.tag];
    if (r.setColor && well.selectedColor) r.setColor(well.selectedColor);
    [self changed];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    IKRow *r = [self rowAt:ip];
    if (r.kind == IKRowCheck) {
        BOOL v = r.getBool ? r.getBool() : NO;
        if (r.setBool) r.setBool(!v);
        [self changed];
        [self rebuild];
    } else if (r.action) {
        r.action();
    }
}

#pragma mark Alerts

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirm:(NSString *)title message:(NSString *)msg action:(NSString *)act then:(void (^)(void))then {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:act style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { then(); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)prompt:(NSString *)title value:(NSString *)value then:(void (^)(NSString *))then {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = value; tf.clearButtonMode = UITextFieldViewModeAlways; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *t = [wa.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (t.length) then(t);
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)choosePreset:(NSString *)title then:(void (^)(NSString *))then {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *n in IKLayoutStore.presetNames) {
        [a addAction:[UIAlertAction actionWithTitle:n style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { then(n); }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Global settings form

+ (void)buildMain:(IKSettingsViewController *)vc {
    IKLayoutStore *store = IKLayoutStore.shared;
    IKProfile *p = store.active;
    IKGlobalSettings *s = p.settings;
    __weak IKSettingsViewController *w = vc;

    IKSection *sec = [vc section:@"Профиль" footer:@"Профиль хранит раскладку и все настройки. Можно держать несколько и переключаться между ними."];
    [sec.rows addObject:RDisclosure(@"Активный профиль", p.name, ^{ [w pushProfiles]; })];
    [sec.rows addObject:RAction(@"Переименовать", nil, ^{
        [w prompt:@"Имя профиля" value:p.name then:^(NSString *t) { p.name = t; [store save]; [w rebuild]; }];
    })];

    sec = [vc section:@"Раскладка" footer:@"В режиме редактирования элементы перетаскиваются пальцем, размер меняется щипком. Тап по элементу открывает панель: размер, свойства, копия, скрыть, удалить."];
    [sec.rows addObject:RAction(@"✎ Редактировать раскладку на экране", nil, ^{
        IKSettingsViewController *root = (IKSettingsViewController *)w.navigationController.viewControllers.firstObject;
        void (^edit)(void) = root.onEditLayout;
        void (^dismiss)(void) = root.onDismiss;
        [store save];
        [w.navigationController dismissViewControllerAnimated:YES completion:^{
            if (dismiss) dismiss();
            if (edit) edit();
        }];
    })];
    [sec.rows addObject:RDisclosure(@"Все элементы", [NSString stringWithFormat:@"%lu", (unsigned long)p.controls.count], ^{ [w pushControlList]; })];
    [sec.rows addObject:RAction(@"Применить пресет…", @"Заменит элементы текущего профиля", ^{
        [w choosePreset:@"Пресет раскладки" then:^(NSString *n) {
            IKProfile *pr = [IKLayoutStore presetNamed:n];
            p.controls = pr.controls;
            [store save]; [w changed]; [w rebuild];
        }];
    })];
    [sec.rows addObject:RAction(@"Отразить по горизонтали (для левши)", nil, ^{
        [p mirrorHorizontally];
        [store save]; [w changed]; [w rebuild];
    })];

    sec = [vc section:@"Внешний вид" footer:nil];
    [sec.rows addObject:RSlider(@"Прозрачность", 0.05, 1, @"%.0f%%", ^double { return s.opacity; }, ^(double v) { s.opacity = v; })];
    sec.rows.lastObject.displayScale = 100;
    [sec.rows addObject:RSlider(@"При нажатии", 0.05, 1, @"%.0f%%", ^double { return s.pressedOpacity; }, ^(double v) { s.pressedOpacity = v; })];
    sec.rows.lastObject.displayScale = 100;
    [sec.rows addObject:RSlider(@"Общий масштаб", 0.4, 2.5, @"×%.2f", ^double { return s.scale; }, ^(double v) { s.scale = v; })];
    [sec.rows addObject:RSegment(@"Стиль", @[ @"Контур", @"Заливка", @"Минимал" ], ^double { return s.style; }, ^(double v) { s.style = (IKStyle)v; })];
    [sec.rows addObject:RSwitch(@"Подписи на кнопках", ^BOOL { return s.showLabels; }, ^(BOOL v) { s.showLabels = v; })];
    [sec.rows addObject:RSwitch(@"Анимация нажатия", ^BOOL { return s.pressAnimation; }, ^(BOOL v) { s.pressAnimation = v; })];
    [sec.rows addObject:RColor(@"Цвет", ^UIColor * { return IKColorFromHex(s.accentHex, UIColor.whiteColor); }, ^(UIColor *c) { s.accentHex = IKHexFromColor(c); })];
    [sec.rows addObject:RSlider(@"Затухание при бездействии", 0, 30, @"%.0f с", ^double { return s.idleFadeSeconds; }, ^(double v) { s.idleFadeSeconds = v; })];
    sec.rows.lastObject.step = 1;
    [sec.rows addObject:RSlider(@"Прозрачность в покое", 0, 1, @"%.0f%%", ^double { return s.idleOpacity; }, ^(double v) { s.idleOpacity = v; })];
    sec.rows.lastObject.displayScale = 100;

    sec = [vc section:@"Управление" footer:@"«Скольжение» — палец можно вести с кнопки на кнопку без отрыва. «Нажатие между кнопками» — касание на стыке зон нажимает обе (удобно для A+B одним пальцем). Размер зон настраивается у каждой кнопки."];
    [sec.rows addObject:RSegment(@"Управляет игроком", @[ @"P1", @"P2", @"P3", @"P4" ], ^double { return s.player; }, ^(double v) { s.player = (NSInteger)v; })];
    [sec.rows addObject:RSwitch(@"Скольжение между кнопками", ^BOOL { return s.slideAcross; }, ^(BOOL v) { s.slideAcross = v; })];
    [sec.rows addObject:RSwitch(@"Нажатие между кнопками", ^BOOL { return s.multiHit; }, ^(BOOL v) { s.multiHit = v; })];

    sec = [vc section:@"Вибрация" footer:nil];
    [sec.rows addObject:RSegment(@"Отклик", @[ @"Выкл", @"Лёгк", @"Сред", @"Сильн", @"Жёстк", @"Мягк" ], ^double { return s.haptic; }, ^(double v) { s.haptic = (NSInteger)v; })];
    [sec.rows addObject:RSlider(@"Сила", 0.1, 1, @"%.0f%%", ^double { return s.hapticIntensity; }, ^(double v) { s.hapticIntensity = v; })];
    sec.rows.lastObject.displayScale = 100;
    [sec.rows addObject:RSwitch(@"При отпускании", ^BOOL { return s.hapticOnRelease; }, ^(BOOL v) { s.hapticOnRelease = v; })];
    [sec.rows addObject:RSwitch(@"При смене направления", ^BOOL { return s.hapticOnDirection; }, ^(BOOL v) { s.hapticOnDirection = v; })];

    sec = [vc section:@"Геймпад" footer:@"MFi / Xbox / PlayStation контроллеры работают сразу, через Bluetooth."];
    [sec.rows addObject:RSwitch(@"Скрывать сенсор при подключённом геймпаде", ^BOOL { return s.hideWithGamepad; }, ^(BOOL v) { s.hideWithGamepad = v; })];

    sec = [vc section:@"Редактор" footer:nil];
    [sec.rows addObject:RSwitch(@"Привязка к сетке", ^BOOL { return s.snapToGrid; }, ^(BOOL v) { s.snapToGrid = v; })];
    [sec.rows addObject:RSlider(@"Шаг сетки", 2, 32, @"%.0f pt", ^double { return s.gridSize; }, ^(double v) { s.gridSize = v; })];
    sec.rows.lastObject.step = 1;

    sec = [vc section:@"Обмен раскладками" footer:@"Формат — JSON. Файл раскладок: Файлы → На iPhone → Ikemen → Ikemen/save/touch_layout.json"];
    [sec.rows addObject:RAction(@"Скопировать текущий профиль", nil, ^{
        UIPasteboard.generalPasteboard.string = [store exportJSON:NO];
        [w alert:@"Скопировано" message:@"JSON профиля в буфере обмена."];
    })];
    [sec.rows addObject:RAction(@"Скопировать все профили", nil, ^{
        UIPasteboard.generalPasteboard.string = [store exportJSON:YES];
        [w alert:@"Скопировано" message:@"JSON всех профилей в буфере обмена."];
    })];
    [sec.rows addObject:RAction(@"Поделиться файлом…", nil, ^{
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ikemen_touch_layout.json"];
        [[store exportJSON:YES] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[ [NSURL fileURLWithPath:path] ] applicationActivities:nil];
        avc.popoverPresentationController.sourceView = w.view;
        [w presentViewController:avc animated:YES completion:nil];
    })];
    [sec.rows addObject:RAction(@"Импорт из буфера обмена", nil, ^{
        NSString *err = nil;
        if ([store importJSON:UIPasteboard.generalPasteboard.string ?: @"" error:&err]) {
            [w changed]; [w rebuild];
            [w alert:@"Готово" message:@"Профиль импортирован и выбран."];
        } else {
            [w alert:@"Ошибка импорта" message:err];
        }
    })];

    sec = [vc section:@"Сброс" footer:nil];
    IKRow *reset = RAction(@"Сбросить текущий профиль", @"Вернёт «Классику» и стандартные настройки", ^{
        [w confirm:@"Сбросить профиль?" message:p.name action:@"Сбросить" then:^{
            IKProfile *def = [IKLayoutStore presetNamed:IKLayoutStore.presetNames[0]];
            def.name = p.name;
            store.profiles[store.activeIndex] = def;
            [store save]; [w changed]; [w rebuild];
        }];
    });
    reset.destructive = YES;
    [sec.rows addObject:reset];

    sec = [vc section:@"О порте" footer:nil];
    [sec.rows addObject:RInfo(@"Ikemen GO для iOS", @"Рендер Vulkan → Metal (MoltenVK). Свои персонажи и стейджи можно подложить через приложение «Файлы»: папка Ikemen. Настоящая папка заменяет встроенную с тем же именем (chars, stages, data…).")];
}

- (void)pushProfiles {
    IKLayoutStore *store = IKLayoutStore.shared;
    IKSettingsViewController *list = [[IKSettingsViewController alloc] initWithTitle:@"Профили" builder:^(IKSettingsViewController *vc) {
        __weak IKSettingsViewController *w = vc;
        IKSection *sec = [vc section:nil footer:@"Тап — сделать активным."];
        for (NSInteger i = 0; i < (NSInteger)store.profiles.count; i++) {
            IKProfile *p = store.profiles[i];
            [sec.rows addObject:RCheck(p.name, [NSString stringWithFormat:@"%lu элементов", (unsigned long)p.controls.count],
                                       ^BOOL { return store.activeIndex == i; },
                                       ^(BOOL v) { store.activeIndex = i; [store save]; })];
        }
        sec = [vc section:nil footer:nil];
        [sec.rows addObject:RAction(@"＋ Новый профиль из пресета…", nil, ^{
            [w choosePreset:@"Основа для профиля" then:^(NSString *n) {
                [store.profiles addObject:[IKLayoutStore presetNamed:n]];
                store.activeIndex = store.profiles.count - 1;
                [store save]; [w changed]; [w rebuild];
            }];
        })];
        [sec.rows addObject:RAction(@"Дублировать активный", nil, ^{
            IKProfile *c = [store.active copy];
            c.name = [store.active.name stringByAppendingString:@" (копия)"];
            [store.profiles addObject:c];
            store.activeIndex = store.profiles.count - 1;
            [store save]; [w changed]; [w rebuild];
        })];
        if (store.profiles.count > 1) {
            IKRow *del = RAction(@"Удалить активный", nil, ^{
                [w confirm:@"Удалить профиль?" message:store.active.name action:@"Удалить" then:^{
                    [store.profiles removeObjectAtIndex:store.activeIndex];
                    store.activeIndex = 0;
                    [store save]; [w changed]; [w rebuild];
                }];
            });
            del.destructive = YES;
            [sec.rows addObject:del];
        }
    }];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)pushControlList {
    IKLayoutStore *store = IKLayoutStore.shared;
    IKSettingsViewController *list = [[IKSettingsViewController alloc] initWithTitle:@"Элементы" builder:^(IKSettingsViewController *vc) {
        __weak IKSettingsViewController *w = vc;
        IKProfile *p = store.active;
        IKSection *sec = [vc section:nil footer:@"Скрытые элементы тоже здесь: включите «Видимость» в свойствах."];
        for (IKControl *c in p.controls) {
            NSString *name = c.label.length ? c.label : @"(без подписи)";
            if (!c.visible) name = [name stringByAppendingString:@"  · скрыт"];
            [sec.rows addObject:RDisclosure(name, c.summary, ^{ [w pushEditorFor:c]; })];
        }
        sec = [vc section:@"Добавить" footer:nil];
        NSArray *types = @[ @[ @"Кнопка", @(IKControlTypeButton) ], @[ @"Клавиша", @(IKControlTypeKey) ],
                            @[ @"Макрос", @(IKControlTypeMacro) ], @[ @"Крестовина / стик", @(IKControlTypeDPad) ] ];
        for (NSArray *t in types) {
            [sec.rows addObject:RAction([@"＋ " stringByAppendingString:t[0]], nil, ^{
                IKControl *c = [IKControl controlWithType:(IKControlType)[t[1] integerValue]];
                c.label = t[0];
                if (c.type == IKControlTypeButton) c.buttons = IKBtnA;
                if (c.type == IKControlTypeMacro) c.macro = @"236+a";
                [p.controls addObject:c];
                [store save]; [w changed];
                [w pushEditorFor:c];
            })];
        }
    }];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)pushEditorFor:(IKControl *)c {
    __weak IKSettingsViewController *weakSelf = self;
    IKSettingsViewController *ed = [[IKSettingsViewController alloc] initWithTitle:c.label.length ? c.label : @"Элемент" builder:^(IKSettingsViewController *vc) {
        __weak IKSettingsViewController *wvc = vc;
        [IKSettingsViewController buildEditor:vc control:c onDelete:^{
            [IKLayoutStore.shared.active.controls removeObject:c];
            [IKLayoutStore.shared save];
            [weakSelf changed];
            [wvc.navigationController popViewControllerAnimated:YES];
        }];
    }];
    [self.navigationController pushViewController:ed animated:YES];
}

#pragma mark - Control editor form

+ (void)buildEditor:(IKSettingsViewController *)vc control:(IKControl *)c onDelete:(void (^)(void))onDelete {
    __weak IKSettingsViewController *w = vc;
    BOOL isPad = c.type == IKControlTypeDPad;

    IKSection *sec = [vc section:@"Основное" footer:[c summary]];
    [sec.rows addObject:RText(@"Подпись", @"A, START, 236A…", ^NSString * { return c.label; }, ^(NSString *t) { c.label = t; })];
    [sec.rows addObject:RSwitch(@"Видимость", ^BOOL { return c.visible; }, ^(BOOL v) { c.visible = v; })];
    if (c.type != IKControlTypeMenu) {
        [sec.rows addObject:RSegment(@"Показывать", @[ @"Всегда", @"В бою", @"В меню" ], ^double { return c.showMode; }, ^(double v) { c.showMode = (IKShowMode)v; })];
    }

    sec = [vc section:@"Размер и положение" footer:@"Зона касания может быть больше видимой кнопки: так легче попадать, не глядя."];
    [sec.rows addObject:RSlider(@"Размер", 16, 320, @"%.0f pt", ^double { return c.size; }, ^(double v) { c.size = v; })];
    sec.rows.lastObject.step = 1;
    if (!isPad) {
        [sec.rows addObject:RSlider(@"Высота / ширина", 0.25, 3, @"%.2f", ^double { return c.aspect; }, ^(double v) { c.aspect = v; })];
        [sec.rows addObject:RSegment(@"Форма", @[ @"Круг", @"Скругл.", @"Квадрат" ], ^double { return c.shape; }, ^(double v) { c.shape = (IKShape)v; })];
    }
    [sec.rows addObject:RSlider(@"Зона касания", 0.5, 2.5, @"×%.2f", ^double { return c.hitScale; }, ^(double v) { c.hitScale = v; })];
    [sec.rows addObject:RSlider(@"Позиция X", 0, 1, @"%.1f%%", ^double { return c.cx; }, ^(double v) { c.cx = v; })];
    sec.rows.lastObject.displayScale = 100;
    [sec.rows addObject:RSlider(@"Позиция Y", 0, 1, @"%.1f%%", ^double { return c.cy; }, ^(double v) { c.cy = v; })];
    sec.rows.lastObject.displayScale = 100;

    sec = [vc section:@"Цвет и прозрачность" footer:nil];
    IKRow *ownOp = RSwitch(@"Своя прозрачность", ^BOOL { return c.opacity >= 0; }, ^(BOOL v) { c.opacity = v ? 0.6 : -1; });
    ownOp.reloadOnChange = YES;
    [sec.rows addObject:ownOp];
    if (c.opacity >= 0) {
        [sec.rows addObject:RSlider(@"Прозрачность", 0.05, 1, @"%.0f%%", ^double { return c.opacity; }, ^(double v) { c.opacity = v; })];
        sec.rows.lastObject.displayScale = 100;
    }
    IKRow *ownColor = RSwitch(@"Свой цвет", ^BOOL { return c.colorHex != nil; }, ^(BOOL v) { c.colorHex = v ? @"#FFD60A" : nil; });
    ownColor.reloadOnChange = YES;
    [sec.rows addObject:ownColor];
    if (c.colorHex) {
        [sec.rows addObject:RColor(@"Цвет", ^UIColor * { return IKColorFromHex(c.colorHex, UIColor.whiteColor); }, ^(UIColor *col) { c.colorHex = IKHexFromColor(col); })];
    }

    switch (c.type) {
        case IKControlTypeDPad: {
            sec = [vc section:@"Крестовина" footer:@"Мёртвая зона — радиус в центре без нажатия. Ширина диагоналей: больше — диагонали легче, меньше — чище «вперёд/назад». Плавающий стик появляется там, где коснулся палец, в своей половине экрана."];
            IKRow *mode = RSegment(@"Режим", @[ @"8 напр.", @"4 напр.", @"Стик", @"Плавающий" ], ^double { return c.dpadMode; }, ^(double v) { c.dpadMode = (IKDPadMode)v; });
            mode.reloadOnChange = YES;
            [sec.rows addObject:mode];
            [sec.rows addObject:RSlider(@"Мёртвая зона", 0, 0.9, @"%.0f%%", ^double { return c.deadzone; }, ^(double v) { c.deadzone = v; })];
            sec.rows.lastObject.displayScale = 100;
            if (c.dpadMode != IKDPadMode4Way) {
                [sec.rows addObject:RSlider(@"Ширина диагоналей", 10, 80, @"%.0f°", ^double { return c.diagonalWidth; }, ^(double v) { c.diagonalWidth = v; })];
                sec.rows.lastObject.step = 1;
            }
            if (c.dpadMode == IKDPadModeFloatingStick) {
                [sec.rows addObject:RSlider(@"Зона появления", 0.15, 0.9, @"%.0f%% экрана", ^double { return c.floatingZone; }, ^(double v) { c.floatingZone = v; })];
                sec.rows.lastObject.displayScale = 100;
                [sec.rows addObject:RSwitch(@"Возвращать на место", ^BOOL { return c.snapBack; }, ^(BOOL v) { c.snapBack = v; })];
            }
            break;
        }
        case IKControlTypeButton: {
            sec = [vc section:@"Нажимает кнопки" footer:@"Можно выбрать несколько: кнопка нажмёт их одновременно (например, x+y для броска или a+b+c для супера). Направления тоже можно."];
            NSArray *desc = @[ @"Вверх", @"Вниз", @"Влево", @"Вправо", @"Удар / A", @"B", @"C", @"X", @"Y", @"Z",
                               @"Start", @"D (доп.)", @"W (доп.)", @"Menu" ];
            NSArray *names = IKButtonNames();
            for (int i = 0; i < IK_BUTTON_COUNT; i++) {
                uint32_t bit = 1u << i;
                [sec.rows addObject:RCheck(names[i], desc[i], ^BOOL { return (c.buttons & bit) != 0; }, ^(BOOL v) {
                    if (v) c.buttons |= bit; else c.buttons &= ~bit;
                })];
            }
            sec = [vc section:@"Поведение" footer:@"Турбо — автоповтор, пока держишь. Фиксация — первое касание включает, второе выключает (например, для «держать блок»)."];
            IKRow *turbo = RSwitch(@"Турбо", ^BOOL { return c.turbo; }, ^(BOOL v) { c.turbo = v; });
            turbo.reloadOnChange = YES;
            [sec.rows addObject:turbo];
            if (c.turbo) {
                [sec.rows addObject:RSlider(@"Частота турбо", 2, 30, @"%.0f Гц", ^double { return c.turboHz; }, ^(double v) { c.turboHz = v; })];
                sec.rows.lastObject.step = 1;
            }
            [sec.rows addObject:RSwitch(@"Фиксация (вкл/выкл)", ^BOOL { return c.toggle; }, ^(BOOL v) { c.toggle = v; })];
            break;
        }
        case IKControlTypeKey: {
            sec = [vc section:@"Нажимает клавиши" footer:@"Esc — пауза/назад, Enter — подтвердить, F1–F12 — горячие клавиши Ikemen (тренировка, отладка), Pause/ScrollLock — пауза и покадровый шаг."];
            for (NSNumber *k in IKSelectableKeys()) {
                [sec.rows addObject:RCheck(IKKeyName(k.integerValue), nil, ^BOOL { return [c.keycodes containsObject:k]; }, ^(BOOL v) {
                    NSMutableArray *m = [c.keycodes mutableCopy];
                    if (v) { if (![m containsObject:k]) [m addObject:k]; } else [m removeObject:k];
                    c.keycodes = m;
                })];
            }
            break;
        }
        case IKControlTypeMacro: {
            sec = [vc section:@"Макрос" footer:IKMacroHelp];
            [sec.rows addObject:RText(@"Скрипт", @"236+a", ^NSString * { return c.macro; }, ^(NSString *t) { c.macro = t; })];
            [sec.rows addObject:RAction(@"Проверить", nil, ^{
                NSString *err = nil;
                NSArray *steps = IKParseMacro(c.macro, 1, &err);
                if (!steps) { [w alert:@"Ошибка" message:err]; return; }
                NSMutableArray *lines = [NSMutableArray array];
                int total = 0;
                for (NSValue *v in steps) {
                    IKMacroStep st; [v getValue:&st];
                    [lines addObject:[NSString stringWithFormat:@"%@ ×%d", IKButtonMaskName(st.mask), st.frames]];
                    total += st.frames;
                }
                [w alert:[NSString stringWithFormat:@"%lu шагов, %d кадров (%.2f с)", (unsigned long)steps.count, total, total / 60.0]
                 message:[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n\n(для персонажа, смотрящего вправо)"]];
            })];
            [sec.rows addObject:RSwitch(@"Повторять, пока держишь", ^BOOL { return c.macroLoop; }, ^(BOOL v) { c.macroLoop = v; })];
            break;
        }
        case IKControlTypeMenu:
            sec = [vc section:@"Меню" footer:@"Эта кнопка открывает настройки сенсора. Её нельзя удалить, но можно сделать почти прозрачной или маленькой."];
            break;
    }

    if (c.type != IKControlTypeMenu && onDelete) {
        sec = [vc section:nil footer:nil];
        IKRow *del = RAction(@"Удалить элемент", nil, ^{
            [w confirm:@"Удалить элемент?" message:c.label action:@"Удалить" then:onDelete];
        });
        del.destructive = YES;
        [sec.rows addObject:del];
    }
}

#pragma mark - Presentation

+ (void)presentNav:(IKSettingsViewController *)root from:(UIViewController *)presenter {
    IKNav *nav = [[IKNav alloc] initWithRootViewController:root];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.presentationController.delegate = root;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [presenter presentViewController:nav animated:YES completion:nil];
}

+ (void)presentFrom:(UIViewController *)presenter
           onChange:(void (^)(void))onChange
       onEditLayout:(void (^)(void))onEditLayout
          onDismiss:(void (^)(void))onDismiss {
    IKSettingsViewController *vc = [[IKSettingsViewController alloc] initWithTitle:@"Сенсорное управление" builder:^(IKSettingsViewController *v) {
        [IKSettingsViewController buildMain:v];
    }];
    vc.onChange = onChange;
    vc.onEditLayout = onEditLayout;
    vc.onDismiss = onDismiss;
    [self presentNav:vc from:presenter];
}

+ (void)presentEditorForControl:(IKControl *)control
                           from:(UIViewController *)presenter
                       onChange:(void (^)(void))onChange
                       onDelete:(void (^)(void))onDelete {
    IKSettingsViewController *vc = [[IKSettingsViewController alloc] initWithTitle:control.label.length ? control.label : @"Элемент" builder:^(IKSettingsViewController *v) {
        __weak IKSettingsViewController *wv = v;
        [IKSettingsViewController buildEditor:v control:control onDelete:^{
            [wv.navigationController dismissViewControllerAnimated:YES completion:^{ if (onDelete) onDelete(); }];
        }];
    }];
    vc.onChange = onChange;
    vc.onDismiss = onChange;
    [self presentNav:vc from:presenter];
}

@end
