#import "HBBalanceHistory.h"
#include <stdlib.h>
#include <math.h>

static BOOL HHSum(NSDecimalNumber *left, NSDecimalNumber *right, NSDecimalNumber **out) {
    NSDecimal a = [left decimalValue], b = [right decimalValue], result;
    if (NSDecimalAdd(&result, &a, &b, NSRoundPlain) != NSCalculationNoError) return NO;
    *out = [NSDecimalNumber decimalNumberWithDecimal:result]; return YES;
}
static int HHMonthShift(int ordinal, int months) {
    NSCalendarDate *date = HBDateFromOrdinal(ordinal);
    int total = [date yearOfCommonEra] * 12 + [date monthOfYear] - 1 + months;
    if (total < 12) return 1;
    if (total >= 120000) return 3652059;
    int year = total / 12, month = total % 12 + 1;
    NSCalendarDate *next = [NSCalendarDate dateWithYear:year + (month == 12) month:month == 12 ? 1 : month + 1 day:1
        hour:12 minute:0 second:0 timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    int days = [[next dateByAddingYears:0 months:0 days:-1 hours:0 minutes:0 seconds:0] dayOfMonth];
    NSCalendarDate *result = [NSCalendarDate dateWithYear:year month:month day:MIN([date dayOfMonth], days)
        hour:12 minute:0 second:0 timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    return HBOrdinalFromDate(result);
}
static int HHPointOrder(const void *a, const void *b) {
    int left = ((const HBBalancePoint *)a)->date, right = ((const HBBalancePoint *)b)->date;
    return left < right ? -1 : left > right ? 1 : 0;
}

@implementation HBBalanceHistory
+ (NSArray *)accountsForWallet:(HBWallet *)wallet scope:(NSString *)scope currency:(NSString *)currency {
    NSMutableArray *accounts = [NSMutableArray array]; unsigned int i;
    for (i = 0; i < [[wallet accounts] count]; i++) {
        NSDictionary *account = [[wallet accounts] objectAtIndex:i];
        if ([[account objectForKey:@"flags"] intValue] & 2) continue;
        int type = [[account objectForKey:@"type"] intValue]; BOOL savings = type == 3 || type == 7;
        BOOL match = [scope isEqualToString:@"bank"] ? !savings : [scope isEqualToString:@"savings"] ? savings :
            [scope hasPrefix:@"account:"] && [[account objectForKey:@"key"] isEqualToString:[scope substringFromIndex:8]];
        if (match && (!currency || [[wallet currencyKeyForAccount:account] isEqualToString:currency])) [accounts addObject:account];
    }
    return accounts;
}
- (id)initWithWallet:(HBWallet *)wallet accounts:(NSArray *)accounts today:(int)today months:(int)months error:(NSString **)error {
    self = [super init]; if (!self) return nil;
    if (error) *error = nil;
    NSString *failure = nil, *currency = nil;
    NSMutableSet *keys = [NSMutableSet set]; NSMutableArray *active = [NSMutableArray array];
    NSDecimalNumber *initial = [NSDecimalNumber zero]; unsigned int i;
    if (today < 1 || today > 3652059 || (months != 3 && months != 12 && months != 60)) failure = @"Plage de projection invalide.";
    for (i = 0; !failure && i < [accounts count]; i++) {
        NSDictionary *account = [accounts objectAtIndex:i]; NSString *key = [account objectForKey:@"key"];
        if ([[account objectForKey:@"flags"] intValue] & 2) continue;
        if (![wallet accountWithKey:key] || [keys containsObject:key]) { failure = @"Perimetre de comptes invalide."; break; }
        NSString *nextCurrency = [wallet currencyKeyForAccount:account];
        if (currency && ![currency isEqualToString:nextCurrency]) { failure = @"Les devises doivent etre affichees separement."; break; }
        currency = nextCurrency;
        if (!HHSum(initial, [account objectForKey:@"initial"], &initial)) { failure = @"Solde initial hors limites."; break; }
        [active addObject:account]; [keys addObject:key];
    }
    if (!failure && ![active count]) failure = @"Aucun compte ouvert dans ce perimetre.";
    if (failure) { if (error) *error = failure; [self release]; return nil; }
    _today = today; _end = HHMonthShift(today, months);
    NSArray *issues = nil;
    NSArray *entries = [wallet calendarEntriesFrom:1 to:_end today:today account:[active count] == 1 ? [[active objectAtIndex:0] objectForKey:@"key"] : nil includeClosed:NO issues:&issues];
    NSMutableDictionary *daily = [NSMutableDictionary dictionary];
    int first = today; BOOL hasRecorded = NO;
    for (i = 0; i < [entries count]; i++) {
        NSDictionary *entry = [entries objectAtIndex:i];
        if (![keys containsObject:[entry objectForKey:@"account"]]) continue;
        int date = [[entry objectForKey:@"date"] intValue];
        if (![entry objectForKey:@"__planned"]) { first = MIN(first, date); hasRecorded = YES; }
        NSNumber *day = [NSNumber numberWithInt:date]; NSDecimalNumber *sum;
        if (!HHSum([daily objectForKey:day] ? [daily objectForKey:day] : [NSDecimalNumber zero], [entry objectForKey:@"amount"], &sum)) {
            failure = @"Total quotidien hors limites."; break;
        }
        [daily setObject:sum forKey:day];
    }
    _start = MAX(1, hasRecorded ? first - 1 : today - 365); _start = MIN(_start, 3652058);
    _end = MAX(_end, _start + 1);
    NSArray *dates = [[daily allKeys] sortedArrayUsingSelector:@selector(compare:)];
    _points = calloc([dates count] + 2, sizeof(HBBalancePoint));
    if (!_points) failure = @"Memoire insuffisante pour le graphique.";
    NSMutableArray *balances = [NSMutableArray array]; NSDecimalNumber *balance = initial;
    if (!failure) {
        _points[0].date = _start; _points[0].balance = [balance doubleValue]; _count = 1; [balances addObject:balance];
        for (i = 0; i < [dates count]; i++) {
            NSNumber *day = [dates objectAtIndex:i];
            if (!HHSum(balance, [daily objectForKey:day], &balance)) { failure = @"Solde hors limites."; break; }
            unsigned int slot = _points[_count - 1].date == [day intValue] ? _count - 1 : _count++;
            _points[slot].date = [day intValue]; _points[slot].balance = [balance doubleValue];
            if (slot < [balances count]) [balances replaceObjectAtIndex:slot withObject:balance]; else [balances addObject:balance];
        }
        if (_points[_count - 1].date != _end) {
            _points[_count].date = _end; _points[_count++].balance = [balance doubleValue]; [balances addObject:balance];
        }
    }
    if (failure) { if (error) *error = failure; [self release]; return nil; }
    _balances = [balances copy]; _accounts = [active copy]; _issues = [issues copy]; return self;
}
- (int)start { return _start; }
- (int)end { return _end; }
- (int)today { return _today; }
- (NSArray *)accounts { return _accounts; }
- (NSArray *)issues { return _issues; }
- (unsigned int)indexAt:(int)date {
    unsigned int low = 0, high = _count;
    while (low < high) { unsigned int mid = low + (high - low) / 2; if (_points[mid].date <= date) low = mid + 1; else high = mid; }
    return low ? low - 1 : 0;
}
- (NSDecimalNumber *)balanceAt:(int)date { return [_balances objectAtIndex:[self indexAt:date]]; }
- (HBBalancePoint *)copyPointsFrom:(int)start to:(int)end limit:(unsigned int)limit count:(unsigned int *)count {
    HBHistoryRange range = {start, end}; range = HBHistoryClamp(range, self);
    limit = MAX(16, MIN(2400, limit)); unsigned int buckets = (limit - 3) / 3;
    HBBalancePoint *samples = calloc(limit, sizeof(HBBalancePoint));
    if (count) *count = 0; if (!samples) return NULL;
    unsigned int n = 0, i, cursor = [self indexAt:range.start] + 1;
    samples[n].date = range.start; samples[n++].balance = _points[cursor - 1].balance;
    /* Preserve the min/max/last balance of each pixel bucket, not only its average. */
    for (i = 0; i < buckets; i++) {
        int stop = range.start + (int)(((double)(i + 1) * (range.end - range.start)) / buckets);
        unsigned int firstIndex = cursor, minIndex = cursor, maxIndex = cursor;
        while (cursor < _count && _points[cursor].date <= stop && _points[cursor].date <= range.end) {
            if (_points[cursor].balance < _points[minIndex].balance) minIndex = cursor;
            if (_points[cursor].balance > _points[maxIndex].balance) maxIndex = cursor;
            cursor++;
        }
        if (cursor > firstIndex) { samples[n++] = _points[minIndex]; samples[n++] = _points[maxIndex]; samples[n++] = _points[cursor - 1]; }
    }
    samples[n].date = range.end; samples[n++].balance = _points[[self indexAt:range.end]].balance;
    if (_today > range.start && _today < range.end) { samples[n].date = _today; samples[n++].balance = _points[[self indexAt:_today]].balance; }
    qsort(samples, n, sizeof(HBBalancePoint), HHPointOrder);
    unsigned int used = 0;
    for (i = 0; i < n; i++) if (!used || samples[i].date != samples[used - 1].date) samples[used++] = samples[i];
    if (count) *count = used; return samples;
}
- (void)dealloc { free(_points); [_balances release]; [_accounts release]; [_issues release]; [super dealloc]; }
@end

HBHistoryRange HBHistoryClamp(HBHistoryRange range, HBBalanceHistory *history) {
    int width = MIN([history end] - [history start], MAX(1, range.end - range.start));
    range.start = MAX([history start], MIN(range.start, [history end] - width)); range.end = range.start + width; return range;
}
HBHistoryRange HBHistoryPreset(HBBalanceHistory *history, unsigned int preset) {
    HBHistoryRange range = {[history start], [history end]};
    if (preset == 4) return range;
    if (preset == 5) { range.start = [history today]; return HBHistoryClamp(range, history); }
    int months[] = {-1, -3, -12, -60}; range.end = [history today];
    range.start = MAX([history start], HHMonthShift(range.end, months[MIN(preset, 3)])); return HBHistoryClamp(range, history);
}
HBHistoryRange HBHistoryZoom(HBHistoryRange range, HBBalanceHistory *history, double factor) {
    int width = MAX(1, MIN([history end] - [history start], (int)floor((range.end - range.start) * factor + 0.5)));
    range.start = (range.start + range.end - width) / 2; range.end = range.start + width; return HBHistoryClamp(range, history);
}
NSDecimalNumber *HBHistoryOverdraft(NSDictionary *account) {
    NSDecimalNumber *minimum = [account objectForKey:@"minimum"];
    if (!minimum) return [NSDecimalNumber zero];
    return [minimum compare:[NSDecimalNumber zero]] == NSOrderedDescending ?
        [minimum decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]] : minimum;
}
