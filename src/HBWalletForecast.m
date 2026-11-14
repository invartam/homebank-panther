#import "HBWallet.h"
#include <string.h>

/* Approximation is permitted only for the income-detection heuristic, never for a balance. */
static NSDecimalNumber *HFMath(NSDecimalNumber *left, NSDecimalNumber *right, char operation, BOOL ranking) {
    if (!left || !right) return nil;
    NSDecimal a = [left decimalValue], b = [right decimalValue], result;
    NSCalculationError error = operation == '*' ? NSDecimalMultiply(&result, &a, &b, NSRoundPlain) :
        operation == '/' ? NSDecimalDivide(&result, &a, &b, NSRoundPlain) : NSDecimalAdd(&result, &a, &b, NSRoundPlain);
    if (error != NSCalculationNoError && !(ranking && error == NSCalculationLossOfPrecision)) return nil;
    return [NSDecimalNumber decimalNumberWithDecimal:result];
}
static NSDecimalNumber *HFNumber(NSString *text) { return [NSDecimalNumber decimalNumberWithString:text]; }
static NSString *HFText(id text) { return [text isKindOfClass:[NSString class]] ? text : @""; }
static NSString *HFFold(NSString *text) {
    NSString *decomposed = [[HFText(text) lowercaseString] decomposedStringWithCanonicalMapping];
    NSMutableString *folded = [NSMutableString string]; unsigned int i;
    NSCharacterSet *marks = [NSCharacterSet nonBaseCharacterSet];
    for (i = 0; i < [decomposed length]; i++) if (![marks characterIsMember:[decomposed characterAtIndex:i]])
        [folded appendFormat:@"%C", [decomposed characterAtIndex:i]];
    return folded;
}
static BOOL HFWord(const char *word) {
    return !strcmp(word, "salaire") || !strcmp(word, "salaires") || !strcmp(word, "salary") ||
        !strcmp(word, "salaries") || !strcmp(word, "paie") || !strcmp(word, "payroll");
}
static BOOL HFNamed(HBWallet *wallet, NSDictionary *record) {
    NSString *text = HFFold([NSString stringWithFormat:@"%@ %@", HFText([record objectForKey:@"wording"]), [wallet categoryForRecord:record]]);
    char word[16]; unsigned int i, length = 0;
    for (i = 0; i <= [text length]; i++) {
        unichar c = i < [text length] ? [text characterAtIndex:i] : 0;
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_') {
            if (length < sizeof(word) - 1) word[length] = (char)c;
            if (length < sizeof(word)) length++;
        } else {
            if (length < sizeof(word)) { word[length] = 0; if (HFWord(word)) return YES; }
            length = 0;
        }
    }
    return NO;
}
static NSString *HFKey(NSDictionary *record, NSString *field) {
    unsigned long value = 0; HBParseUnsigned([record objectForKey:field], 4294967295UL, &value);
    return [NSString stringWithFormat:@"%lu", value];
}
static unsigned int HFRemaining(NSDictionary *entry) {
    unsigned int flags = [[entry objectForKey:@"flags"] intValue];
    unsigned int recurrence = [entry objectForKey:@"recflg"] ? [[entry objectForKey:@"recflg"] intValue] : ((flags & 4) ? 1 : 0) | ((flags & 128) ? 2 : 0);
    return recurrence & 2 ? [[entry objectForKey:@"limit"] intValue] : 65536;
}
static NSDecimalNumber *HFMonthly(NSDictionary *entry) {
    unsigned int unit = [[entry objectForKey:@"unit"] intValue];
    unsigned int every = [entry objectForKey:@"every"] ? [[entry objectForKey:@"every"] intValue] : 1;
    NSString *days[] = { @"1", @"7", @"30.436875", @"365.2425" };
    NSDecimalNumber *amount = [entry objectForKey:@"amount"];
    if ([amount compare:[NSDecimalNumber zero]] == NSOrderedAscending) amount = HFMath(amount, HFNumber(@"-1"), '*', NO);
    NSDecimalNumber *duration = HFMath(HFNumber(days[MIN(unit, 3)]), [NSDecimalNumber decimalNumberWithMantissa:every exponent:0 isNegative:NO], '*', YES);
    return HFMath(HFMath(amount, HFNumber(@"30.436875"), '*', YES), duration, '/', YES);
}
static BOOL HFRegular(NSDictionary *entry) {
    int unit = [[entry objectForKey:@"unit"] intValue], every = [entry objectForKey:@"every"] ? [[entry objectForKey:@"every"] intValue] : 1;
    return HFRemaining(entry) != 1 && ((unit == 0 && every <= 93) || (unit == 1 && every <= 13) || (unit == 2 && every <= 3));
}

