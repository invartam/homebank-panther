#import "HBWallet.h"
#import "PantherString.h"
#include <stdio.h>

static int failures = 0, checks = 0;
void HBCheck(BOOL condition, const char *message) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message); }
}
#define check HBCheck
void HBEditingTests(HBWallet *wallet);
void HBCalendarTests(HBWallet *wallet);
static HBWallet *parse(NSString *text, NSString **error) {
    return [[[HBWallet alloc] initWithData:[text dataUsingEncoding:NSUTF8StringEncoding] error:error] autorelease];
}
static void rejects(NSString *text) {
    NSString *error = nil;
    HBWallet *wallet = parse(text, &error);
    check(wallet == nil && [error length] > 0, "reject malformed or unsupported file with safe message");
}

int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *error = nil;
    NSString *path = argc == 2 ? [NSString stringWithUTF8String:argv[1]] : @"tests/demo.xhb";
    NSData *before = [NSData dataWithContentsOfFile:path];
    HBWallet *wallet = [HBWallet walletAtPath:path error:&error];
    NSDictionary *account = [[wallet accounts] count] ? [[wallet accounts] objectAtIndex:0] : nil;
    NSDictionary *balance = [wallet balancesForAccount:account];
    check(wallet != nil && error == nil, "loads original GLib version 1.6000000000000001");
    check([[wallet accounts] count] == 4, "loads accounts without silently discarding closed account history");
    check([[balance objectForKey:@"reconciled"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"80"]], "reconciled balance");
    check([[balance objectForKey:@"cleared"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"70"]], "cleared includes reconciled");
    check([[balance objectForKey:@"future"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"40"]], "future includes posted transfer and excludes void and templates");
    check([[wallet recordsForAccount:account] count] == 5, "records include void and future posted operations");
    check([[wallet recordsForAccount:nil] count] == 0 && [wallet balancesForAccount:nil] == nil, "empty account selection is safe");
    check([[HBDateFromOrdinal(739890) descriptionWithCalendarFormat:@"%d/%m/%Y"] isEqualToString:@"01/10/2026"], "French dates");
    check([[HBDateFromOrdinal(744730) descriptionWithCalendarFormat:@"%d/%m/%Y"] isEqualToString:@"01/01/2040"], "dates do not depend on 32-bit Unix time");
    check([[HBDateFromOrdinal(730544) descriptionWithCalendarFormat:@"%d/%m/%Y"] isEqualToString:@"28/02/2001"], "calendar conversion at month boundary");
    if (wallet) {
        NSDictionary *record = [[wallet recordsForAccount:account] lastObject];
        check([[wallet payeeForRecord:record] isEqualToString:@"Supermarche"], "payee is distinct from memo and number");
        check([[wallet categoryForRecord:record] isEqualToString:@"Maison:Courses"], "hierarchical category");
        check([[record objectForKey:@"info"] isEqualToString:@"123"] && [[record objectForKey:@"wording"] isEqualToString:@"Courses"], "payment number is distinct from memo");
        check([[wallet formatAmount:[balance objectForKey:@"reconciled"] account:account] isEqualToString:@"80,00 EUR"], "French money with account currency");
        check([[wallet formatAmount:[NSDecimalNumber decimalNumberWithString:@"-2.25"] account:account] isEqualToString:@"-2,25 EUR"], "negative money");
        check([[wallet formatAmount:[NSDecimalNumber zero] account:account] isEqualToString:@"0,00 EUR"], "zero money is numeric, not a formatter pattern");
        NSDictionary *dollars = [[wallet accounts] objectAtIndex:3];
        check([[wallet formatAmount:[NSDecimalNumber decimalNumberWithString:@"10"] account:dollars] isEqualToString:@"10,00 USD"], "does not mix currencies");
    }
    check([before isEqualToData:[NSData dataWithContentsOfFile:path]], "never modifies imported file");
    NSString *largeID = [[[HBPString alloc] initWithValue:@"4294967295"] autorelease];
    @try {
        check(HBIsTransfer([NSDictionary dictionaryWithObject:largeID forKey:@"kxfer"]), "transfer IDs use the unsigned parser, not NSString doubleValue");
        check(HBIsTransfer([NSDictionary dictionaryWithObject:largeID forKey:@"dst_account"]), "destination IDs retain 32-bit unsigned precision on Panther");
    } @catch (NSException *exception) { check(NO, "transfer detection used an unsupported Panther selector"); }
    HBWallet *decimal = parse(@"<homebank v='1.6'><account key='1' initial='0.1'/><ope account='1' date='730486' amount='0.2' st='2'/></homebank>", &error);
    check([[[decimal balancesForAccount:[[decimal accounts] objectAtIndex:0]] objectForKey:@"future"]
        isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"0.3"]], "exact decimal arithmetic");
    HBWallet *empty = parse(@"<homebank/>", &error);
    check(empty != nil && [[empty accounts] count] == 0, "empty wallet");
    HBWallet *padded = parse(@"<homebank v='1.6'><cur key='0001' frac='02' iso='EUR'/><account key='0001' curr='01'/><ope account='01' date='0730486' amount='1' st='02'/></homebank>", &error);
    check(padded && [[[[padded accounts] objectAtIndex:0] objectForKey:@"key"] isEqualToString:@"1"] &&
        [[[[padded records] objectAtIndex:0] objectForKey:@"st"] isEqualToString:@"2"], "integer fast path still canonicalizes padded identifiers and statuses");
    HBWallet *formats = parse(@"<homebank v='1.6'><cur key='1' frac='2' iso='EUR'/><cur key='2' frac='0' iso='JPY'/><cur key='3' frac='3' iso='KWD'/><account key='1' curr='1'/><account key='2' curr='2'/><account key='3' curr='3'/></homebank>", &error);
    check([[formats formatAmount:[NSDecimalNumber decimalNumberWithString:@"1000"] account:[formats accountWithKey:@"2"]] isEqualToString:@"1 000 JPY"], "cached formatter preserves zero-fraction currency");
    check([[formats formatAmount:[NSDecimalNumber decimalNumberWithString:@"-1.234"] account:[formats accountWithKey:@"3"]] isEqualToString:@"-1,234 KWD"], "cached formatter preserves three-fraction currency");
    check([[formats formatAmount:[NSDecimalNumber decimalNumberWithString:@"1000.5"] account:[formats accountWithKey:@"1"]] isEqualToString:@"1 000,50 EUR"] &&
        [[formats formatAmount:[NSDecimalNumber zero] account:[formats accountWithKey:@"3"]] isEqualToString:@"0,000 KWD"], "formatter reuse does not leak precision or currency between accounts");
    rejects(@"<homebank v='1.7'/>"); rejects(@"<homebank v='NaN'/>"); rejects(@"<homebank v='0'/>");
    rejects(@"<homebank v='-1'/>"); rejects(@"<not-homebank/>"); rejects(@"<homebank>");
    rejects(@"<!DOCTYPE homebank [<!ENTITY steal SYSTEM 'file:///etc/passwd'>]><homebank/>");
    rejects(@"<homebank><account key='1' initial='NaN'/></homebank>");
    rejects(@"<homebank><account key='1' initial='(null)'/></homebank>");
    rejects(@"<homebank><account key='1' initial='1e127'/><ope account='1' date='730486' amount='0.01'/></homebank>");
    rejects(@"<homebank><account key='1'/><account key='1'/></homebank>");
    rejects(@"<homebank><ope account='9' date='730486' amount='1'/></homebank>");
    rejects(@"<homebank><account key='1'/><ope account='1' date='730486' amount='1' st='4'/></homebank>");
    rejects(@"<homebank><account key='1'/><ope account='1' date='0' amount='1'/></homebank>");
    rejects(@"<homebank><account key='4294967296'/></homebank>");
    rejects(@"<homebank><cur key='1' frac='21'/></homebank>");
    NSMutableData *large = [NSMutableData dataWithLength:HB_MAX_FILE_BYTES + 1];
    check([[[HBWallet alloc] initWithData:large error:&error] autorelease] == nil, "bounded import");
    HBEditingTests(wallet);
    HBCalendarTests(wallet);
    printf("%d/%d checks passed\n", checks - failures, checks);
    [pool release]; return failures ? 1 : 0;
}
