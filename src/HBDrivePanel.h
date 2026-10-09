#import <Cocoa/Cocoa.h>
#import "HBDrive.h"

@interface HBDrivePanel : NSObject {
    NSWindow *_window;
    NSTextField *_fileID, *_curlPath, *_caPath, *_keyLabel;
    NSData *_keyData;
    NSString *_keyAlias;
    NSDictionary *_result;
}
- (id)initWithSettings:(NSDictionary *)settings;
- (NSDictionary *)run;
@end
