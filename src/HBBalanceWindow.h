#import <Cocoa/Cocoa.h>
#import "HBBalanceView.h"

@interface HBBalanceWindow : NSObject {
    HBWallet *_wallet;
    HBBalanceHistory *_history;
    NSWindow *_window;
    HBBalanceView *_plot;
    NSPopUpButton *_scope, *_currency, *_horizon;
    NSSegmentedControl *_periodControl;
    NSTextField *_from, *_to, *_closingTitle, *_closing, *_legend, *_status;
    NSMutableArray *_labels;
    NSButton *_previous, *_next, *_zoomIn, *_zoomOut;
    HBHistoryRange _range;
    int _period;
    unsigned int _request;
    BOOL _busy, _needsRefresh;
}
- (id)initWithWallet:(HBWallet *)wallet account:(NSString *)key;
- (void)setWallet:(HBWallet *)wallet;
- (void)show;
@end
