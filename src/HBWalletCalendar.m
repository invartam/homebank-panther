#import "HBWallet.h"

static HBIndex HBEntryOrder(id a, id b, void *context) {
    int left = [[a objectForKey:@"date"] intValue], right = [[b objectForKey:@"date"] intValue];
    return left < right ? NSOrderedAscending : left > right ? NSOrderedDescending : NSOrderedSame;
}
static BOOL HBField(NSDictionary *record, NSString *name, unsigned long fallback, unsigned long max, unsigned long *result) {
    NSString *raw = [record objectForKey:name];
    if (!raw || ![raw length]) { *result = fallback; return YES; }
    return HBParseUnsigned(raw, max, result);
}
static BOOL HBVisible(HBWallet *wallet, NSString *key, NSString *filter, BOOL closed) {
    NSDictionary *account = [wallet accountWithKey:key];
    return account && (closed || !([[account objectForKey:@"flags"] intValue] & 2)) && (!filter || [filter isEqualToString:key]);
}
static NSCalendarDate *HBMonthDate(int year, int month, int day) {
    return [NSCalendarDate dateWithYear:year month:month day:day hour:12 minute:0 second:0 timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
}
static int HBMonthDays(int year, int month) {
    NSCalendarDate *next = HBMonthDate(year + (month == 12), month == 12 ? 1 : month + 1, 1);
    return [[next dateByAddingYears:0 months:0 days:-1 hours:0 minutes:0 seconds:0] dayOfMonth];
}
static int HBWeekday(NSCalendarDate *date) { int day = [date dayOfWeek]; return day == 0 ? 7 : day; }
static int HBPostDate(int ordinal, int weekend) {
    int weekday = HBWeekday(HBDateFromOrdinal(ordinal));
    if (weekday < 6) return ordinal;
    return weekend == 1 ? ordinal - (weekday - 5) : weekend == 2 ? ordinal + (8 - weekday) : ordinal;
}
static int HBAdvance(int ordinal, unsigned long unit, unsigned long every, unsigned long recFlags,
    unsigned long weekday, unsigned long order, unsigned long weekend, unsigned long *gap) {
    NSCalendarDate *current = HBDateFromOrdinal(ordinal), *next;
    if ((recFlags & 4) || unit >= 2) {
        int months = [current yearOfCommonEra] * 12 + [current monthOfYear] - 1 + every * ((recFlags & 4) || unit == 2 ? 1 : 12);
        int year = months / 12, month = months % 12 + 1, days = HBMonthDays(year, month), day = [current dayOfMonth];
        if (year > 9999) return 0;
        if (recFlags & 4) {
            if (weekday == 8) day = order == 5 ? days : order;
            else {
                day = 1 + ((int)weekday - HBWeekday(HBMonthDate(year, month, 1)) + 7) % 7 + 7 * ((int)order - 1);
                if (day > days) day -= 7;
            }
        } else if (day > days) day = days;
        next = HBMonthDate(year, month, day);
    } else next = [current dateByAddingYears:0 months:0 days:every * (unit == 1 ? 7 : 1) hours:0 minutes:0 seconds:0];
    if (!(recFlags & 4)) {
        if (weekend == 3 && HBWeekday(next) >= 6) next = [next dateByAddingYears:0 months:0 days:8 - HBWeekday(next) hours:0 minutes:0 seconds:0];
        /* Match the web projection's persisted HomeBank month-end gap. */
        if (unit >= 2) {
            if ([current dayOfMonth] >= 28) {
                if (*gap) next = [next dateByAddingYears:0 months:0 days:*gap hours:0 minutes:0 seconds:0];
                int difference = [current dayOfMonth] + *gap - [next dayOfMonth];
                *gap = difference < 0 ? 0 : difference > 3 ? 3 : difference;
            } else *gap = 0;
        }
    }
    int result = HBOrdinalFromDate(next);
    return result >= 1 && result <= 3652059 ? result : 0;
}

@implementation HBWallet (Calendar)
- (NSArray *)forecastFrom:(int)start to:(int)end account:(NSString *)filter includeClosed:(BOOL)closed nextOnly:(BOOL)nextOnly issues:(NSMutableArray *)issues {
    NSMutableArray *entries = [NSMutableArray array];
    unsigned int i, totalSteps = 0;
    for (i = 0; i < [[self templates] count]; i++) {
        NSDictionary *raw = [[self templates] objectAtIndex:i];
        unsigned long flags, recurrence, every, unit, weekend, weekday, order, gap, remaining, date, key, destination;
        if (!HBField(raw, @"flags", 0, 4294967295UL, &flags) || !HBField(raw, @"recflg", ((flags & 4) ? 1 : 0) | ((flags & 128) ? 2 : 0), 7, &recurrence)) {
            [issues addObject:@"Indicateurs de recurrence invalides."]; continue;
        }
        if (!(recurrence & 1)) continue;
        if (!HBField(raw, @"account", 0, 4294967295UL, &key) || ![self accountWithKey:[NSString stringWithFormat:@"%lu", key]]) { [issues addObject:@"Compte de planification introuvable."]; continue; }
        NSString *accountKey = [NSString stringWithFormat:@"%lu", key];
        if (!closed && ([[[self accountWithKey:accountKey] objectForKey:@"flags"] intValue] & 2)) continue;
        BOOL valid = HBField(raw, @"every", 1, 255, &every) && every > 0 && HBField(raw, @"unit", 0, 3, &unit)
            && HBField(raw, @"weekend", 0, 3, &weekend) && HBField(raw, @"wkdy", 0, 8, &weekday)
            && HBField(raw, @"ordn", 0, 5, &order) && HBField(raw, @"gap", 0, 3, &gap)
            && HBField(raw, @"nextdate", 0, 3652059, &date) && date > 0 && HBField(raw, @"limit", 0, 65535, &remaining)
            && HBField(raw, @"dst_account", 0, 4294967295UL, &destination);
        NSDecimalNumber *amount = HBMoneyFromText([raw objectForKey:@"amount"] ? [raw objectForKey:@"amount"] : @"0");
        if (!valid || !amount || ((recurrence & 4) && (!weekday || !order))) { [issues addObject:@"Planification invalide ou non prise en charge."]; continue; }
        if ((recurrence & 2) && remaining == 0) continue;
        NSString *destinationKey = [NSString stringWithFormat:@"%lu", destination];
        BOOL transfer = (flags & 8) != 0;
        NSDictionary *target = [self accountWithKey:destinationKey], *source = [self accountWithKey:accountKey];
        if (filter && ![filter isEqualToString:accountKey] && (!transfer || ![filter isEqualToString:destinationKey])) continue;
        NSDecimalNumber *otherAmount = nil;
        if (transfer) {
            if ([[self currencyKeyForAccount:source] isEqualToString:[self currencyKeyForAccount:target]])
                otherAmount = [amount decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]];
            else otherAmount = HBMoneyFromText([raw objectForKey:@"damt"]);
            if (!target || target == source || !otherAmount || [otherAmount compare:[NSDecimalNumber zero]] == NSOrderedSame
                || [otherAmount compare:[NSDecimalNumber zero]] == [amount compare:[NSDecimalNumber zero]]) {
                [issues addObject:@"Virement planifie incomplet : compte ou montant lie invalide."]; otherAmount = nil;
            }
        }
        unsigned int step = 0;
        while ((nextOnly || date <= (unsigned int)end + 2) && (!(recurrence & 2) || step < remaining)) {
            if (++totalSteps > 50000 || step >= 10000) { [issues addObject:@"Trop d'echeances : projection incomplete."]; break; }
            int posted = HBPostDate(date, weekend);
            if (nextOnly || (posted >= start && posted <= end)) {
                NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:raw];
                [entry setObject:accountKey forKey:@"account"]; [entry setObject:amount forKey:@"amount"];
                [entry setObject:[NSString stringWithFormat:@"%d", posted] forKey:@"date"];
                [entry setObject:[NSString stringWithFormat:@"%lu", flags] forKey:@"flags"];
                [entry setObject:@"1" forKey:@"__planned"];
                if (HBVisible(self, accountKey, filter, closed)) [entries addObject:entry];
                if (otherAmount && HBVisible(self, destinationKey, filter, closed)) {
                    entry = [NSMutableDictionary dictionaryWithDictionary:entry];
                    [entry setObject:destinationKey forKey:@"account"]; [entry setObject:otherAmount forKey:@"amount"];
                    [entry setObject:accountKey forKey:@"dst_account"]; [entries addObject:entry];
                }
            }
            if (nextOnly) break;
            int next = HBAdvance(date, unit, every, recurrence, weekday, order, weekend, &gap);
            if (!next || next <= (int)date) { [issues addObject:@"Fin de la plage de dates de la recurrence."]; break; }
            date = next; step++;
        }
        if (totalSteps > 50000) break;
    }
    [entries sortUsingFunction:HBEntryOrder context:NULL]; return entries;
}
- (NSArray *)calendarEntriesFrom:(int)start to:(int)end today:(int)today account:(NSString *)key includeClosed:(BOOL)closed issues:(NSArray **)issuesOut {
    NSMutableArray *issues = [NSMutableArray array], *entries = [NSMutableArray array];
    unsigned int i;
    if (start < 1 || end > 3652059 || start > end || today < 1 || today > 3652059) {
        [issues addObject:@"Plage du calendrier invalide."];
    } else {
        for (i = 0; i < [[self records] count]; i++) {
            NSDictionary *record = [[self records] objectAtIndex:i]; int date = [[record objectForKey:@"date"] intValue];
            if (date >= start && date <= end && [[record objectForKey:@"st"] intValue] != 3 && HBVisible(self, [record objectForKey:@"account"], key, closed)) [entries addObject:record];
        }
        if (end > today) [entries addObjectsFromArray:[self forecastFrom:start > today ? start : today + 1 to:end account:key includeClosed:closed nextOnly:NO issues:issues]];
    }
    [entries sortUsingFunction:HBEntryOrder context:NULL];
    if (issuesOut) *issuesOut = issues; return entries;
}
- (NSArray *)recurringEntriesForAccount:(NSString *)key includeClosed:(BOOL)closed issues:(NSArray **)issuesOut {
    NSMutableArray *issues = [NSMutableArray array];
    NSArray *entries = [self forecastFrom:1 to:3652059 account:key includeClosed:closed nextOnly:YES issues:issues];
    if (issuesOut) *issuesOut = issues; return entries;
}
- (NSArray *)totalsForEntries:(NSArray *)entries {
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    unsigned int i;
    for (i = 0; i < [entries count]; i++) {
        NSDictionary *entry = [entries objectAtIndex:i], *account = [self accountWithKey:[entry objectForKey:@"account"]];
        NSString *currency = [self currencyKeyForAccount:account];
        NSMutableDictionary *group = [groups objectForKey:currency];
        if (!group) {
            group = [NSMutableDictionary dictionaryWithObjectsAndKeys:[account objectForKey:@"key"], @"account", [NSDecimalNumber zero], @"income",
                [NSDecimalNumber zero], @"expenses", [NSDecimalNumber zero], @"transferIn", [NSDecimalNumber zero], @"transferOut", nil];
            [groups setObject:group forKey:currency];
        }
        NSDecimalNumber *amount = [entry objectForKey:@"amount"];
        BOOL positive = [amount compare:[NSDecimalNumber zero]] != NSOrderedAscending;
        NSString *field = HBIsTransfer(entry) ? positive ? @"transferIn" : @"transferOut" : positive ? @"income" : @"expenses";
        NSDecimal left = [[group objectForKey:field] decimalValue], right = [amount decimalValue], sum;
        if (!positive) { NSDecimal zero = [[NSDecimalNumber zero] decimalValue]; NSDecimalSubtract(&right, &zero, &right, NSRoundPlain); }
        if (NSDecimalAdd(&sum, &left, &right, NSRoundPlain) != NSCalculationNoError) [group setObject:@"1" forKey:@"error"];
        else [group setObject:[NSDecimalNumber decimalNumberWithDecimal:sum] forKey:field];
    }
    return [groups allValues];
}
@end
