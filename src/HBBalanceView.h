#import <Cocoa/Cocoa.h>
#import "HBBalanceHistory.h"

@interface HBBalanceView : NSView {
    HBBalanceHistory *_history;
    HBWallet *_wallet;
    NSDecimalNumber *_overdraft;
    HBHistoryRange _range;
    HBBalancePoint *_samples;
    unsigned int _sampleCount;
    NSImage *_image;
    BOOL _cachedDark, _dragging;
    double _minimum, _maximum;
    int _hoverDate, _dragStart, _dragDate;
    id _delegate;
}
- (void)setHistory:(HBBalanceHistory *)history wallet:(HBWallet *)wallet range:(HBHistoryRange)range overdraft:(NSDecimalNumber *)overdraft;
- (void)setRange:(HBHistoryRange)range;
- (void)setDelegate:(id)delegate;
@end

@interface NSObject (HBBalanceViewDelegate)
- (void)balanceView:(HBBalanceView *)view selectFrom:(int)start to:(int)end;
- (void)balanceView:(HBBalanceView *)view zoom:(double)factor;
- (void)balanceView:(HBBalanceView *)view shift:(int)direction;
@end
