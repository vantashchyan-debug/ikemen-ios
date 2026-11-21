#import <UIKit/UIKit.h>
#import "IKLayout.h"

NS_ASSUME_NONNULL_BEGIN

@interface IKOverlayView : UIView
@property (nonatomic, readonly) BOOL editing;
+ (nullable instancetype)shared;
- (void)reloadLayout;                 // after profile/settings changed
- (void)setEditing:(BOOL)editing;
- (void)openSettings;
- (void)releaseAll;                   // drop every held input
- (void)setSuspended:(BOOL)suspended;
@end

UIViewController *_Nullable IKRootViewController(void);

NS_ASSUME_NONNULL_END
