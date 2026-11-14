#import "HBWalletStore.h"
#import "PantherString.h"
#include <limits.h>
#include <stdio.h>

void HBCheck(BOOL condition, const char *message);
static NSString *FFReplace(NSString *text, NSString *before, NSString *after) {
    return [[text componentsSeparatedByString:before] componentsJoinedByString:after];
}
static HBWallet *FFWalletWithInitial(NSString *content, NSString *initial) {
    NSString *error = nil;
    NSString *xml = [NSString stringWithFormat:@"<homebank v='1.6'><properties curr='1'/><cur key='1' iso='EUR'/><cur key='2' iso='USD'/>"
        "<account key='1' name='Courant fictif' initial='%@' curr='1'/><account key='2' name='Epargne fictive' type='7' curr='1' initial='100'/>"
        "<account key='3' name='Dollars fictifs' curr='2' initial='200'/><account key='4' name='Clos fictif' flags='2' initial='50'/>"
        "<cat key='1' name='Revenus'/><cat key='2' parent='1' name='Salaires'/>%@</homebank>", initial, content];
    HBWallet *wallet = [[[HBWallet alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error] autorelease];
    if (!wallet || error) fprintf(stderr, "forecast fixture rejected: %s\n", error ? [error UTF8String] : "unknown import error");
    HBCheck(wallet != nil && !error, "forecast fixture imports"); return wallet;
}
static HBWallet *FFWallet(NSString *content) { return FFWalletWithInitial(content, @"1000"); }
static NSString *FFSalary(int date, NSString *attributes) {
    return [NSString stringWithFormat:@"<fav key='1' account='1' amount='2000' recflg='1' unit='2' nextdate='%d' wording='Salaire' %@/>", date, attributes];
}
static NSString *FFExpense(int date, NSString *attributes) {
    return [NSString stringWithFormat:@"<fav key='2' account='1' amount='-100' recflg='1' unit='2' nextdate='%d' %@/>", date, attributes];
}
static NSString *FFPosted(int date, NSString *amount, NSString *attributes) {
    return [NSString stringWithFormat:@"<ope account='1' date='%d' amount='%@' %@/>", date, amount, attributes];
}
static NSDictionary *FFForecast(HBWallet *wallet, int today, BOOL manual, int until) {
    return [wallet futureForecastForAccount:[wallet accountWithKey:@"1"] today:today manual:manual until:until];
}
static BOOL FFAmount(NSDictionary *result, NSString *expected) {
    return [[result objectForKey:@"available"] boolValue] && [[result objectForKey:@"future"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:expected]];
}

void HBForecastTests(void) {
    int today = HBOrdinalFromFrenchDate(@"13/11/2026"), payday = today + 20;
    HBWallet *wallet = FFWallet([NSString stringWithFormat:@"%@%@%@%@%@%@%@%@", FFSalary(payday, @""), FFExpense(today + 2, @""),
        FFPosted(today - 1, @"-10", @"st='2'"), FFPosted(today + 1, @"-50", @"st='1'"), FFPosted(payday, @"2000", @"wording='Salaire'"),
        FFPosted(payday, @"-200", @""), FFPosted(payday + 1, @"-300", @""), FFPosted(today + 1, @"9999", @"st='3'")]);
    NSData *source = [wallet baseSourceData]; NSDictionary *balances = [wallet balancesForAccount:[wallet accountWithKey:@"1"]];
    NSDictionary *result = FFForecast(wallet, today, NO, 0);
    HBCheck(FFAmount(result, @"840") && [[result objectForKey:@"kind"] isEqualToString:@"salary"] && [[result objectForKey:@"until"] intValue] == payday, "salary budget includes recorded and recurring charges strictly before salary day");
    HBCheck([balances isEqual:[wallet balancesForAccount:[wallet accountWithKey:@"1"]]] && [source isEqualToData:[wallet baseSourceData]] && [wallet generation] == 0, "display forecasts preserve accounting balances, source and journal");
    HBCheck([[balances objectForKey:@"reconciled"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"990"]] && [[balances objectForKey:@"cleared"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"940"]], "reconciled and cleared balances remain exact");

    NSString *categorized = FFReplace(FFSalary(payday, @"category='0002'"), @"wording='Salaire'", @"wording='Employeur fictif'");
    wallet = FFWallet([categorized stringByAppendingString:FFExpense(today + 2, @"")]);
    result = FFForecast(wallet, today, NO, 0);
    HBCheck(FFAmount(result, @"900") && ![[result objectForKey:@"estimated"] boolValue], "salary detection reads hierarchical categories with canonical IDs");
    NSString *employer = FFReplace(FFSalary(payday, @""), @"wording='Salaire'", @"wording='Employeur fictif'");
    wallet = FFWallet([employer stringByAppendingString:FFExpense(today + 2, @"")]);
    result = FFForecast(wallet, today, NO, 0);
    HBCheck(FFAmount(result, @"900") && [[result objectForKey:@"estimated"] boolValue], "dominant recurring income is identified as an estimate");
    HBCheck(FFAmount(FFForecast(wallet, today, YES, payday), @"2900") && ![[FFForecast(wallet, today, YES, payday) objectForKey:@"estimated"] boolValue], "manual salary horizon includes salary day and removes the estimate marker");
    HBCheck([result isEqual:FFForecast(wallet, today, NO, payday)], "disabling manual mode restores the complete automatic result");
    wallet = FFWallet([FFReplace(employer, @"amount='2000'", @"amount='5'") stringByAppendingString:FFExpense(today + 2, @"")]);
    HBCheck([[FFForecast(wallet, today, NO, 0) objectForKey:@"kind"] isEqualToString:@"posted"], "small recurring income is not automatically called salary");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@", employer, employer, FFExpense(today + 2, @"")]);
    HBCheck([[FFForecast(wallet, today, NO, 0) objectForKey:@"kind"] isEqualToString:@"posted"], "ambiguous equal recurring incomes are not classified as salary");

    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@", FFSalary(payday, @""), FFExpense(today + 2, @""),
        [NSString stringWithFormat:@"<fav account='1' amount='50' recflg='3' limit='1' unit='2' nextdate='%d'/>", today + 1]]);
    HBCheck(FFAmount(FFForecast(wallet, today, NO, 0), @"950"), "other recurring income before salary contributes to the budget");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@", FFSalary(payday, @""), FFSalary(today + 10, @""), FFExpense(today + 2, @"")]);
    HBCheck([[FFForecast(wallet, today, NO, 0) objectForKey:@"until"] intValue] == today + 10, "earliest of several salaries defines the horizon");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@", FFSalary(today + 1, @"weekend='1'"), FFPosted(today, @"-500", @"")]);
    HBCheck(FFAmount(FFForecast(wallet, today, NO, 0), @"1000") && [[FFForecast(wallet, today, NO, 0) objectForKey:@"until"] intValue] == today, "Friday-before weekend salary excludes the entire effective salary day");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@", FFSalary(payday, @""), FFExpense(today, @""), FFExpense(today - 3, @"")]);
    result = FFForecast(wallet, today, NO, 0);
    HBCheck(FFAmount(result, @"900") && [[result objectForKey:@"overdue"] intValue] == 1, "today is projected and overdue occurrences are excluded and reported");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@", FFReplace(FFSalary(payday, @""), @"recflg='1'", @"recflg='3' limit='1'"), FFExpense(today + 2, @""), FFPosted(today, @"2000", @"wording='Salaire'")]);
    HBCheck(FFAmount(FFForecast(wallet, today, NO, 0), @"2900"), "salary already credited today stays in the current budget before the final upcoming salary");

    int nextPayday = payday + 31;
    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@%@", FFSalary(nextPayday, @""),
        FFReplace(FFExpense(today + 2, @""), @"recflg='1'", @"recflg='3' limit='1'"),
        FFPosted(payday, @"2000", @"category='2'"), FFPosted(nextPayday + 1, @"-70", @"")]);
    HBCheck(FFAmount(FFForecast(wallet, today, NO, 0), @"900") && [[FFForecast(wallet, today, NO, 0) objectForKey:@"until"] intValue] == payday, "posted future salary bounds the budget after HomeBank advances nextdate");
    HBCheck(FFAmount(FFForecast(wallet, today, YES, payday), @"2900") && FFAmount(FFForecast(wallet, today, YES, nextPayday), @"4900"), "chosen date counts the posted salary once and includes later salary occurrences through its final day");
    NSString *spentSalary = FFReplace(FFSalary(payday, @""), @"recflg='1'", @"recflg='3' limit='0'");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@", spentSalary, FFPosted(payday, @"2100", @"wording='SALAIRE'"), FFExpense(today + 2, @"")]);
    HBCheck(FFAmount(FFForecast(wallet, today, NO, 0), @"900"), "explicit future salary is detected even after its recurring template is exhausted");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@", FFReplace(employer, [NSString stringWithFormat:@"nextdate='%d'", payday], [NSString stringWithFormat:@"nextdate='%d'", nextPayday]),
        FFPosted(payday, @"2100", @"wording='Employeur fictif'"), FFExpense(today + 2, @"")]);
    HBCheck([[FFForecast(wallet, today, NO, 0) objectForKey:@"until"] intValue] == payday, "anticipated variable salary matches its recurring memo without requiring equal amounts");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@", FFPosted(payday, @"2000", @"wording='Salaire' st='3'"), FFPosted(payday, @"500", @"wording='Salaire' paymode='5'")]);
    HBCheck([[FFForecast(wallet, today, NO, 0) objectForKey:@"kind"] isEqualToString:@"posted"], "cancelled credits and transfers named salary do not bound the budget");

    wallet = FFWallet([NSString stringWithFormat:@"%@%@<fav account='2' dst_account='1' amount='-20' recflg='1' flags='8' unit='2' nextdate='%d'/>", FFSalary(payday, @""), FFExpense(today + 1, @"dst_account='2' paymode='5'"), today + 2]);
    HBCheck(FFAmount(FFForecast(wallet, today, NO, 0), @"920"), "legacy planned transfers and their incoming legs contribute exactly once");
    HBCheck(FFAmount([wallet futureForecastForAccount:[wallet accountWithKey:@"2"] today:today manual:YES until:today + 3], @"180"), "savings supports a manual horizon including both transfer directions");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@<fav account='3' dst_account='1' amount='-30' damt='25' recflg='1' flags='8' unit='2' nextdate='%d'/>", FFSalary(payday, @""), FFExpense(today + 1, @""), today + 2]);
    HBCheck(FFAmount(FFForecast(wallet, today, NO, 0), @"925") && FFAmount([wallet futureForecastForAccount:[wallet accountWithKey:@"3"] today:today manual:YES until:today + 2], @"170"), "cross-currency forecasts use their own amounts and never add EUR to USD");
    wallet = FFWallet([FFSalary(payday, @"dst_account='2' paymode='5'") stringByAppendingString:FFExpense(today + 1, @"")]);
    HBCheck([[FFForecast(wallet, today, NO, 0) objectForKey:@"kind"] isEqualToString:@"posted"], "legacy positive transfers are excluded from salary detection");

    wallet = FFWallet([FFSalary(payday, @"") stringByAppendingString:FFExpense(today + 1, @"every='0'")]);
    HBCheck(![[FFForecast(wallet, today, NO, 0) objectForKey:@"available"] boolValue], "invalid recurrences never display a partial forecast as reliable");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@", FFSalary(payday, @""),
        FFReplace(FFExpense(today + 1, @""), @"amount='-100'", @"amount='-0.1'"), FFPosted(today, @"-1000.2", @"")]);
    HBCheck(FFAmount(FFForecast(wallet, today, NO, 0), @"-0.3"), "forecast arithmetic is decimal and exact");
    wallet = FFWalletWithInitial([NSString stringWithFormat:@"%@%@", FFSalary(payday, @""),
        FFReplace(FFExpense(today + 1, @""), @"amount='-100'", @"amount='-0.01'")], @"1e37");
    HBCheck(![[FFForecast(wallet, today, NO, 0) objectForKey:@"available"] boolValue], "unrepresentable minor units report unavailable rather than rounding the balance");
    wallet = FFWallet([NSString stringWithFormat:@"%@%@%@", FFExpense(today + 5, @""), FFPosted(today + 5, @"-50", @""), FFPosted(today + 6, @"-90", @"")]);
    HBCheck(FFAmount(FFForecast(wallet, today, NO, 0), @"860") && FFAmount(FFForecast(wallet, today, YES, today + 5), @"850"), "without salary, recorded balance remains the default and chosen date includes planned and posted entries");
    HBCheck(![[FFForecast(wallet, today, YES, today - 1) objectForKey:@"available"] boolValue] && ![[FFForecast(wallet, today, YES, INT_MAX) objectForKey:@"available"] boolValue], "past and overflowing manual dates are rejected");
    HBCheck(FFAmount([wallet futureForecastForAccount:[wallet accountWithKey:@"4"] today:today manual:YES until:payday], @"50"), "closed accounts keep their accounting balance");
    HBCheck([wallet futureForecastForAccount:nil today:today manual:NO until:0] == nil, "missing selected account is safe");
}
