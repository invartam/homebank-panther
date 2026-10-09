#import "HBWallet.h"
#import "HBWalletStore.h"
#include <stdlib.h>
#include <float.h>

static NSString *HBText(NSDictionary *attributes, NSString *name, NSString *fallback) {
    NSString *value = [attributes objectForKey:name];
    return value == nil || [value isEqualToString:@"(null)"] ? fallback : value;
}

BOOL HBParseUnsigned(NSString *text, unsigned long maximum, unsigned long *value) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    const char *p = [text UTF8String];
    unsigned long result = 0;
    if (p == NULL || *p == 0) return NO;
    while (*p) {
        if (*p < '0' || *p > '9' || result > maximum / 10
            || (result == maximum / 10 && (unsigned long)(*p - '0') > maximum % 10)) return NO;
        result = result * 10 + (*p++ - '0');
    }
    *value = result;
    return result <= maximum;
}

static BOOL HBNumeric(NSString *text, BOOL signedValue) {
    const char *p = [text UTF8String];
    int digits = 0;
    if (p == NULL || [text length] > 128) return NO;
    if (signedValue && (*p == '-' || *p == '+')) p++;
    while (*p >= '0' && *p <= '9') { digits++; p++; }
    if (*p == '.') {
        p++;
        while (*p >= '0' && *p <= '9') { digits++; p++; }
    }
    if (!digits || digits > 38) return NO;
    if (*p == 'e' || *p == 'E') {
        int exponentDigits = 0;
        p++;
        if (*p == '-' || *p == '+') p++;
        while (*p >= '0' && *p <= '9') { exponentDigits++; p++; }
        if (!exponentDigits) return NO;
    }
    return *p == 0;
}

static NSDecimalNumber *HBDecimal(NSString *text) {
    NSDecimalNumber *value;
    if (!HBNumeric(text, YES)) return nil;
    value = [NSDecimalNumber decimalNumberWithString:text locale:
        [NSDictionary dictionaryWithObject:@"." forKey:@"NSDecimalSeparator"]];
    return [value isEqualToNumber:[NSDecimalNumber notANumber]] ? nil : value;
}

NSDecimalNumber *HBMoneyFromText(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return HBDecimal([[trimmed componentsSeparatedByString:@","] componentsJoinedByString:@"."]);
}

int HBOrdinalFromDate(NSCalendarDate *date) {
    return (int)([date timeIntervalSinceDate:HBDateFromOrdinal(730486)] / 86400.0) + 730486;
}

