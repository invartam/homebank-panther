#import "PantherString.h"

@implementation HBPString
- (id)initWithValue:(NSString *)value { self = [super init]; if (self) _value = [value copy]; return self; }
- (HBPStringIndex)length { return [_value length]; }
- (unichar)characterAtIndex:(HBPStringIndex)index { return [_value characterAtIndex:index]; }
- (const char *)UTF8String { return [_value UTF8String]; }
- (int)intValue { return [_value intValue]; }
- (id)copyWithZone:(NSZone *)zone { (void)zone; return [self retain]; }
- (long long)longLongValue { [NSException raise:NSInvalidArgumentException format:@"Panther string has no longLongValue"]; return 0; }
- (double)doubleValue { [NSException raise:NSInvalidArgumentException format:@"Panther string has no doubleValue"]; return 0; }
- (void)dealloc { [_value release]; [super dealloc]; }
@end
