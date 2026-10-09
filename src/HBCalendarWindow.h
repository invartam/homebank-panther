#import <Cocoa/Cocoa.h>
#import "HBWallet.h"

@interface HBCalendarWindow : NSObject {
    HBWallet *_wallet;
    NSWindow *_window, *_agenda;
    NSSegmentedControl *_mode;
    NSPopUpButton *_account;
    NSButton *_closed, *_previous, *_next, *_today, *_monthButton;
    NSTextField *_heading, *_totals, *_issues, *_agendaTitle, *_agendaTotals;
    NSMutableArray *_cells, *_weekdays;
    NSArray *_entries, *_recurrences, *_agendaEntries;
    NSScrollView *_recurrenceScroll, *_agendaScroll;
    NSTableView *_recurrenceTable, *_agendaTable;
    int _year, _month, _agendaMonth;
    BOOL _needsRefresh;
}
- (id)initWithWallet:(HBWallet *)wallet account:(NSString *)key;
- (void)setWallet:(HBWallet *)wallet;
- (void)show;
@end