@implementation HBWallet (Forecast)
- (NSDictionary *)futureForecastForAccount:(NSDictionary *)account today:(int)today manual:(BOOL)manual until:(int)until {
    account = [self accountWithKey:[account objectForKey:@"key"]];
    if (!account) return nil;
    NSString *key = [account objectForKey:@"key"];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [[self balancesForAccount:account] objectForKey:@"future"], @"future", @"posted", @"kind",
        [NSNumber numberWithBool:YES], @"available", [NSNumber numberWithBool:NO], @"estimated",
        [NSNumber numberWithInt:0], @"until", [NSNumber numberWithInt:0], @"overdue", @"Operations inscrites", @"label", nil];
    NSMutableArray *issues = [NSMutableArray array];
    if ([[account objectForKey:@"flags"] intValue] & 2) { [result setObject:issues forKey:@"issues"]; return result; }
    int type = [[account objectForKey:@"type"] intValue], nextSalary = 0;
    BOOL estimated = NO;
    NSString *label = nil;
    NSArray *recorded = [self recordsForAccount:account];
    unsigned int i, j;
    if (today < 1 || today > 3652059) [issues addObject:@"Date du jour invalide."];
    if (manual && (until < today || until > 3652059 || until < 1)) [issues addObject:@"Choisir une date valide a partir d'aujourd'hui (jj/mm/aaaa)."];
    if (!manual && type != 3 && type != 7 && ![issues count]) {
        NSArray *parsedIssues = nil;
        NSArray *entries = [self recurringEntriesForAccount:key includeClosed:NO issues:&parsedIssues];
        NSMutableArray *incomes = [NSMutableArray array], *candidates = [NSMutableArray array];
        for (i = 0; i < [entries count]; i++) {
            NSDictionary *entry = [entries objectAtIndex:i];
            if (!HBIsTransfer(entry) && [[entry objectForKey:@"amount"] compare:[NSDecimalNumber zero]] == NSOrderedDescending) {
                [incomes addObject:entry]; if (HFNamed(self, entry)) [candidates addObject:entry];
            }
        }
        if (![candidates count]) {
            NSDecimalNumber *income = [NSDecimalNumber zero], *expenses = [NSDecimalNumber zero], *largest = nil;
            NSDictionary *dominant = nil;
            BOOL reliable = YES;
            for (i = 0; i < [entries count]; i++) {
                NSDictionary *entry = [entries objectAtIndex:i];
                if (HFRemaining(entry) == 1) continue;
                NSDecimalNumber *monthly = HFMonthly(entry);
                if ([[entry objectForKey:@"amount"] compare:[NSDecimalNumber zero]] == NSOrderedAscending) expenses = HFMath(expenses, monthly, '+', YES);
                else if (!HBIsTransfer(entry)) income = HFMath(income, monthly, '+', YES);
                if (!income || !expenses || !monthly) reliable = NO;
            }
            for (i = 0; i < [incomes count]; i++) {
                NSDictionary *entry = [incomes objectAtIndex:i]; NSDecimalNumber *monthly = HFMonthly(entry);
                if (monthly && HFRegular(entry) && (!largest || [monthly compare:largest] == NSOrderedDescending)) { largest = monthly; dominant = entry; }
            }
            NSDecimalNumber *incomeThreshold = HFMath(income, HFNumber(@"0.6"), '*', YES), *expenseThreshold = HFMath(expenses, HFNumber(@"0.5"), '*', YES);
            if (reliable && dominant && incomeThreshold && expenseThreshold && [expenses compare:[NSDecimalNumber zero]] == NSOrderedDescending &&
                [largest compare:incomeThreshold] != NSOrderedAscending && [largest compare:expenseThreshold] != NSOrderedAscending) {
                [candidates addObject:dominant]; estimated = YES;
            }
        }
        NSMutableArray *templates = [NSMutableArray array];
        for (i = 0; i < [candidates count]; i++) {
            unsigned int index = [[[candidates objectAtIndex:i] objectForKey:@"__templateIndex"] unsignedIntValue];
            if (index < [[self templates] count]) [templates addObject:[[self templates] objectAtIndex:index]];
        }
        if ([templates count]) {
            NSArray *salaryIssues = nil;
            NSArray *upcoming = [self plannedEntriesFrom:today to:MIN(3652059, today + 366) account:key templates:templates issues:&salaryIssues overdue:NULL];
            if ([upcoming count]) {
                NSDictionary *entry = [upcoming objectAtIndex:0]; nextSalary = [[entry objectForKey:@"date"] intValue];
                label = [HFText([entry objectForKey:@"wording"]) length] ? [entry objectForKey:@"wording"] : estimated ? @"Revenu recurrent" : @"Salaire";
            }
            [issues addObjectsFromArray:salaryIssues];
        }
        /* A future salary already posted by HomeBank still bounds the automatic budget. */
        for (i = 0; i < [recorded count]; i++) {
            NSDictionary *record = [recorded objectAtIndex:i]; int date = [[record objectForKey:@"date"] intValue];
            if (date <= today || [[record objectForKey:@"st"] intValue] == 3 || HBIsTransfer(record) || [[record objectForKey:@"amount"] compare:[NSDecimalNumber zero]] != NSOrderedDescending) continue;
            BOOL named = HFNamed(self, record), matched = NO;
            NSDictionary *match = nil;
            for (j = 0; j < [candidates count]; j++) {
                NSDictionary *candidate = [candidates objectAtIndex:j];
                BOOL payer = ![HFKey(candidate, @"payee") isEqualToString:@"0"] && [HFKey(candidate, @"payee") isEqualToString:HFKey(record, @"payee")];
                BOOL memo = [HFText([candidate objectForKey:@"wording"]) length] && [HFFold([candidate objectForKey:@"wording"]) isEqualToString:HFFold([record objectForKey:@"wording"])];
                if ([HFKey(candidate, @"category") isEqualToString:HFKey(record, @"category")] && (payer || memo)) { matched = YES; match = candidate; break; }
            }
            if ((named || matched) && (!nextSalary || date <= nextSalary)) {
                nextSalary = date;
                label = [HFText([record objectForKey:@"wording"]) length] ? [record objectForKey:@"wording"] : [HFText([match objectForKey:@"wording"]) length] ? [match objectForKey:@"wording"] : @"Salaire";
                if (named) estimated = NO;
            }
        }
        if (nextSalary) [issues addObjectsFromArray:parsedIssues];
    }
    if (manual || nextSalary || [issues count]) {
        int boundary = manual ? (until >= 1 && until <= 3652059 ? until + 1 : 0) : nextSalary;
        NSString *kind = manual ? @"manual" : nextSalary ? @"salary" : @"unavailable";
        [result setObject:kind forKey:@"kind"]; [result setObject:[NSNumber numberWithInt:manual ? until : nextSalary] forKey:@"until"];
        [result setObject:manual ? @"Date choisie" : label ? label : @"Prevision indisponible" forKey:@"label"];
        [result setObject:[NSNumber numberWithBool:!manual && estimated] forKey:@"estimated"];
        if (![issues count]) {
            unsigned int overdue = 0; NSArray *projectionIssues = nil;
            NSArray *projected = boundary > today ? [self plannedEntriesFrom:today to:boundary - 1 account:key templates:nil issues:&projectionIssues overdue:&overdue] : [NSArray array];
            if (projectionIssues) [issues addObjectsFromArray:projectionIssues];
            [result setObject:[NSNumber numberWithUnsignedInt:overdue] forKey:@"overdue"];
            NSDecimalNumber *total = [account objectForKey:@"initial"];
            for (i = 0; i < [recorded count] && total; i++) {
                NSDictionary *record = [recorded objectAtIndex:i];
                if ([[record objectForKey:@"st"] intValue] != 3 && [[record objectForKey:@"date"] intValue] < boundary) total = HFMath(total, [record objectForKey:@"amount"], '+', NO);
            }
            for (i = 0; i < [projected count] && total; i++) total = HFMath(total, [[projected objectAtIndex:i] objectForKey:@"amount"], '+', NO);
            if (!total) [issues addObject:@"Solde hors limites de precision."];
            if (![issues count]) [result setObject:total forKey:@"future"];
        }
    }
    [result setObject:[NSNumber numberWithBool:[issues count] == 0] forKey:@"available"];
    [result setObject:issues forKey:@"issues"]; return result;
}
@end
