#import "HBApplication.h"
#include <stdio.h>
#include <stdlib.h>

@interface HBApplication (ForecastTestSurface)
- (void)buildForecastControlsInView:(NSView *)view;
- (void)selectAccount;
- (void)filterRecords;
- (NSDictionary *)selectedAccount;
- (void)manualForecastChanged:(id)sender;
- (void)launchForecast:(NSDictionary *)context;
- (void)layout;
@end

@interface HFSlowWallet : HBWallet { BOOL _slow; }
- (void)setSlow:(BOOL)slow;
@end
@implementation HFSlowWallet
- (void)setSlow:(BOOL)slow { _slow = slow; }
- (NSDictionary *)futureForecastForAccount:(NSDictionary *)account today:(int)today manual:(BOOL)manual until:(int)until {
    if (_slow) [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
    return [super futureForecastForAccount:account today:today manual:manual until:until];
}
@end

@interface HFForecastApplication : HBApplication { NSString *_selectedKey; unsigned int _launches; }
- (id)initWithWallet:(HBWallet *)wallet;
- (void)chooseAccount:(NSString *)key;
- (void)chooseManual:(BOOL)enabled date:(NSString *)date;
- (void)replaceWallet:(HBWallet *)wallet;
- (BOOL)ready;
- (BOOL)manual;
- (BOOL)enabled;
- (BOOL)dateVisible;
- (NSString *)future;
- (NSString *)note;
- (NSDictionary *)forecast;
- (unsigned int)launches;
- (BOOL)controlsFit;
@end
@implementation HFForecastApplication
- (id)initWithWallet:(HBWallet *)wallet {
    self = [super init]; if (self) {
        _wallet = [wallet retain];
        _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 480) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
        [_window setReleasedWhenClosed:NO];
        _balanceLabels = [[NSMutableArray alloc] init];
        unsigned int i;
        for (i = 0; i < 3; i++) {
            NSTextField *field = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
            [field setEditable:NO]; [_balanceLabels addObject:field]; [[_window contentView] addSubview:field];
        }
        [self buildForecastControlsInView:[_window contentView]];
        [self layout];
    } return self;
}
- (NSDictionary *)selectedAccount { return _selectedKey ? [_wallet accountWithKey:_selectedKey] : nil; }
- (void)filterRecords { }
- (void)chooseAccount:(NSString *)key { [_selectedKey release]; _selectedKey = [key copy]; [self selectAccount]; }
- (void)chooseManual:(BOOL)enabled date:(NSString *)date {
    [_forecastToggle setState:enabled ? NSOnState : NSOffState]; [_forecastDate setStringValue:date];
    [self manualForecastChanged:_forecastToggle];
}
- (void)replaceWallet:(HBWallet *)wallet { [wallet retain]; [_wallet release]; _wallet = wallet; [self selectAccount]; }
- (void)launchForecast:(NSDictionary *)context { _launches++; [super launchForecast:context]; }
- (BOOL)ready { return !_forecastBusy && !_forecastPending && _forecastResult != nil; }
- (BOOL)manual { return [_forecastToggle state] == NSOnState; }
- (BOOL)enabled { return [_forecastToggle isEnabled]; }
- (BOOL)dateVisible { return ![_forecastDate isHidden]; }
- (NSString *)future { return [[_balanceLabels objectAtIndex:2] stringValue]; }
- (NSString *)note { return [_forecastNote stringValue]; }
- (NSDictionary *)forecast { return _forecastResult; }
- (unsigned int)launches { return _launches; }
- (BOOL)controlsFit {
    NSRect toggle = [_forecastToggle frame], date = [_forecastDate frame], hint = [_forecastDateHint frame];
    return NSMaxX(toggle) < date.origin.x && NSMaxX(date) < hint.origin.x && NSMaxX(hint) < [[_window contentView] bounds].size.width;
}
- (void)dealloc { [_selectedKey release]; [super dealloc]; }
@end

