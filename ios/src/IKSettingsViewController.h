#import <UIKit/UIKit.h>
#import "IKLayout.h"

NS_ASSUME_NONNULL_BEGIN

@interface IKSettingsViewController : UITableViewController
// Global settings / profiles / presets / import-export.
+ (void)presentFrom:(UIViewController *)presenter
           onChange:(void (^)(void))onChange
       onEditLayout:(void (^)(void))onEditLayout
          onDismiss:(void (^)(void))onDismiss;

// Inspector for a single control.
+ (void)presentEditorForControl:(IKControl *)control
                           from:(UIViewController *)presenter
                       onChange:(void (^)(void))onChange
                       onDelete:(void (^)(void))onDelete;
@end

NS_ASSUME_NONNULL_END
