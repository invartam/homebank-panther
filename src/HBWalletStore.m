#import "HBWalletStore.h"
#include <stdlib.h>
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
typedef id<NSCopying> HBStoreKey;
#else
typedef id HBStoreKey;
#endif

@implementation HBOperation
- (void)cacheFields {
    id date = [_attributes objectForKey:@"date"], status = [_attributes objectForKey:@"st"];
    _date = [date respondsToSelector:@selector(intValue)] ? [date intValue] : 0;
    _status = [status respondsToSelector:@selector(intValue)] ? [status intValue] : 0;
    id account = [_attributes objectForKey:@"account"], amount = [_attributes objectForKey:@"amount"];
    _accountKey = [account isKindOfClass:[NSString class]] ? [account copy] : nil;
    _amount = [amount isKindOfClass:[NSDecimalNumber class]] ? [amount retain] : nil;
}
- (id)initWithObjects:(const id *)objects forKeys:(const HBStoreKey *)keys count:(HBCollectionCount)count {
    self = [super init]; if (self) {
        _attributes = [[NSDictionary alloc] initWithObjects:objects forKeys:keys count:count];
        id identifier = [_attributes objectForKey:@"__index"];
        _identifier = [identifier isKindOfClass:[NSNumber class]] ? [identifier unsignedLongValue] : 0;
        [self cacheFields];
    } return self;
}
- (id)initWithAttributes:(NSDictionary *)attributes identifier:(unsigned long)identifier version:(unsigned int)version {
    self = [super init]; if (self) {
        NSMutableDictionary *values = [NSMutableDictionary dictionaryWithDictionary:attributes];
        [values setObject:[NSNumber numberWithUnsignedLong:identifier] forKey:@"__index"];
        _attributes = [values copy]; _identifier = identifier; _version = version;
        [self cacheFields];
    } return self;
}
- (HBCollectionCount)count { return [_attributes count]; }
- (NSEnumerator *)keyEnumerator { return [_attributes keyEnumerator]; }
- (id)objectForKey:(id)key { return [_attributes objectForKey:key]; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (unsigned long)identifier { return _identifier; }
- (unsigned int)version { return _version; }
- (unsigned int)date { return _date; }
- (unsigned int)status { return _status; }
- (NSString *)accountKey { return _accountKey; }
- (NSDecimalNumber *)amount { return _amount; }
- (void)dealloc { [_attributes release]; [_accountKey release]; [_amount release]; [super dealloc]; }
@end

@implementation HBAccount
- (id)initWithObjects:(const id *)objects forKeys:(const HBStoreKey *)keys count:(HBCollectionCount)count {
    NSDictionary *attributes = [NSDictionary dictionaryWithObjects:objects forKeys:keys count:count];
    return [self initWithAttributes:attributes];
}
- (id)initWithAttributes:(NSDictionary *)attributes {
    self = [super init]; if (self) {
        _attributes = [attributes copy]; id key = [attributes objectForKey:@"key"], initial = [attributes objectForKey:@"initial"];
        _key = [key isKindOfClass:[NSString class]] ? [key copy] : nil;
        _initial = [initial isKindOfClass:[NSDecimalNumber class]] ? [initial retain] : nil;
    } return self;
}
- (HBCollectionCount)count { return [_attributes count]; }
- (NSEnumerator *)keyEnumerator { return [_attributes keyEnumerator]; }
- (id)objectForKey:(id)key { return [_attributes objectForKey:key]; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)key { return _key; }
- (NSDecimalNumber *)initial { return _initial; }
- (void)dealloc { [_attributes release]; [_key release]; [_initial release]; [super dealloc]; }
@end

@implementation HBWalletStore
@end

static BOOL HBStoreError(NSString **error, NSString *text) { if (error) *error = text; return NO; }
static BOOL HBContributes(unsigned int status, unsigned int field) { return status != 3 && (field == 0 || (field == 1 && (status == 1 || status == 2)) || (field == 2 && status == 2)); }
static void HBInsertRecord(NSMutableArray *array, HBOperation *record) {
    unsigned int low = 0, high = [array count];
    while (low < high) {
        unsigned int middle = low + (high - low) / 2; HBOperation *existing = [array objectAtIndex:middle];
        if ([existing date] > [record date] || ([existing date] == [record date] && [existing identifier] < [record identifier])) low = middle + 1;
        else high = middle;
    }
    [array insertObject:record atIndex:low];
}
static BOOL HBDelta(NSMutableDictionary *balance, HBOperation *record, BOOL remove) {
    NSString *fields[] = { @"future", @"cleared", @"reconciled" }; unsigned int i;
    for (i = 0; i < 3; i++) if (HBContributes([record status], i)) {
        NSDecimal current = [[balance objectForKey:fields[i]] decimalValue], amount = [[record amount] decimalValue], result;
        NSCalculationError status = remove ? NSDecimalSubtract(&result, &current, &amount, NSRoundPlain) : NSDecimalAdd(&result, &current, &amount, NSRoundPlain);
        if (status != NSCalculationNoError) return NO;
        [balance setObject:[NSDecimalNumber decimalNumberWithDecimal:result] forKey:fields[i]];
    }
    return YES;
}

@implementation HBWallet (WorkingStore)
- (HBWalletStore *)workingCopy {
    HBWallet *copy = [[[HBWalletStore alloc] init] autorelease];
    copy->_accounts = [_accounts retain]; copy->_records = [_records mutableCopy];
    copy->_currencies = [_currencies retain]; copy->_payees = [_payees mutableCopy]; copy->_categories = [_categories retain];
    copy->_balances = [_balances mutableCopy]; copy->_recordsByAccount = [_recordsByAccount mutableCopy];
    copy->_owner = [_owner retain]; copy->_baseCurrency = [_baseCurrency retain]; copy->_sourceData = [_sourceData retain];
    copy->_templates = [_templates retain]; copy->_moneyFormatters = [_moneyFormatters retain]; copy->_moneyLock = [_moneyLock retain];
    copy->_accountLookup = [_accountLookup retain]; copy->_recordLookup = [_recordLookup mutableCopy]; copy->_recordSlots = [_recordSlots mutableCopy];
    copy->_transferLookup = [_transferLookup mutableCopy]; copy->_payeeNameLookup = [_payeeNameLookup mutableCopy];
    copy->_journalCommands = [_journalCommands mutableCopy]; copy->_newPayees = [_newPayees mutableCopy]; copy->_xmlChanges = [_xmlChanges mutableCopy];
    copy->_generation = _generation; copy->_nextOperationID = _nextOperationID; copy->_maxPayeeKey = _maxPayeeKey; copy->_maxTransferKey = _maxTransferKey;
    copy->_canEdit = _canEdit; copy->_seenRoot = YES;
    return (HBWalletStore *)copy;
}
- (NSArray *)journalCommands { return _journalCommands; }
- (unsigned int)generation { return _generation; }
- (NSData *)baseSourceData { return _sourceData; }
- (NSDictionary *)xmlChanges { return _xmlChanges; }
- (NSArray *)newPayees { return _newPayees; }
- (NSDictionary *)recordWithIdentifier:(NSNumber *)identifier { return identifier ? [_recordLookup objectForKey:identifier] : nil; }
- (NSNumber *)createdIdentifier { return _createdIdentifier; }
- (BOOL)canEdit { return _canEdit; }
- (NSDictionary *)command:(NSString *)kind record:(NSDictionary *)record values:(NSDictionary *)values {
    NSMutableDictionary *command = [NSMutableDictionary dictionaryWithObjectsAndKeys:kind, @"kind",
        record ? [[record objectForKey:@"__index"] stringValue] : @"new", @"id",
        [NSString stringWithFormat:@"%u", _generation + 1], @"generation",
        [NSString stringWithFormat:@"%u", record ? [(HBOperation *)record version] : 0], @"version", nil];
    if (values) [command setObject:[[values copy] autorelease] forKey:@"values"];
    return command;
}
- (HBWallet *)commitRecords:(NSArray *)records deleting:(NSArray *)deleted payee:(NSDictionary *)payee command:(NSDictionary *)command error:(NSString **)error {
    if (!_canEdit || _generation == 4294967295UL || [_journalCommands count] >= 10000) { HBStoreError(error, @"Format non editable ou limite du journal atteinte. Consolider le XML."); return nil; }
    HBWallet *copy = [self workingCopy]; NSMutableSet *accounts = [NSMutableSet set], *transfers = [NSMutableSet set];
    NSMutableArray *oldRecords = [NSMutableArray array]; unsigned int i;
    for (i = 0; i < [records count]; i++) {
        NSDictionary *record = [records objectAtIndex:i]; NSDictionary *old = [self recordWithIdentifier:[record objectForKey:@"__index"]];
        if (old) [oldRecords addObject:old]; [accounts addObject:[record objectForKey:@"account"]];
    }
    [oldRecords addObjectsFromArray:deleted];
    for (i = 0; i < [oldRecords count]; i++) [accounts addObject:[[oldRecords objectAtIndex:i] objectForKey:@"account"]];
    NSEnumerator *keys = [accounts objectEnumerator]; NSString *key;
    while ((key = [keys nextObject])) {
        if (![self accountWithKey:key]) { HBStoreError(error, @"Compte de modification introuvable."); return nil; }
        [copy->_balances setObject:[[[_balances objectForKey:key] mutableCopy] autorelease] forKey:key];
        [copy->_recordsByAccount setObject:[[[_recordsByAccount objectForKey:key] mutableCopy] autorelease] forKey:key];
    }
    BOOL exact = YES;
    for (i = 0; i < [oldRecords count]; i++) {
        HBOperation *old = [oldRecords objectAtIndex:i];
        [[copy->_recordsByAccount objectForKey:[old accountKey]] removeObjectIdenticalTo:old];
        if (!HBDelta([copy->_balances objectForKey:[old accountKey]], old, YES)) exact = NO;
        NSString *transfer = [old objectForKey:@"kxfer"]; if ([transfer intValue] || ![transfer isEqualToString:@"0"]) [transfers addObject:transfer];
    }
    for (i = 0; i < [deleted count]; i++) {
        NSDictionary *old = [deleted objectAtIndex:i]; NSNumber *identifier = [old objectForKey:@"__index"];
        [copy->_records removeObjectIdenticalTo:old]; [copy->_recordLookup removeObjectForKey:identifier]; [copy->_recordSlots removeObjectForKey:identifier];
    }
    if ([deleted count]) {
        for (i = 0; i < [copy->_records count]; i++) [copy->_recordSlots setObject:[NSNumber numberWithUnsignedInt:i] forKey:[[copy->_records objectAtIndex:i] objectForKey:@"__index"]];
    }
    for (i = 0; i < [records count]; i++) {
        HBOperation *record = [records objectAtIndex:i]; NSNumber *identifier = [record objectForKey:@"__index"], *slot = [copy->_recordSlots objectForKey:identifier];
        if (slot) [copy->_records replaceObjectAtIndex:[slot unsignedIntValue] withObject:record];
        else {
            [copy->_recordSlots setObject:[NSNumber numberWithUnsignedInt:[copy->_records count]] forKey:identifier]; [copy->_records addObject:record];
            if (!copy->_createdIdentifier) copy->_createdIdentifier = [identifier retain];
        }
        [copy->_recordLookup setObject:record forKey:identifier];
        if ([record identifier] >= copy->_nextOperationID) copy->_nextOperationID = [record identifier] + 1;
        HBInsertRecord([copy->_recordsByAccount objectForKey:[record accountKey]], record);
        if (!HBDelta([copy->_balances objectForKey:[record accountKey]], record, NO)) exact = NO;
        NSString *transfer = [record objectForKey:@"kxfer"]; unsigned long transferKey = 0; HBParseUnsigned(transfer, 4294967295UL, &transferKey);
        if (transferKey) [transfers addObject:transfer]; if (transferKey > copy->_maxTransferKey) copy->_maxTransferKey = transferKey;
        NSMutableDictionary *changed = [[[_xmlChanges objectForKey:identifier] mutableCopy] autorelease];
        if (!changed) changed = [NSMutableDictionary dictionary];
        NSDictionary *before = [_recordLookup objectForKey:identifier]; NSEnumerator *fields = [record keyEnumerator]; NSString *field;
        while ((field = [fields nextObject])) if (![field isEqualToString:@"__index"] && ![[record objectForKey:field] isEqual:[before objectForKey:field]]) {
            id value = [record objectForKey:field];
            [changed setObject:[value isKindOfClass:[NSDecimalNumber class]] ? [value descriptionWithLocale:[NSDictionary dictionaryWithObject:@"." forKey:@"NSDecimalSeparator"]] : value forKey:field];
        }
        [copy->_xmlChanges setObject:changed forKey:identifier];
    }
    keys = [transfers objectEnumerator];
    while ((key = [keys nextObject])) {
        NSMutableArray *group = [NSMutableArray arrayWithArray:[_transferLookup objectForKey:key] ? [_transferLookup objectForKey:key] : [NSArray array]];
        for (i = 0; i < [oldRecords count]; i++) [group removeObjectIdenticalTo:[oldRecords objectAtIndex:i]];
        for (i = 0; i < [records count]; i++) if ([[[records objectAtIndex:i] objectForKey:@"kxfer"] isEqualToString:key]) [group addObject:[records objectAtIndex:i]];
        if ([group count]) [copy->_transferLookup setObject:group forKey:key]; else [copy->_transferLookup removeObjectForKey:key];
    }
    // Rare precision-loss cases fall back to the original summation order for affected accounts only.
    if (!exact) {
        keys = [accounts objectEnumerator];
        while ((key = [keys nextObject])) {
            NSDecimalNumber *initial = [[self accountWithKey:key] objectForKey:@"initial"];
            [copy->_balances setObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:initial, @"future", initial, @"cleared", initial, @"reconciled", nil] forKey:key];
        }
        for (i = 0; i < [copy->_records count]; i++) {
            HBOperation *record = [copy->_records objectAtIndex:i];
            if ([accounts containsObject:[record accountKey]] && !HBDelta([copy->_balances objectForKey:[record accountKey]], record, NO)) {
                HBStoreError(error, @"Solde hors precision decimale. Modification annulee."); return nil;
            }
        }
    }
    if (payee) {
        [copy->_payees setObject:payee forKey:[payee objectForKey:@"key"]]; [copy->_newPayees addObject:payee];
        [copy->_payeeNameLookup setObject:payee forKey:[[payee objectForKey:@"name"] lowercaseString]];
        HBParseUnsigned([payee objectForKey:@"key"], 4294967295UL, &copy->_maxPayeeKey);
    }
    copy->_generation++; [copy->_journalCommands addObject:command]; return copy;
}
- (HBWallet *)walletByApplyingCommand:(NSDictionary *)command error:(NSString **)error {
    if (error) *error = nil;
    if (![command isKindOfClass:[NSDictionary class]]) { HBStoreError(error, @"Commande de journal invalide."); return nil; }
    NSString *kind = [command objectForKey:@"kind"], *identifier = [command objectForKey:@"id"]; unsigned long value, version, generation;
    if (![kind isKindOfClass:[NSString class]] || ![identifier isKindOfClass:[NSString class]] || !HBParseUnsigned([command objectForKey:@"version"], 4294967295UL, &version)) {
        HBStoreError(error, @"Schema de journal invalide."); return nil;
    }
    if (!HBParseUnsigned([command objectForKey:@"generation"], 10000, &generation) || generation != _generation + 1) {
        HBStoreError(error, @"Ordre des commandes du journal invalide."); return nil;
    }
    HBOperation *record = nil;
    if (![identifier isEqualToString:@"new"]) {
        if (!HBParseUnsigned(identifier, 4294967295UL, &value)) { HBStoreError(error, @"Identifiant de journal invalide."); return nil; }
        record = (HBOperation *)[self recordWithIdentifier:[NSNumber numberWithUnsignedLong:value]];
        if (!record || [record version] != version) { HBStoreError(error, @"Journal incompatible avec la version de l'operation. Aucun changement applique."); return nil; }
    } else if (version) { HBStoreError(error, @"Version de creation invalide."); return nil; }
    NSDictionary *values = [command objectForKey:@"values"]; HBWallet *result = nil;
    if ([kind isEqualToString:@"update"] && [values isKindOfClass:[NSDictionary class]]) result = [self walletByUpdatingRecord:record values:values error:error];
    else if ([kind isEqualToString:@"status"] && record && [values isKindOfClass:[NSDictionary class]]) result = [self walletByChangingStatus:[values objectForKey:@"status"] record:record error:error];
    else if ([kind isEqualToString:@"delete"] && record) result = [self walletByDeletingRecord:record error:error];
    else if ([kind isEqualToString:@"normalize"] && [identifier isEqualToString:@"new"]) result = [self commitRecords:[NSArray array] deleting:[NSArray array] payee:nil command:command error:error];
    if (result && ![[[result journalCommands] lastObject] isEqual:command]) result = nil;
    if (!result && error && !*error) *error = @"Commande du journal refusee."; return result;
}
@end