int HBOrdinalFromFrenchDate(NSString *text) {
    unsigned long day, month, year;
    if ([text length] != 10 || [text characterAtIndex:2] != '/' || [text characterAtIndex:5] != '/') return 0;
    if (!HBParseUnsigned([text substringToIndex:2], 31, &day) || !day
        || !HBParseUnsigned([text substringWithRange:NSMakeRange(3, 2)], 12, &month) || !month
        || !HBParseUnsigned([text substringFromIndex:6], 9999, &year) || !year) return 0;
    NSCalendarDate *date = [NSCalendarDate dateWithYear:year month:month day:day hour:12 minute:0 second:0
        timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    if ([date yearOfCommonEra] != (int)year || [date monthOfYear] != month || [date dayOfMonth] != day) return 0;
    int ordinal = HBOrdinalFromDate(date);
    return ordinal >= 1 && ordinal <= 3652059 ? ordinal : 0;
}

BOOL HBIsTransfer(NSDictionary *record) {
    unsigned long transfer = 0, destination = 0;
    HBParseUnsigned([record objectForKey:@"kxfer"], 4294967295UL, &transfer);
    HBParseUnsigned([record objectForKey:@"dst_account"], 4294967295UL, &destination);
    return ([[record objectForKey:@"flags"] intValue] & 8) || [[record objectForKey:@"paymode"] intValue] == 5
        || transfer > 0 || destination > 0;
}

static HBIndex HBRecordOrder(id a, id b, void *context) {
    int left = [[a objectForKey:@"date"] intValue];
    int right = [[b objectForKey:@"date"] intValue];
    if (left != right) return left > right ? NSOrderedAscending : NSOrderedDescending;
    return [[a objectForKey:@"__index"] compare:[b objectForKey:@"__index"]];
}

NSCalendarDate *HBDateFromOrdinal(int ordinal) {
    NSCalendarDate *epoch = [NSCalendarDate dateWithYear:2001 month:1 day:1
        hour:12 minute:0 second:0 timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    /* HomeBank uses GLib's Julian day, with 01/01/0001 = 1. */
    return [epoch dateByAddingYears:0 months:0 days:ordinal - 730486 hours:0 minutes:0 seconds:0];
}

NSCalendarDate *HBToday(void) {
    NSCalendarDate *now = [NSCalendarDate calendarDate];
    return [NSCalendarDate dateWithYear:[now yearOfCommonEra] month:[now monthOfYear]
        day:[now dayOfMonth] hour:12 minute:0 second:0 timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
}

@implementation HBWallet
+ (id)walletAtPath:(NSString *)path error:(NSString **)error {
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    NSMutableData *data = [NSMutableData data];
    BOOL readable = file != nil;
    BOOL tooLarge = NO;
    if (error) *error = nil;
    NS_DURING
        while (readable) {
            NSData *chunk = [file readDataOfLength:65536];
            if ([chunk length] == 0) break;
            if ([data length] + [chunk length] > HB_MAX_FILE_BYTES) { tooLarge = YES; break; }
            [data appendData:chunk];
        }
        [file closeFile];
    NS_HANDLER
        readable = NO;
    NS_ENDHANDLER
    if (!readable || tooLarge) {
        if (error) *error = tooLarge ? @"Fichier trop volumineux pour cette edition (8 Mo maximum)." : @"Impossible de lire le fichier.";
        return nil;
    }
    return [[[self alloc] initWithData:data error:error] autorelease];
}

- (void)fail:(NSString *)message parser:(NSXMLParser *)parser {
    if (_error == nil) _error = [message copy];
    [parser abortParsing];
}

- (BOOL)integer:(NSMutableDictionary *)attributes name:(NSString *)name fallback:(NSString *)fallback
    maximum:(unsigned long)maximum parser:(NSXMLParser *)parser {
    unsigned long value;
    NSString *raw = [attributes objectForKey:name];
    NSString *text = raw == nil ? fallback : raw;
    if (!HBParseUnsigned(text, maximum, &value)) {
        [self fail:@"Attribut entier invalide dans le fichier." parser:parser]; return NO;
    }
    if (!raw || ([text length] > 1 && [text characterAtIndex:0] == '0'))
        [attributes setObject:[NSString stringWithFormat:@"%lu", value] forKey:name];
    return YES;
}

- (BOOL)decimal:(NSMutableDictionary *)attributes name:(NSString *)name parser:(NSXMLParser *)parser {
    NSString *raw = [attributes objectForKey:name];
    NSDecimalNumber *value = HBDecimal(raw == nil ? @"0" : raw);
    if (value == nil) { [self fail:@"Montant invalide ou hors precision dans le fichier." parser:parser]; return NO; }
    [attributes setObject:value forKey:name]; return YES;
}

- (id)initWithData:(NSData *)data error:(NSString **)error {
    NSString *text;
    NSXMLParser *parser;
    BOOL parsed;
    unsigned int i;
    self = [super init];
    if (!self) return nil;
    if (error) *error = nil;
    _accounts = [[NSMutableArray alloc] init]; _records = [[NSMutableArray alloc] init];
    _currencies = [[NSMutableDictionary alloc] init]; _payees = [[NSMutableDictionary alloc] init];
    _categories = [[NSMutableDictionary alloc] init]; _balances = [[NSMutableDictionary alloc] init];
    _recordsByAccount = [[NSMutableDictionary alloc] init];
    _templates = [[NSMutableArray alloc] init]; _sourceData = [data copy];
    _moneyFormatters = [[NSMutableDictionary alloc] init]; _moneyLock = [[NSLock alloc] init];
    _accountLookup = [[NSMutableDictionary alloc] init]; _recordLookup = [[NSMutableDictionary alloc] init];
    _recordSlots = [[NSMutableDictionary alloc] init]; _transferLookup = [[NSMutableDictionary alloc] init];
    _payeeNameLookup = [[NSMutableDictionary alloc] init]; _journalCommands = [[NSMutableArray alloc] init];
    _newPayees = [[NSMutableArray alloc] init]; _xmlChanges = [[NSMutableDictionary alloc] init];
    _owner = [@"" copy]; _baseCurrency = [@"1" copy];
    text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if ([data length] == 0 || [data length] > HB_MAX_FILE_BYTES || text == nil) {
        _error = [@"Fichier vide, trop volumineux ou non UTF-8." copy];
    } else if ([text rangeOfString:@"<!DOCTYPE" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        _error = [@"Les declarations DTD ne sont pas autorisees." copy];
    }
    parser = [[NSXMLParser alloc] initWithData:data];
    [parser setDelegate:(id)self];
    [parser setShouldResolveExternalEntities:NO];
    parsed = _error == nil && [parser parse];
    [parser release];
    if (!parsed || !_seenRoot || _depth != 0) {
        if (_error == nil) _error = [@"Fichier XML HomeBank invalide." copy];
    }
    for (i = 0; _error == nil && i < [_accounts count]; i++) {
        NSDictionary *account = [_accounts objectAtIndex:i];
        NSString *key = [account objectForKey:@"key"];
        NSDecimalNumber *initial = [account objectForKey:@"initial"];
        NSMutableDictionary *balance;
        if ([key isEqualToString:@"0"] || [_balances objectForKey:key] != nil) {
            _error = [@"Identifiant de compte nul ou duplique." copy]; break;
        }
        if ([_currencies count] && [_currencies objectForKey:[account objectForKey:@"curr"]] == nil) {
            _error = [@"Devise de compte introuvable dans le fichier." copy]; break;
        }
        balance = [NSMutableDictionary dictionaryWithObjectsAndKeys:initial, @"reconciled", initial, @"cleared", initial, @"future", nil];
        [_balances setObject:balance forKey:key];
        [_recordsByAccount setObject:[NSMutableArray array] forKey:key];
        [_accountLookup setObject:account forKey:key];
    }
    NSString *balanceFields[] = { @"future", @"cleared", @"reconciled" };
    for (i = 0; _error == nil && i < [_records count]; i++) {
        NSDictionary *record = [_records objectAtIndex:i];
        NSString *key = [record objectForKey:@"account"];
        NSMutableDictionary *balance = [_balances objectForKey:key];
        int status = [[record objectForKey:@"st"] intValue];
        unsigned int j;
        if (balance == nil) { _error = [@"Une operation reference un compte introuvable." copy]; break; }
        [[_recordsByAccount objectForKey:key] addObject:record];
        NSNumber *identifier = [record objectForKey:@"__index"];
        [_recordLookup setObject:record forKey:identifier]; [_recordSlots setObject:[NSNumber numberWithUnsignedInt:i] forKey:identifier];
        unsigned long transferKey = 0; HBParseUnsigned([record objectForKey:@"kxfer"], 4294967295UL, &transferKey);
        if (transferKey > _maxTransferKey) _maxTransferKey = transferKey;
        if (transferKey) {
            NSString *transfer = [record objectForKey:@"kxfer"]; NSMutableArray *group = [_transferLookup objectForKey:transfer];
            if (!group) { group = [NSMutableArray array]; [_transferLookup setObject:group forKey:transfer]; }
            [group addObject:record];
        }
        for (j = 0; j < 3; j++) {
            NSString *field = balanceFields[j];
            NSDecimal left, right, sum;
            if (status == 3 || (j == 1 && status != 1 && status != 2) || (j == 2 && status != 2)) continue;
            left = [[balance objectForKey:field] decimalValue]; right = [[record objectForKey:@"amount"] decimalValue];
            if (NSDecimalAdd(&sum, &left, &right, NSRoundPlain) != NSCalculationNoError) {
                _error = [@"Solde hors precision decimale." copy]; break;
            }
            [balance setObject:[NSDecimalNumber decimalNumberWithDecimal:sum] forKey:field];
        }
    }
    if (_error != nil) {
        if (error) *error = [[_error retain] autorelease];
        [self release]; return nil;
    }
    for (i = 0; i < [_accounts count]; i++) {
        [[_recordsByAccount objectForKey:[[_accounts objectAtIndex:i] objectForKey:@"key"]]
            sortUsingFunction:HBRecordOrder context:NULL];
    }
    _nextOperationID = [_records count];
    NSArray *payees = [_payees allValues];
    for (i = 0; i < [payees count]; i++) {
        NSDictionary *payee = [payees objectAtIndex:i]; unsigned long key = 0;
        HBParseUnsigned([payee objectForKey:@"key"], 4294967295UL, &key); if (key > _maxPayeeKey) _maxPayeeKey = key;
        NSString *name = [[payee objectForKey:@"name"] lowercaseString]; NSDictionary *existing = name ? [_payeeNameLookup objectForKey:name] : nil;
        if (name && (!existing || key < strtoul([[existing objectForKey:@"key"] UTF8String], NULL, 10))) [_payeeNameLookup setObject:payee forKey:name];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)name namespaceURI:(NSString *)uri
    qualifiedName:(NSString *)qualified attributes:(NSDictionary *)attributes {
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithDictionary:attributes];
    _depth++;
    if (_depth > 128) { [self fail:@"Fichier XML trop imbrique." parser:parser]; return; }
    if (_depth == 1) {
        NSString *version = [attributes objectForKey:@"v"];
        if (_seenRoot || ![name isEqualToString:@"homebank"]) { [self fail:@"Racine HomeBank manquante." parser:parser]; return; }
        _seenRoot = YES;
        _canEdit = version != nil && ![[attributes objectForKey:@"xmlns"] length];
        if (version != nil) {
            double value = [HBDecimal(version) doubleValue];
            /* HomeBank serializes v as a double (including GLib's 17-digit form). */
            if (!HBNumeric(version, NO) || value <= 0 || value > DBL_MAX) [self fail:@"Version du fichier invalide." parser:parser];
            else if (value > 1.6) [self fail:@"Format HomeBank plus recent que 1.6 : fichier non pris en charge." parser:parser];
        }
        return;
    }
    if (_depth != 2) return;
    if ([name isEqualToString:@"properties"]) {
        if (![self integer:a name:@"curr" fallback:@"1" maximum:4294967295UL parser:parser]) return;
        [_owner release]; _owner = [HBText(a, @"title", @"") copy];
        [_baseCurrency release]; _baseCurrency = [[a objectForKey:@"curr"] copy];
    } else if ([name isEqualToString:@"account"]) {
        NSArray *names = [NSArray arrayWithObjects:@"key", @"flags", @"type", @"pos", @"curr", nil];
        unsigned int i;
        for (i = 0; i < [names count]; i++) {
            NSString *field = [names objectAtIndex:i];
            if (![self integer:a name:field fallback:[field isEqualToString:@"curr"] ? _baseCurrency : @"0" maximum:4294967295UL parser:parser]) return;
        }
        if (![self decimal:a name:@"initial" parser:parser] || ![self decimal:a name:@"minimum" parser:parser]) return;
        [a setObject:HBText(a, @"name", @"Compte") forKey:@"name"];
        [_accounts addObject:[[[HBAccount alloc] initWithAttributes:a] autorelease]];
    } else if ([name isEqualToString:@"ope"]) {
        NSString *names[] = { @"account", @"payee", @"category", @"flags", @"st", @"date", @"kxfer", @"dst_account", @"paymode" };
        unsigned int i;
        for (i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
            NSString *field = names[i];
            unsigned long maximum = [field isEqualToString:@"date"] ? 3652059UL : [field isEqualToString:@"st"] ? 3UL : 4294967295UL;
            if (![self integer:a name:field fallback:@"0" maximum:maximum parser:parser]) return;
        }
        if ([[a objectForKey:@"date"] intValue] == 0) { [self fail:@"Date d'operation invalide." parser:parser]; return; }
        if (![self decimal:a name:@"amount" parser:parser]) return;
        [a setObject:[NSNumber numberWithUnsignedInt:[_records count]] forKey:@"__index"];
        [_records addObject:[[[HBOperation alloc] initWithAttributes:a identifier:[_records count] version:0] autorelease]];
    } else if ([name isEqualToString:@"fav"]) {
        [_templates addObject:a];
    } else if ([name isEqualToString:@"cur"] || [name isEqualToString:@"pay"] || [name isEqualToString:@"cat"]) {
        NSMutableDictionary *target = [name isEqualToString:@"cur"] ? _currencies : [name isEqualToString:@"pay"] ? _payees : _categories;
        NSString *key;
        if (![self integer:a name:@"key" fallback:@"0" maximum:4294967295UL parser:parser]) return;
        key = [a objectForKey:@"key"];
        if ([target objectForKey:key] != nil) { [self fail:@"Identifiant de devise, tiers ou categorie duplique." parser:parser]; return; }
        if ([name isEqualToString:@"cur"] && ![self integer:a name:@"frac" fallback:@"2" maximum:20UL parser:parser]) return;
        if ([name isEqualToString:@"cat"] && ![self integer:a name:@"parent" fallback:@"0" maximum:4294967295UL parser:parser]) return;
        [target setObject:a forKey:key];
    }
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified { _depth--; }
- (NSData *)parser:(NSXMLParser *)parser resolveExternalEntityName:(NSString *)name systemID:(NSString *)systemID {
    [self fail:@"Entite XML externe refusee." parser:parser]; return nil;
}
- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)error {
    if (_error == nil) _error = [@"Fichier XML invalide." copy];
}
- (NSArray *)accounts { return _accounts; }
- (NSString *)owner { return _owner; }
- (NSData *)sourceData {
    if (!_generation) return _sourceData;
    if (!_serializedData) _serializedData = [[[self walletForHomeBankExport:NULL] baseSourceData] copy];
    return _serializedData;
}
- (NSArray *)records { return _records; }
- (NSArray *)templates { return _templates; }
- (NSArray *)payees { return [_payees allValues]; }
- (NSArray *)categories { return [_categories allValues]; }
- (NSDictionary *)accountWithKey:(NSString *)key {
    return key ? [_accountLookup objectForKey:key] : nil;
}
- (NSString *)currencyKeyForAccount:(NSDictionary *)account { return [account objectForKey:@"curr"] ? [account objectForKey:@"curr"] : _baseCurrency; }
- (unsigned int)fractionDigitsForAccount:(NSDictionary *)account {
    NSDictionary *currency = [_currencies objectForKey:[self currencyKeyForAccount:account]];
    return currency ? [[currency objectForKey:@"frac"] intValue] : 2;
}
- (NSArray *)recordsForAccount:(NSDictionary *)account { return account ? [_recordsByAccount objectForKey:[account objectForKey:@"key"]] : nil; }
- (NSDictionary *)balancesForAccount:(NSDictionary *)account { return account ? [_balances objectForKey:[account objectForKey:@"key"]] : nil; }
- (NSString *)payeeForRecord:(NSDictionary *)record {
    return HBText([_payees objectForKey:[record objectForKey:@"payee"]], @"name", HBText(record, @"wording", @"Operation"));
}
- (NSString *)categoryForRecord:(NSDictionary *)record {
    NSMutableArray *parts = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSString *key = [record objectForKey:@"category"];
    while (key && ![key isEqualToString:@"0"] && ![seen containsObject:key]) {
        NSDictionary *category = [_categories objectForKey:key];
        if (!category) break;
        [seen addObject:key];
        [parts insertObject:HBText(category, @"name", @"") atIndex:0];
        key = [category objectForKey:@"parent"];
    }
    return [parts componentsJoinedByString:@":"];
}
- (NSString *)formatAmount:(NSDecimalNumber *)amount account:(NSDictionary *)account {
    NSDictionary *currency = [_currencies objectForKey:[account objectForKey:@"curr"]];
    unsigned int digits = currency ? [[currency objectForKey:@"frac"] intValue] : 2;
    NSString *key = [account objectForKey:@"curr"] ? [account objectForKey:@"curr"] : @"";
    NSString *formatted = nil;
    [_moneyLock lock];
    @try {
        NSNumberFormatter *formatter = [_moneyFormatters objectForKey:key];
        if (!formatter) {
            NSMutableString *format = [NSMutableString stringWithString:@"#,##0"], *zero = [NSMutableString stringWithString:@"0"];
            unsigned int i;
            if (digits) { [format appendString:@"."]; [zero appendString:@","]; }
            for (i = 0; i < digits; i++) { [format appendString:@"0"]; [zero appendString:@"0"]; }
            formatter = [[[NSNumberFormatter alloc] init] autorelease];
            [formatter setFormat:[NSString stringWithFormat:@"%@;%@;-%@", format, zero, format]];
            [formatter setDecimalSeparator:@","]; [formatter setThousandSeparator:@" "]; [formatter setHasThousandSeparators:YES];
            [_moneyFormatters setObject:formatter forKey:key];
        }
        formatted = [[[formatter stringForObjectValue:amount] copy] autorelease];
    } @finally { [_moneyLock unlock]; }
    return [NSString stringWithFormat:@"%@ %@", formatted ? formatted : [amount description], HBText(currency, @"iso", @"EUR")];
}
- (void)dealloc {
    [_accounts release]; [_records release]; [_currencies release]; [_payees release]; [_categories release];
    [_balances release]; [_recordsByAccount release]; [_owner release]; [_baseCurrency release]; [_error release]; [_sourceData release]; [_templates release];
    [_moneyFormatters release]; [_moneyLock release];
    [_accountLookup release]; [_recordLookup release]; [_recordSlots release]; [_transferLookup release]; [_payeeNameLookup release];
    [_journalCommands release]; [_newPayees release]; [_xmlChanges release]; [_serializedData release]; [_createdIdentifier release];
    [super dealloc];
}
@end