static unsigned int checks = 0, failures = 0;
static void HBTestCheck(BOOL condition, const char *message) { checks++; if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message); } }
static void waitReady(HFForecastApplication *application) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (![application ready] && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    HBTestCheck([application ready], "forecast worker completes on the main thread");
}
static NSString *dateText(int ordinal) { return [HBDateFromOrdinal(ordinal) descriptionWithCalendarFormat:@"%d/%m/%Y"]; }
static BOOL shows(HFForecastApplication *application, NSString *amount) { return [[application future] rangeOfString:amount].location != NSNotFound; }

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; [NSApplication sharedApplication];
    int today = HBOrdinalFromDate(HBToday());
    NSString *xml = [NSString stringWithFormat:@"<homebank v='1.6'><cur key='1' iso='EUR'/><properties curr='1'/>"
        "<account key='1' name='Salaire fictif' curr='1' initial='1000'/><account key='2' name='Epargne fictive' type='7' curr='1' initial='500'/><account key='3' flags='2' initial='50'/>"
        "<cat key='1' name='Revenus'/><cat key='2' name='Salaires' parent='1'/>"
        "<ope account='1' date='%d' amount='-50' st='2'/><ope account='1' date='%d' amount='2000' category='2'/><ope account='1' date='%d' amount='-100'/>"
        "<fav account='1' recflg='1' unit='2' nextdate='%d' amount='2000' wording='Employeur fictif' category='2'/><fav account='1' recflg='1' unit='2' nextdate='%d' amount='-100'/>"
        "<ope account='2' date='%d' amount='-50'/><ope account='2' date='%d' amount='-100'/><fav account='2' recflg='1' unit='2' nextdate='%d' amount='-25'/></homebank>",
        today - 1, today + 20, today + 21, today + 50, today + 2, today + 1, today + 5, today + 3];
    NSString *error = nil; NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
    HBWallet *wallet = [[[HBWallet alloc] initWithData:data error:&error] autorelease];
    HBTestCheck(wallet && !error, "synthetic UI wallet loads");
    HFForecastApplication *application = [[HFForecastApplication alloc] initWithWallet:wallet];
    [application chooseAccount:@"1"]; waitReady(application);
    HBTestCheck(shows(application, @"850,00") && [[application note] hasPrefix:@"Avant le"], "salary budget is the default");
    HBTestCheck([application enabled] && ![application manual] && ![application dateVisible], "manual option is available on a salary account");
    unsigned int launches = [application launches]; [application chooseAccount:@"1"];
    HBTestCheck([application ready] && [application launches] == launches, "reselecting an unchanged account reuses the cached result");
    [application chooseManual:YES date:dateText(today + 20)]; waitReady(application);
    HBTestCheck(shows(application, @"2 850,00") && [[application note] hasPrefix:@"Au"] && [application dateVisible], "manual date overrides salary and includes its day");
    HBTestCheck([application controlsFit], "forecast controls do not overlap at the minimum window width");
    [application chooseAccount:@"2"]; waitReady(application);
    HBTestCheck(shows(application, @"350,00") && ![application manual], "savings without salary defaults to recorded balances");
    [application chooseManual:YES date:dateText(today + 3)]; waitReady(application);
    HBTestCheck(shows(application, @"425,00"), "savings supports an inclusive chosen date");
    [application chooseAccount:@"1"]; waitReady(application);
    HBTestCheck([application manual] && shows(application, @"2 850,00"), "manual settings survive switching accounts and remain account-specific");
    [application chooseManual:NO date:dateText(today + 20)]; waitReady(application);
    HBTestCheck(shows(application, @"850,00") && [[application note] hasPrefix:@"Avant le"], "turning the option off restores automatic salary detection");
    [application chooseManual:YES date:@"31/02/2026"]; waitReady(application);
    HBTestCheck([[application future] isEqualToString:@"--"] && [[application note] rangeOfString:@"date valide"].location != NSNotFound, "invalid French dates hide unreliable balances");
    [application chooseManual:YES date:dateText(today - 1)]; waitReady(application);
    HBTestCheck(![[[application forecast] objectForKey:@"available"] boolValue], "expired manual dates are rejected");
    [application chooseManual:NO date:dateText(today + 20)]; waitReady(application);
    HBTestCheck([wallet generation] == 0 && [[wallet baseSourceData] isEqualToData:data], "forecast controls never edit XML or append to the journal");

    NSDictionary *salaryRecord = nil; unsigned int i;
    for (i = 0; i < [[wallet records] count]; i++) if ([[[[wallet records] objectAtIndex:i] objectForKey:@"category"] isEqualToString:@"2"]) salaryRecord = [[wallet records] objectAtIndex:i];
    HBWallet *changed = [wallet walletByDeletingRecord:salaryRecord error:&error];
    launches = [application launches]; [application replaceWallet:changed]; waitReady(application);
    HBTestCheck(changed && shows(application, @"650,00") && [application launches] > launches, "wallet edits invalidate cached forecasts without changing other balances");
    [application chooseAccount:@"3"];
    HBTestCheck(![application enabled] && ![application dateVisible], "closed accounts have no manual forecast control");
    [application chooseAccount:nil]; HBTestCheck(![application enabled] && [[application future] length] == 0, "empty account selection stays safe");
    [application release];

    HFSlowWallet *slow = [[[HFSlowWallet alloc] initWithData:data error:&error] autorelease]; [slow setSlow:YES];
    application = [[HFForecastApplication alloc] initWithWallet:slow];
    [application chooseAccount:@"1"];
    for (i = 1; i <= 20; i++) [application chooseManual:YES date:dateText(today + i)];
    [application chooseAccount:@"2"]; [application chooseManual:YES date:dateText(today + 3)]; waitReady(application);
    HBTestCheck(shows(application, @"425,00") && [application launches] <= 2, "rapid date/account changes coalesce into one pending calculation and discard obsolete results");
    [application chooseAccount:@"1"]; waitReady(application);
    HBTestCheck(shows(application, @"2 850,00") && [application manual], "coalescing keeps the latest preference of each account");
    NSString *testPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    [data writeToFile:testPath atomically:YES];
    HBTestCheck([application openPath:testPath], "explicit import of a synthetic file succeeds"); waitReady(application);
    HBTestCheck(![application manual] && shows(application, @"850,00"), "opening a file resets session-only forecast choices");
    [[NSFileManager defaultManager] removeFileAtPath:testPath handler:nil];
    [application release];
    printf("%u/%u forecast UI checks passed\n", checks - failures, checks);
    [pool release]; return failures ? 1 : 0;
}
