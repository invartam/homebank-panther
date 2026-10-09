#import "HBWallet.h"
#include "HBXML.h"
#include <unistd.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>

extern void HBCheck(BOOL condition, const char *message);
static HBWallet *ETParse(NSString *text) { return [[[HBWallet alloc] initWithData:[text dataUsingEncoding:NSUTF8StringEncoding] error:NULL] autorelease]; }
static NSString *ETRootProperty(HBWallet *wallet, const char *name, const char *uri) {
    NSData *data = [wallet sourceData]; xmlDocPtr doc = HBXMLDocument([data bytes], [data length]);
    if (!doc) return nil;
    xmlChar *value = uri ? xmlGetNsProp(xmlDocGetRootElement(doc), BAD_CAST name, BAD_CAST uri) : xmlGetProp(xmlDocGetRootElement(doc), BAD_CAST name);
    NSString *text = value ? [NSString stringWithUTF8String:(const char *)value] : nil;
    if (value) xmlFree(value); xmlFreeDoc(doc); return text;
}
static BOOL ETOriginalHeader(HBWallet *wallet) {
    NSData *data = [wallet sourceData]; const char *bytes = [data bytes];
    unsigned long length = [data length] < 50 ? [data length] : 50, i;
    const char signature[] = "<homebank v=";
    for (i = 0; i + sizeof(signature) - 1 <= length; i++) if (memcmp(bytes + i, signature, sizeof(signature) - 1) == 0) return YES;
    return NO;
}
static NSMutableDictionary *ETValues(NSString *type, NSString *account, NSString *amount) {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:type, @"type", account, @"account", amount, @"amount", @"15/10/2026", @"date",
        @"0", @"status", @"2", @"category", @"0", @"paymode", @"Nouveau & <tiers>", @"payeeName", @"Memo & <texte>", @"memo", @"CHEQUE-7", @"number",
        @"2", @"destination", @"10,00", @"destinationAmount", @"out", @"direction", nil];
}
void HBEditingTests(HBWallet *original) {
    NSString *error = nil;
    NSMutableDictionary *values = ETValues(@"expense", @"1", @"12,34");
    HBWallet *expense = [original walletByUpdatingRecord:nil values:values error:&error];
    HBCheck(expense != nil && error == nil, "creates expense with French decimal input and escaped texts");
    HBCheck(ETOriginalHeader(expense), "edited XML passes original HomeBank's first-50-byte signature check");
    [[expense sourceData] writeToFile:@"build/homebank-compatible-edit.xhb" atomically:YES];
    NSDictionary *record = [[expense records] lastObject];
    HBCheck([[record objectForKey:@"amount"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"-12.34"]], "expense sign");
    HBCheck([[expense payeeForRecord:record] isEqualToString:@"Nouveau & <tiers>"] && [[record objectForKey:@"wording"] isEqualToString:@"Memo & <texte>"] && [[record objectForKey:@"info"] isEqualToString:@"CHEQUE-7"], "distinct payee, memo and payment number survive XML escaping");
    HBCheck([[[expense balancesForAccount:[expense accountWithKey:@"1"]] objectForKey:@"future"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"27.66"]], "expense updates future balance exactly");
    HBWallet *income = [expense walletByUpdatingRecord:nil values:ETValues(@"income", @"1", @"100") error:&error];
    HBCheck(income != nil && [[[[income records] lastObject] objectForKey:@"flags"] intValue] & 2, "creates income with HomeBank flag");
    [values setObject:@"transfer" forKey:@"type"]; [values setObject:@"10" forKey:@"amount"];
    HBWallet *transfer = [original walletByUpdatingRecord:nil values:values error:&error];
    NSDictionary *incoming = [[transfer records] lastObject], *outgoing = [transfer counterpartForRecord:incoming];
    HBCheck(transfer != nil && outgoing != nil && [[transfer records] count] == [[original records] count] + 2, "creates a linked two-sided transfer");
    HBCheck([[incoming objectForKey:@"amount"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"10"]] && [[outgoing objectForKey:@"amount"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"-10"]], "transfer amounts do not cancel account movements");
    [values setObject:@"2" forKey:@"account"]; [values setObject:@"1" forKey:@"destination"]; [values setObject:@"in" forKey:@"direction"]; [values setObject:@"20" forKey:@"amount"];
    HBWallet *edited = [transfer walletByUpdatingRecord:incoming values:values error:&error];
    HBCheck(edited != nil && [[[edited counterpartForRecord:[[edited records] lastObject]] objectForKey:@"amount"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"-20"]], "edits a transfer from its incoming side");
    HBWallet *pointed = [edited walletByChangingStatus:@"1" record:[[edited records] lastObject] error:&error];
    HBCheck(pointed != nil && [[[pointed counterpartForRecord:[[pointed records] lastObject]] objectForKey:@"st"] intValue] == 0, "pointing is per account side");
    HBWallet *reconciled = [pointed walletByChangingStatus:@"2" record:[[pointed records] lastObject] error:&error];
    [values setObject:@"30" forKey:@"amount"];
    HBCheck([reconciled walletByUpdatingRecord:[[reconciled records] lastObject] values:values error:&error] == nil, "protects reconciled linked transfer amounts");
    HBCheck([reconciled walletByDeletingRecord:[[reconciled records] lastObject] error:&error] == nil, "protects reconciled transfers from deletion");
    HBWallet *voided = [pointed walletByChangingStatus:@"3" record:[[pointed records] lastObject] error:&error];
    HBCheck([[[voided counterpartForRecord:[[voided records] lastObject]] objectForKey:@"st"] intValue] == 3, "voiding affects both transfer sides");
    HBWallet *removed = [pointed walletByDeletingRecord:[[pointed records] lastObject] error:&error];
    HBCheck(removed != nil && [[removed records] count] == [[original records] count], "deletes both transfer records atomically");
    values = ETValues(@"transfer", @"1", @"10"); [values setObject:@"4" forKey:@"destination"]; [values setObject:@"12,50" forKey:@"destinationAmount"];
    HBWallet *foreign = [original walletByUpdatingRecord:nil values:values error:&error];
    HBCheck(foreign != nil && [[[[foreign records] lastObject] objectForKey:@"amount"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"12.5"]], "cross-currency transfer has explicit destination amount");
    [values setObject:@"1" forKey:@"destination"];
    HBCheck([original walletByUpdatingRecord:nil values:values error:&error] == nil, "rejects same-account transfer");
    values = ETValues(@"expense", @"3", @"1"); HBCheck([original walletByUpdatingRecord:nil values:values error:&error] == nil, "rejects new operations on closed accounts");
    values = ETValues(@"expense", @"1", @"0"); HBCheck([original walletByUpdatingRecord:nil values:values error:&error] == nil, "rejects zero amount");
    [values setObject:@"0,001" forKey:@"amount"]; HBCheck([original walletByUpdatingRecord:nil values:values error:&error] == nil, "rejects invisible currency fraction");
    [values setObject:@"2" forKey:@"amount"]; [values setObject:@"31/02/2026" forKey:@"date"]; HBCheck([original walletByUpdatingRecord:nil values:values error:&error] == nil, "rejects invalid calendar date");
    HBCheck(HBOrdinalFromFrenchDate(@"01/01/2040") == 744730 && HBOrdinalFromFrenchDate(@"29/02/2024") != 0 && HBOrdinalFromFrenchDate(@"29/02/2025") == 0, "date input leap years and dates beyond 2038");
    HBWallet *opaque = ETParse(@"<homebank v='1.6000000000000001' custom='keep' xmlns:x='urn:test'><!--keep-comment--><properties title='Test' curr='1'/><account key='1' initial='0'/><cat key='2' name='Test'/><ope account='1' date='739890' amount='-2' custom='transaction' scat='2||2' samt='-1||-1' smem='a||b'/><x:extension secret='preserve'><x:child/></x:extension><fav recflg='1' account='1' nextdate='739920' every='1' unit='2' amount='-15' custom='template'/></homebank>");
    HBWallet *opaqueEdited = [opaque walletByChangingStatus:@"1" record:[[opaque records] objectAtIndex:0] error:&error];
    NSString *xml = [[[NSString alloc] initWithData:[opaqueEdited sourceData] encoding:NSUTF8StringEncoding] autorelease];
    HBCheck(opaqueEdited != nil && [xml rangeOfString:@"keep-comment"].location != NSNotFound && [xml rangeOfString:@"x:extension"].location != NSNotFound && [xml rangeOfString:@"scat=\"2||2\""].location != NSNotFound && [xml rangeOfString:@"custom=\"template\""].location != NSNotFound && [xml rangeOfString:@"1.6000000000000001"].location != NSNotFound, "preserves unknown nodes, attributes, comments, splits, templates and raw version");
    HBCheck(ETOriginalHeader(opaqueEdited), "namespace declarations do not precede the v attribute required by original HomeBank");
    [[opaqueEdited sourceData] writeToFile:@"build/homebank-compatible-opaque.xhb" atomically:YES];
    NSData *beforeRepair = [[original sourceData] copy];
    HBWallet *repaired = [original walletForHomeBankExport:&error];
    HBCheck(!ETOriginalHeader(original) && repaired != nil && ETOriginalHeader(repaired), "repairs previously exported XML declaration without needing a transaction edit");
    HBCheck([[original sourceData] isEqualToData:beforeRepair] && [[repaired records] isEqual:[original records]] && [[repaired accounts] isEqual:[original accounts]] && [[repaired templates] isEqual:[original templates]], "repair leaves source bytes and all account, transaction and recurrence values intact");
    [beforeRepair release];
    HBWallet *again = [repaired walletForHomeBankExport:&error];
    HBCheck([[again sourceData] isEqualToData:[repaired sourceData]], "compatible export is idempotent");
    [[repaired sourceData] writeToFile:@"build/homebank-compatible-repair.xhb" atomically:YES];
    HBWallet *order = ETParse(@"<homebank custom='a long attribute before the format marker' d='51003' v='1.6000000000000001'><account key='1'/></homebank>");
    HBWallet *ordered = [order walletForHomeBankExport:&error];
    HBCheck(ETOriginalHeader(ordered) && [[[[NSString alloc] initWithData:[ordered sourceData] encoding:NSUTF8StringEncoding] autorelease] rangeOfString:@"a long attribute before the format marker"].location != NSNotFound, "version attribute moves ahead of long attributes without dropping them");
    HBWallet *dataVersion = ETParse(@"<homebank xmlns:x='urn:very-long-extension-namespace-which-must-not-hide-data-version' v='1.4' custom='keep' d='051003'><account key='1'/></homebank>");
    HBWallet *dataVersionExport = [dataVersion walletForHomeBankExport:&error];
    NSString *dataXML = [[[NSString alloc] initWithData:[dataVersionExport sourceData] encoding:NSUTF8StringEncoding] autorelease];
    HBCheck([dataXML hasPrefix:@"<homebank v=\"1.4\" d=\"051003\""] && [dataXML rangeOfString:@"urn:very-long-extension"].location != NSNotFound, "keeps original data version ahead of namespace declarations for legacy migration detection");
    NSString *rootText = [NSString stringWithFormat:@"<homebank v='1.6' xmlns:x='urn:test' custom='Cr%Cdit &amp; &lt; &gt; &quot; &#10;&#13;&#9;' x:custom='ns &amp; &quot;value&quot;'><account key='1'/></homebank>", (unichar)0x00e9];
    HBWallet *rootSource = ETParse(rootText), *rootExport = [rootSource walletForHomeBankExport:&error];
    HBCheck(rootExport && [ETRootProperty(rootSource, "custom", NULL) isEqual:ETRootProperty(rootExport, "custom", NULL)], "root attributes preserve UTF8, XML escapes and whitespace with legacy serializers");
    HBCheck([ETRootProperty(rootSource, "custom", "urn:test") isEqual:ETRootProperty(rootExport, "custom", "urn:test")], "namespaced root attributes retain their prefix and decoded values");
    NSString *unicode = [NSString stringWithFormat:@"<?xml version='1.0' encoding='UTF-8'?><!--note--><homebank v='1.6'><properties title='Cr%Cdit &amp; %Cpargne' curr='1'/><account key='1'/><ope account='1' date='739904' amount='-1' wording='Ligne1&#10;Ligne2&#13;Fin&#9;&quot;test&quot;' info='N&amp;123'/></homebank><!--tail-->", (unichar)0x00e9, (unichar)0x00c9];
    HBWallet *unicodeSource = ETParse(unicode), *unicodeResult = [unicodeSource walletForHomeBankExport:&error];
    NSString *unicodeXML = [[[NSString alloc] initWithData:[unicodeResult sourceData] encoding:NSUTF8StringEncoding] autorelease];
    HBCheck(ETOriginalHeader(unicodeResult) && [[unicodeResult owner] isEqual:[unicodeSource owner]] && [unicodeXML rangeOfString:@"<!--note-->"].location != NSNotFound && [unicodeXML rangeOfString:@"<!--tail-->"].location != NSNotFound, "UTF8, escaped attributes and document-level comments survive repair");
    HBCheck([[unicodeResult records] isEqual:[unicodeSource records]], "memo line breaks, tabs, quotes and payment-number entities survive repair");
    [[unicodeResult sourceData] writeToFile:@"build/homebank-compatible-unicode.xhb" atomically:YES];
    HBWallet *longPrologue = ETParse(@"<!--1234567890123456789012345678901234567890123--><homebank v='1.6'/>");
    HBCheck([longPrologue walletForHomeBankExport:&error] == nil, "refuses an incompatible long prologue rather than deleting preserved comments");
    HBCheck([ETParse(@"<homebank><account key='1'/></homebank>") walletForHomeBankExport:&error] == nil, "does not invent a file version for unversioned input");
    values = ETValues(@"expense", @"1", @"3");
    HBCheck([opaque walletByUpdatingRecord:[[opaque records] objectAtIndex:0] values:values error:&error] == nil, "protects split amounts");
    values = ETValues(@"expense", @"1", @"12");
    HBCheck([income walletByUpdatingRecord:[[expense records] lastObject] values:values error:&error] != nil, "unrelated changes preserve editable record identity");
    HBWallet *modified = [expense walletByUpdatingRecord:[[expense records] lastObject] values:values error:&error];
    HBCheck([modified walletByUpdatingRecord:[[expense records] lastObject] values:values error:&error] == nil, "rejects stale record drafts");
    HBWallet *legacyMoney = ETParse(@"<homebank v='1.6'><account key='1'/><cat key='2' name='Test'/><ope account='1' date='739904' amount='-12.340000000000001' st='2'/></homebank>");
    values = ETValues(@"expense", @"1", @"12.340000000000001"); [values setObject:@"0" forKey:@"category"];
    [values setObject:@"2" forKey:@"status"];
    HBCheck([legacyMoney walletByUpdatingRecord:[[legacyMoney records] objectAtIndex:0] values:values error:&error] != nil, "legacy float precision does not prevent metadata-only edits");
    char *folder = strdup([[NSTemporaryDirectory() stringByAppendingPathComponent:@"homebank-panther-tests-XXXXXX"] fileSystemRepresentation]);
    HBCheck(mkdtemp(folder) != NULL, "creates isolated save test directory");
    NSString *directory = [NSString stringWithUTF8String:folder]; free(folder);
    NSString *path = [directory stringByAppendingPathComponent:@"test.xhb"];
    HBCheck(HBWriteWallet(expense, path, nil, &error), "exports a new wallet atomically");
    HBCheck(!HBWriteWallet(income, path, nil, &error), "new export never silently overwrites an existing file");
    HBCheck(HBWriteWallet(income, path, [expense sourceData], &error), "saves with matching disk version and backup");
    NSArray *files = [[NSFileManager defaultManager] directoryContentsAtPath:directory]; unsigned int backups = 0, i;
    for (i = 0; i < [files count]; i++) if ([[files objectAtIndex:i] rangeOfString:@".backup-"].location != NSNotFound) {
        backups++; HBCheck([[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:[files objectAtIndex:i]]] isEqualToData:[expense sourceData]], "backup is exactly the previous file");
    }
    HBCheck(backups == 1, "retains a backup before replacement");
    struct stat info; stat([path fileSystemRepresentation], &info); HBCheck((info.st_mode & 0777) == 0600, "saved wallet is private");
    HBCheck(!HBWriteWallet(expense, path, [expense sourceData], &error) && [[NSData dataWithContentsOfFile:path] isEqualToData:[income sourceData]], "rejects external changes without losing disk data");
    NSMutableData *changedBytes = [NSMutableData dataWithData:[income sourceData]];
    ((char *)[changedBytes mutableBytes])[[changedBytes length] - 1] = '?';
    [changedBytes writeToFile:path atomically:NO];
    HBCheck(!HBWriteWallet(expense, path, [income sourceData], &error) && [[NSData dataWithContentsOfFile:path] isEqualToData:changedBytes], "exact baseline comparison rejects same-size external edit, even invalid XML");
    NSData *truncated = [[income sourceData] subdataWithRange:NSMakeRange(0, [[income sourceData] length] - 1)];
    [truncated writeToFile:path atomically:NO];
    HBCheck(!HBWriteWallet(expense, path, [income sourceData], &error) && [[NSData dataWithContentsOfFile:path] isEqualToData:truncated], "baseline comparison rejects truncation without rewriting external data");
    [[income sourceData] writeToFile:path atomically:NO];
    HBCheck(!HBWriteWallet(nil, path, [income sourceData], &error) && [[NSData dataWithContentsOfFile:path] isEqualToData:[income sourceData]], "invalid replacement is still refused before writing");
    NSString *fifo = [directory stringByAppendingPathComponent:@"fifo.xhb"];
    HBCheck(mkfifo([fifo fileSystemRepresentation], 0600) == 0 && !HBWriteWallet(expense, fifo, [income sourceData], &error), "regular-file guard refuses FIFO without blocking reader");
    NSString *alias = [directory stringByAppendingPathComponent:@"alias.xhb"]; symlink([path fileSystemRepresentation], [alias fileSystemRepresentation]);
    HBCheck(!HBWriteWallet(expense, alias, [income sourceData], &error), "refuses replacing a symlink");
    NSString *lock = [path stringByAppendingString:@".panther-lock"]; [[@"test" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:lock atomically:NO];
    HBCheck(!HBWriteWallet(expense, path, [income sourceData], &error), "refuses another writer's lock");
    [[NSFileManager defaultManager] removeFileAtPath:directory handler:nil];
}
