#import "HBWallet.h"
extern void HBCheck(BOOL condition, const char *message);
static HBWallet *CTParse(NSString *text) { return [[[HBWallet alloc] initWithData:[text dataUsingEncoding:NSUTF8StringEncoding] error:NULL] autorelease]; }
static HBWallet *CTSchedule(NSString *attributes) {
    return CTParse([NSString stringWithFormat:@"<homebank><account key='1'/><account key='2'/><fav account='1' amount='-10' %@/></homebank>", attributes]);
}
static NSArray *CTRange(HBWallet *wallet, NSString *start, NSString *end, NSString *today) {
    return [wallet calendarEntriesFrom:HBOrdinalFromFrenchDate(start) to:HBOrdinalFromFrenchDate(end) today:HBOrdinalFromFrenchDate(today) account:nil includeClosed:NO issues:NULL];
}
void HBCalendarTests(HBWallet *wallet) {
    NSArray *issues = nil;
    int start = HBOrdinalFromFrenchDate(@"01/10/2026"), end = HBOrdinalFromFrenchDate(@"31/10/2026"), today = HBOrdinalFromFrenchDate(@"07/10/2026");
    NSArray *entries = [wallet calendarEntriesFrom:start to:end today:today account:@"1" includeClosed:NO issues:&issues];
    HBCheck([entries count] == 5 && [issues count] == 0, "calendar combines future posted entries and forecasts but excludes void operations");
    NSArray *totals = [wallet totalsForEntries:entries]; NSDictionary *total = [totals count] ? [totals objectAtIndex:0] : nil;
    HBCheck([[total objectForKey:@"expenses"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"50"]], "calendar expense total includes the forecast");
    HBCheck([[total objectForKey:@"transferOut"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"25"]], "internal transfers are summed independently of expenses");
    entries = [wallet calendarEntriesFrom:start to:end today:end account:@"1" includeClosed:NO issues:&issues];
    HBCheck([entries count] == 4, "today and past use posted entries only");
    entries = [wallet calendarEntriesFrom:start to:end today:today account:nil includeClosed:NO issues:&issues];
    total = [[wallet totalsForEntries:entries] objectAtIndex:0];
    HBCheck([[total objectForKey:@"transferIn"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"25"]]
        && [[total objectForKey:@"transferOut"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"25"]], "global transfers are not cancelled into zero");
    NSString *next = [NSString stringWithFormat:@"%d", HBOrdinalFromFrenchDate(@"31/01/2026")];
    HBWallet *monthly = CTSchedule([NSString stringWithFormat:@"recflg='1' unit='2' every='1' nextdate='%@'", next]);
    entries = CTRange(monthly, @"31/01/2026", @"31/03/2026", @"30/01/2026");
    HBCheck([entries count] == 3 && [[[entries lastObject] objectForKey:@"date"] intValue] == HBOrdinalFromFrenchDate(@"31/03/2026"), "preserves monthly end-of-month gap");
    HBWallet *relative = CTSchedule([NSString stringWithFormat:@"recflg='5' unit='2' every='1' ordn='5' wkdy='5' nextdate='%d'", HBOrdinalFromFrenchDate(@"30/01/2026")]);
    entries = CTRange(relative, @"01/02/2026", @"28/02/2026", @"31/01/2026");
    HBCheck([entries count] == 1 && [[[entries objectAtIndex:0] objectForKey:@"date"] intValue] == HBOrdinalFromFrenchDate(@"27/02/2026"), "relative last Friday recurrence");
    HBWallet *limited = CTSchedule([NSString stringWithFormat:@"recflg='3' limit='2' unit='2' nextdate='%@'", next]);
    entries = CTRange(limited, @"01/02/2026", @"31/12/2026", @"01/02/2026");
    HBCheck([entries count] == 1, "remaining occurrence limit includes old unposted positions");
    HBWallet *before = CTSchedule([NSString stringWithFormat:@"recflg='1' unit='2' weekend='1' nextdate='%@'", next]);
    entries = CTRange(before, @"30/01/2026", @"30/01/2026", @"29/01/2026");
    HBCheck([entries count] == 1, "Friday-before weekend shift crosses the date-range boundary");
    HBWallet *after = CTSchedule([NSString stringWithFormat:@"recflg='1' unit='2' weekend='2' nextdate='%@'", next]);
    entries = CTRange(after, @"02/02/2026", @"02/02/2026", @"01/02/2026"); HBCheck([entries count] == 1, "Monday-after weekend shift");
    HBWallet *skip = CTSchedule([NSString stringWithFormat:@"recflg='1' unit='0' weekend='3' nextdate='%d'", HBOrdinalFromFrenchDate(@"30/01/2026")]);
    entries = CTRange(skip, @"30/01/2026", @"02/02/2026", @"29/01/2026"); HBCheck([entries count] == 2, "daily recurrence skips weekends");
    HBWallet *legacy = CTSchedule([NSString stringWithFormat:@"flags='132' limit='1' unit='2' nextdate='%@'", next]);
    HBCheck([CTRange(legacy, @"01/01/2026", @"31/12/2026", @"01/01/2026") count] == 1, "legacy recurrence and limit flag bits");
    HBWallet *invalid = CTSchedule([NSString stringWithFormat:@"recflg='1' every='0' nextdate='%@'", next]);
    entries = [invalid recurringEntriesForAccount:nil includeClosed:NO issues:&issues];
    HBCheck([entries count] == 0 && [issues count] > 0, "malformed recurrences report incomplete forecasts");
    HBWallet *history = CTParse([NSString stringWithFormat:@"<homebank><account key='1'/><account key='2' flags='2'/><ope account='2' date='%d' amount='10'/></homebank>", start]);
    HBCheck([[history calendarEntriesFrom:start to:end today:today account:nil includeClosed:NO issues:NULL] count] == 0
        && [[history calendarEntriesFrom:start to:end today:today account:nil includeClosed:YES issues:NULL] count] == 1, "closed account history is opt-in in calendar only");
    HBWallet *currencies = CTParse([NSString stringWithFormat:@"<homebank><cur key='1' iso='EUR'/><cur key='2' iso='USD'/><account key='1' curr='1'/><account key='2' curr='2'/><fav recflg='1' flags='8' account='1' dst_account='2' amount='-10' damt='12' unit='2' nextdate='%d'/></homebank>", start + 14]);
    entries = [currencies calendarEntriesFrom:start to:end today:today account:nil includeClosed:NO issues:NULL];
    HBCheck([entries count] == 2 && [[currencies totalsForEntries:entries] count] == 2, "cross-currency forecasts keep totals separate");
    NSArray *nextEntries = [wallet recurringEntriesForAccount:@"1" includeClosed:NO issues:NULL];
    HBCheck([nextEntries count] == 1, "recurrences show next occurrence independent of the selected month");
}
