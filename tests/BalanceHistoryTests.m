#import "HBBalanceHistory.h"
#import "HBWalletStore.h"
#include <stdlib.h>
#include <math.h>
extern void HBCheck(BOOL condition, const char *message);
static HBWallet *HTParse(NSString *text) { return [[[HBWallet alloc] initWithData:[text dataUsingEncoding:NSUTF8StringEncoding] error:NULL] autorelease]; }
static HBBalanceHistory *HTHistory(HBWallet *wallet, NSString *scope, NSString *currency, int today, int months) {
    return [[[HBBalanceHistory alloc] initWithWallet:wallet accounts:[HBBalanceHistory accountsForWallet:wallet scope:scope currency:currency] today:today months:months error:NULL] autorelease];
}
static BOOL HTAmount(HBBalanceHistory *history, int date, NSString *value) { return [[history balanceAt:date] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:value]]; }
void HBBalanceHistoryTests(HBWallet *wallet) {
    int today = HBOrdinalFromFrenchDate(@"07/10/2026"), monthEnd = HBOrdinalFromFrenchDate(@"31/10/2026");
    NSArray *bank = [HBBalanceHistory accountsForWallet:wallet scope:@"bank" currency:nil];
    HBCheck([bank count] == 2 && [[HBBalanceHistory accountsForWallet:wallet scope:@"savings" currency:nil] count] == 1, "history scopes separate bank/savings and exclude closed accounts");
    HBCheck([[HBBalanceHistory accountsForWallet:wallet scope:@"account:3" currency:nil] count] == 0, "closed accounts cannot enter balance history");
    NSString *error = nil;
    HBCheck([[[HBBalanceHistory alloc] initWithWallet:wallet accounts:bank today:today months:12 error:&error] autorelease] == nil && [error length], "balance report never adds different currencies");
    HBBalanceHistory *history = HTHistory(wallet, @"account:1", nil, today, 3);
    HBCheck(history && [[history issues] count] == 0, "builds bounded history and projection using working data");
    HBCheck(HTAmount(history, today, @"70"), "balance includes initial and every recorded non-void status");
    HBCheck(HTAmount(history, monthEnd, @"25"), "future balance combines posted transfer, posted expense and planned expense");
    HBCheck([history end] == HBOrdinalFromFrenchDate(@"07/01/2027"), "three month horizon is calendar based");
    HBCheck(HTAmount(HTHistory(wallet, @"savings", nil, today, 12), monthEnd, @"265"), "savings report includes posted incoming transfers");
    HBCheck(HTAmount(HTHistory(wallet, @"bank", @"2", today, 12), monthEnd, @"10"), "currency selector isolates dollar initial balance");
    HBCheck([HBHistoryOverdraft([wallet accountWithKey:@"1"]) isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"-50"]], "overdraft uses HomeBank minimum");
    HBCheck([HBHistoryOverdraft([NSDictionary dictionaryWithObject:[NSDecimalNumber decimalNumberWithString:@"350"] forKey:@"minimum"]) isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"-350"]], "positive overdraft amounts normalize to a negative limit");
    HBCheck([HBHistoryOverdraft([wallet accountWithKey:@"2"]) isEqualToNumber:[NSDecimalNumber zero]], "no authorized overdraft means zero");
    unsigned int count = 0; HBBalancePoint *points = [history copyPointsFrom:[history start] to:[history end] limit:30 count:&count];
    HBCheck(points && count <= 30 && points[0].date == [history start] && points[count - 1].date == [history end], "draw samples are bounded and preserve endpoints");
    BOOL hasToday = NO; unsigned int i; for (i = 0; i < count; i++) if (points[i].date == today) hasToday = YES;
    HBCheck(hasToday, "today's actual/forecast junction is never sampled away"); free(points);
    HBHistoryRange range = HBHistoryPreset(history, 1);
    HBCheck(range.start == [history start] && range.end == today, "short historic presets never slide into future dates");
    range = HBHistoryPreset(history, 5); HBCheck(range.start == today && range.end == [history end], "forecast preset starts at today's posted balance");
    for (i = 0; i < 20; i++) range = HBHistoryZoom(range, history, 0.5);
    HBCheck(range.end - range.start == 1, "zooms down to one day");
    for (i = 0; i < 20; i++) range = HBHistoryZoom(range, history, 2);
    HBCheck(range.start == [history start] && range.end == [history end], "dezooms over the complete history and future domain");
    NSData *before = [wallet sourceData];
    HTHistory(wallet, @"bank", @"1", today, 60);
    HBCheck([[wallet sourceData] isEqualToData:before] && [wallet generation] == 0, "report never edits XML, templates or journal");

    HBWallet *decimal = HTParse(@"<homebank><account key='1' initial='0.1'/><ope account='1' date='739890' amount='0.2'/></homebank>");
    HBCheck(HTAmount(HTHistory(decimal, @"account:1", nil, today, 12), today, @"0.3"), "reported balances retain exact decimal precision");
    NSString *scheduled = [NSString stringWithFormat:@"<homebank><account key='1' initial='100'/><account key='2' type='7' initial='200'/><fav account='1' dst_account='2' amount='-10' flags='8' recflg='3' limit='2' unit='2' nextdate='%d'/></homebank>", today + 1];
    HBWallet *transfer = HTParse(scheduled);
    HBCheck(HTAmount(HTHistory(transfer, @"savings", nil, today, 12), HBOrdinalFromFrenchDate(@"30/11/2026"), @"220"), "planned transfers into destination-only scope are included");
    HBCheck(HTAmount(HTHistory(transfer, @"account:1", nil, today, 12), HBOrdinalFromFrenchDate(@"30/11/2026"), @"80"), "source transfers respect remaining installment limit");
    transfer = HTParse([[scheduled componentsSeparatedByString:@"type='7'"] componentsJoinedByString:@"type='1'"]);
    HBCheck(HTAmount(HTHistory(transfer, @"bank", nil, today, 12), HBOrdinalFromFrenchDate(@"30/11/2026"), @"300"), "two planned transfer legs cancel inside the same scope");
    HBWallet *foreign = HTParse([NSString stringWithFormat:@"<homebank><cur key='1' iso='EUR'/><cur key='2' iso='USD'/><account key='1' curr='1'/><account key='2' curr='2'/><fav account='1' dst_account='2' amount='-10' damt='12' flags='8' recflg='3' limit='1' unit='2' nextdate='%d'/></homebank>", today + 1]);
    HBCheck(HTAmount(HTHistory(foreign, @"account:2", nil, today, 3), today + 1, @"12"), "cross-currency planned transfer uses saved destination amount");
    HBWallet *limited = HTParse([NSString stringWithFormat:@"<homebank><account key='1' initial='100'/><fav account='1' amount='-10' recflg='3' limit='6' unit='0' nextdate='%d'/></homebank>", today - 2]);
    HBCheck(HTAmount(HTHistory(limited, @"bank", nil, today, 12), today, @"100") && HTAmount(HTHistory(limited, @"bank", nil, today, 12), today + 3, @"70"), "forecasts never backfill past days or today");
    HBWallet *posted = HTParse([NSString stringWithFormat:@"<homebank><account key='1' initial='100'/><ope account='1' amount='-10' date='%d'/><fav account='1' amount='-10' recflg='3' limit='1' unit='2' nextdate='%d'/></homebank>", today + 1, today + 32]);
    HBCheck(HTAmount(HTHistory(posted, @"bank", nil, today, 12), today + 1, @"90"), "nextdate prevents recreating already posted installments");
    posted = HTParse([NSString stringWithFormat:@"<homebank><account key='1' initial='100'/><ope account='1' amount='-10' date='%d'/><fav account='1' amount='-10' recflg='3' limit='1' unit='2' nextdate='%d'/></homebank>", today + 1, today + 1]);
    HBCheck(HTAmount(HTHistory(posted, @"bank", nil, today, 12), today + 1, @"80"), "does not guess duplicates between independent posted and planned amounts");
    HBWallet *invalid = HTParse([NSString stringWithFormat:@"<homebank><account key='1' initial='100'/><fav account='1' recflg='1' every='0' nextdate='%d'/></homebank>", today + 1]);
    HBCheck([[HTHistory(invalid, @"bank", nil, today, 3) issues] count] > 0, "invalid schedules report incomplete projections");
    HBWallet *empty = HTParse(@"<homebank><account key='1' initial='100'/></homebank>");
    history = HTHistory(empty, @"bank", nil, HBOrdinalFromFrenchDate(@"31/01/2026"), 3);
    HBCheck([history end] == HBOrdinalFromFrenchDate(@"30/04/2026") && HTAmount(history, [history end], @"100"), "month horizons clamp month-end dates and keep constant balances");
    history = HTHistory(empty, @"bank", nil, HBOrdinalFromFrenchDate(@"29/02/2024"), 12);
    HBCheck([history end] == HBOrdinalFromFrenchDate(@"28/02/2025"), "annual horizon handles leap days");
    history = HTHistory(empty, @"bank", nil, HBOrdinalFromFrenchDate(@"30/12/9999"), 60);
    HBCheck([history end] == 3652059, "bounds future dates at HomeBank year 9999");
    NSMutableString *large = [NSMutableString stringWithString:@"<homebank><account key='1' initial='100'/>"];
    for (i = 0; i < 3000; i++) [large appendFormat:@"<ope account='1' date='%u' amount='%d'/>", 730486 + i, i == 1234 ? -5000 : i == 1235 ? 5000 : 0];
    [large appendString:@"</homebank>"]; HBWallet *many = HTParse(large); history = HTHistory(many, @"bank", nil, today, 60);
    points = [history copyPointsFrom:[history start] to:[history end] limit:120 count:&count]; BOOL extreme = NO;
    for (i = 0; i < count; i++) if (fabs(points[i].balance + 4900) < 0.01) extreme = YES;
    HBCheck(count <= 120 && extreme, "long-history sampling preserves real daily extrema rather than averaging them away"); free(points);
}
