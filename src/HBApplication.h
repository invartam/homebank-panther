#import <Cocoa/Cocoa.h>
#import "HBWallet.h"
#import "HBOperationEditor.h"
#import "HBCalendarWindow.h"
#import "HBBalanceWindow.h"
#import "HBDrivePanel.h"
#import "HBJournal.h"

typedef HBIndex HBRow;

@interface HBApplication : NSObject {
    NSWindow *_window;
    NSButton *_openButton;
    NSPopUpButton *_group;
    NSTableView *_accountsTable;
    NSTableView *_recordsTable;
    NSScrollView *_accountsScroll;
    NSScrollView *_recordsScroll;
    NSTextField *_ownerLabel;
    NSTextField *_accountLabel;
    NSTextField *_statusLabel;
    NSTextField *_pageLabel;
    NSMutableArray *_balanceTitles;
    NSMutableArray *_balanceLabels;
    NSButton *_previous;
    NSButton *_next;
    HBWallet *_wallet;
    NSString *_path;
    NSArray *_visibleAccounts;
    NSArray *_visibleRecords;
    unsigned int _page;
    NSButton *_newButton, *_editButton, *_saveButton, *_exportButton, *_calendarButton, *_deleteButton, *_pointButton, *_reconcileButton;
    NSSearchField *_search;
    NSData *_savedData;
    NSString *_savedHash;
    HBWallet *_savedWallet;
    NSDictionary *_journalState;
    BOOL _dirty;
    BOOL _refreshingSelection;
    HBCalendarWindow *_calendar;
    HBBalanceWindow *_balanceWindow;
    NSButton *_graphButton;
    NSButton *_driveButton, *_syncButton;
    NSTextField *_driveLabel;
    HBDriveClient *_drive;
    NSDictionary *_driveSettings, *_driveState;
    NSString *_driveCachePath;
    NSTimer *_saveTimer;
    BOOL _saveBusy, _syncRequested;
    BOOL _checkpointRequested;
    NSString *_saveError;
    BOOL _driveActive, _driveBusy, _driveLoading, _driveManual;
    NSButton *_forecastToggle;
    NSTextField *_forecastDate, *_forecastNote, *_forecastDateHint;
    NSMutableDictionary *_manualForecasts, *_forecastCache;
    HBWallet *_forecastWallet;
    NSDictionary *_forecastPending, *_forecastResult;
    NSString *_forecastControlAccountKey;
    unsigned int _forecastRequest;
    int _forecastToday;
    BOOL _forecastBusy;
}
- (void)buildInterface;
- (BOOL)openPath:(NSString *)path;
@end
