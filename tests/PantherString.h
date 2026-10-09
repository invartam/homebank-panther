#import <Foundation/Foundation.h>

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
typedef NSUInteger HBPStringIndex;
#else
typedef unsigned int HBPStringIndex;
#endif

/* No longLongValue, like Panther; also guards integer IDs against float conversion. */
@interface HBPString : NSString {
    NSString *_value;
}
- (id)initWithValue:(NSString *)value;
@end
