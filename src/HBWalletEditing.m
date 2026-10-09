#import "HBWallet.h"
#import "HBWalletStore.h"
#include "HBXML.h"
#include <libxml/tree.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>

static xmlDocPtr HBDocument(HBWallet *wallet) {
    NSData *data = [wallet baseSourceData];
    xmlDocPtr doc = HBXMLDocument([data bytes], [data length]);
    if (doc && xmlDocGetRootElement(doc)->ns != NULL) { xmlFreeDoc(doc); return NULL; }
    return doc;
}
static void HBProperty(xmlNodePtr node, NSString *key, NSString *value) {
    const char *bytes = [value UTF8String];
    /* Carry allocation/encoding failures on this private editing document, never save a partial mutation. */
    if (!bytes || !xmlSetProp(node, (const xmlChar *)[key UTF8String], (const xmlChar *)bytes)) node->doc->_private = (void *)1;
}
static BOOL HBBufferAppendRange(xmlBufferPtr buffer, const xmlChar *text, int length) {
    int before = xmlBufferLength(buffer);
    if (before < 0 || length < 0 || before > HB_MAX_FILE_BYTES - length) return NO;
    /* xmlBufferAdd returned void before 2.6; verify growth, not its return type. */
    xmlBufferAdd(buffer, text, length);
    return xmlBufferLength(buffer) == before + length;
}
static BOOL HBBufferAppend(xmlBufferPtr buffer, const xmlChar *text) {
    return HBBufferAppendRange(buffer, text, xmlStrlen(text));
}
static BOOL HBAttributeValue(xmlBufferPtr buffer, xmlDocPtr doc, const xmlChar *prefix, const xmlChar *name, const xmlChar *value) {
    xmlChar *escaped = xmlEncodeSpecialChars(doc, value ? value : BAD_CAST "");
    if (!escaped) return NO;
    BOOL ok = HBBufferAppend(buffer, BAD_CAST " ");
    if (ok && prefix) ok = HBBufferAppend(buffer, prefix) && HBBufferAppend(buffer, BAD_CAST ":");
    if (ok) ok = HBBufferAppend(buffer, name) && HBBufferAppend(buffer, BAD_CAST "=\"");
    const xmlChar *start = escaped, *cursor;
    /* Attribute whitespace must remain numeric references, not normalize to spaces. */
    for (cursor = escaped; ok && *cursor; cursor++) {
        const xmlChar *entity = *cursor == '\n' ? BAD_CAST "&#10;" : *cursor == '\r' ? BAD_CAST "&#13;" : *cursor == '\t' ? BAD_CAST "&#9;" : NULL;
        if (entity) { ok = HBBufferAppendRange(buffer, start, (int)(cursor - start)) && HBBufferAppend(buffer, entity); start = cursor + 1; }
    }
    if (ok) ok = HBBufferAppendRange(buffer, start, (int)(cursor - start)) && HBBufferAppend(buffer, BAD_CAST "\"");
    xmlFree(escaped); return ok;
}
static BOOL HBAttributeDump(xmlBufferPtr buffer, xmlDocPtr doc, xmlAttrPtr attribute) {
    xmlChar *value = attribute->children ? xmlNodeListGetString(doc, attribute->children, 1) : xmlStrdup(BAD_CAST "");
    if (!value) return NO;
    BOOL ok = HBAttributeValue(buffer, doc, attribute->ns ? attribute->ns->prefix : NULL, attribute->name, value);
    xmlFree(value); return ok;
}
static BOOL HBRootDump(xmlBufferPtr buffer, xmlDocPtr doc, xmlNodePtr root, xmlAttrPtr version) {
    xmlAttrPtr attribute; xmlNsPtr ns; xmlNodePtr child;
    if (!HBBufferAppend(buffer, BAD_CAST "<homebank") || !HBAttributeDump(buffer, doc, version)) return NO;
    xmlAttrPtr dataVersion = xmlHasProp(root, BAD_CAST "d");
    if (dataVersion && dataVersion->ns) dataVersion = NULL;
    if (dataVersion && !HBAttributeDump(buffer, doc, dataVersion)) return NO;
    /* libxml normally emits xmlns before attributes; HomeBank needs v first. */
    for (ns = root->nsDef; ns; ns = ns->next) {
        if (!HBAttributeValue(buffer, doc, ns->prefix ? BAD_CAST "xmlns" : NULL, ns->prefix ? ns->prefix : BAD_CAST "xmlns", ns->href)) return NO;
    }
    for (attribute = root->properties; attribute; attribute = attribute->next)
        if (attribute != version && attribute != dataVersion && !HBAttributeDump(buffer, doc, attribute)) return NO;
    if (!root->children) return HBBufferAppend(buffer, BAD_CAST "/>");
    if (!HBBufferAppend(buffer, BAD_CAST ">")) return NO;
    for (child = root->children; child; child = child->next)
        if (xmlNodeDump(buffer, doc, child, 0, 0) < 0 || xmlBufferLength(buffer) > HB_MAX_FILE_BYTES) return NO;
    return HBBufferAppend(buffer, BAD_CAST "</homebank>");
}
static HBWallet *HBResult(xmlDocPtr doc, NSString **error) {
    if (doc->_private) { xmlFreeDoc(doc); if (error) *error = @"Modification XML incomplete : memoire ou texte invalide."; return nil; }
    xmlNodePtr root = xmlDocGetRootElement(doc), node;
    xmlAttrPtr version = root ? xmlHasProp(root, BAD_CAST "v") : NULL;
    if (!version || version->ns) {
        xmlFreeDoc(doc); if (error) *error = @"Version HomeBank absente : export compatible refuse, sans attribuer de format arbitraire."; return nil;
    }
    /* Original HomeBank probes only the first 50 bytes for <homebank v=. */
    xmlBufferPtr buffer = xmlBufferCreate(); BOOL ok = buffer != NULL; unsigned int rootOffset = 0;
    /* Dump document children as UTF-8, without adding an XML declaration. */
    for (node = doc->children; ok && node; node = node->next) {
        if (node == root) rootOffset = xmlBufferLength(buffer);
        ok = (node == root ? HBRootDump(buffer, doc, root, version) : xmlNodeDump(buffer, doc, node, 0, 0) >= 0) && xmlBufferLength(buffer) <= HB_MAX_FILE_BYTES;
    }
    const char signature[] = "<homebank v="; unsigned int i, limit = ok && xmlBufferLength(buffer) < 50 ? xmlBufferLength(buffer) : 50;
    unsigned int detected = 50;
    if (ok) for (i = 0; i + sizeof(signature) - 1 <= limit; i++) {
        if (memcmp(xmlBufferContent(buffer) + i, signature, sizeof(signature) - 1) == 0) { detected = i; break; }
    }
    NSData *data = ok && detected < 50 && detected == rootOffset ? [NSData dataWithBytes:xmlBufferContent(buffer) length:xmlBufferLength(buffer)] : nil;
    if (buffer) xmlBufferFree(buffer);
    xmlFreeDoc(doc);
    if (!data) { if (error) *error = @"Export incompatible ou trop volumineux. Le prologue ne permet pas la detection HomeBank ; aucune donnee n'a ete supprimee."; return nil; }
    return [[[HBWallet alloc] initWithData:data error:error] autorelease];
}
static NSString *HBDecimalText(NSDecimalNumber *number) { return [number descriptionWithLocale:[NSDictionary dictionaryWithObject:@"." forKey:@"NSDecimalSeparator"]]; }
static NSDecimalNumber *HBNegative(NSDecimalNumber *number) { return [number decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]]; }
static BOOL HBError(NSString **error, NSString *message) { if (error) *error = message; return NO; }

@implementation HBWallet (Editing)
- (HBWallet *)walletForHomeBankExport:(NSString **)error {
    if (error) *error = nil;
    xmlDocPtr doc = HBDocument(self);
    if (!doc) { HBError(error, @"Impossible de preparer le fichier XML."); return nil; }
    NSMutableDictionary *nodes = [NSMutableDictionary dictionary]; xmlNodePtr node, next; unsigned long identifier = 0;
    for (node = xmlDocGetRootElement(doc)->children; node; node = next) {
        next = node->next;
        if (node->type != XML_ELEMENT_NODE || node->ns || !xmlStrEqual(node->name, BAD_CAST "ope")) continue;
        NSNumber *key = [NSNumber numberWithUnsignedLong:identifier++];
        if (![self recordWithIdentifier:key]) { xmlUnlinkNode(node); xmlFreeNode(node); }
        else [nodes setObject:[NSValue valueWithPointer:node] forKey:key];
    }
    NSArray *payees = [self newPayees]; unsigned int i;
    for (i = 0; i < [payees count]; i++) {
        node = xmlNewChild(xmlDocGetRootElement(doc), NULL, BAD_CAST "pay", NULL);
        if (!node) { xmlFreeDoc(doc); HBError(error, @"Memoire insuffisante pour exporter le tiers."); return nil; }
        HBProperty(node, @"key", [[payees objectAtIndex:i] objectForKey:@"key"]); HBProperty(node, @"name", [[payees objectAtIndex:i] objectForKey:@"name"]);
    }
    NSArray *records = [self records];
    for (i = 0; i < [records count]; i++) {
        NSNumber *key = [[records objectAtIndex:i] objectForKey:@"__index"]; NSDictionary *changes = [[self xmlChanges] objectForKey:key];
        if (!changes) continue;
        node = [[nodes objectForKey:key] pointerValue];
        if (!node) node = xmlNewChild(xmlDocGetRootElement(doc), NULL, BAD_CAST "ope", NULL);
        if (!node) { xmlFreeDoc(doc); HBError(error, @"Memoire insuffisante pour exporter l'operation."); return nil; }
        NSEnumerator *fields = [changes keyEnumerator]; NSString *field;
        while ((field = [fields nextObject])) HBProperty(node, field, [changes objectForKey:field]);
    }
    return HBResult(doc, error);
}
- (NSDictionary *)counterpartForRecord:(NSDictionary *)record {
    NSString *key = [record objectForKey:@"kxfer"];
    NSDictionary *result = nil;
    unsigned int count = 0, i;
    if (![key length] || [key isEqualToString:@"0"]) return nil;
    NSArray *group = [_transferLookup objectForKey:key]; count = [group count];
    for (i = 0; i < count; i++) if ([group objectAtIndex:i] != record) result = [group objectAtIndex:i];
    if (count != 2 || !result || !HBIsTransfer(result)
        || ![[result objectForKey:@"account"] isEqualToString:[record objectForKey:@"dst_account"]]
        || ![[result objectForKey:@"dst_account"] isEqualToString:[record objectForKey:@"account"]]) return nil;
    NSDecimalNumber *a = [record objectForKey:@"amount"], *b = [result objectForKey:@"amount"];
    if ([a compare:[NSDecimalNumber zero]] == [b compare:[NSDecimalNumber zero]]) return nil;
    NSDictionary *source = [self accountWithKey:[record objectForKey:@"account"]], *target = [self accountWithKey:[result objectForKey:@"account"]];
    if ([[self currencyKeyForAccount:source] isEqualToString:[self currencyKeyForAccount:target]] && ![HBNegative(a) isEqualToNumber:b]) return nil;
    return result;
}
- (HBWallet *)walletByUpdatingRecord:(NSDictionary *)record values:(NSDictionary *)values error:(NSString **)error {
    if (error) *error = nil;
    if (![self canEdit] || (record && [self recordWithIdentifier:[record objectForKey:@"__index"]] != record)) { HBError(error, @"Operation modifiee ou format non editable."); return nil; }
    NSArray *fields = [NSArray arrayWithObjects:@"type", @"account", @"date", @"amount", @"status", @"category", @"paymode", @"payeeName", @"memo", @"number", @"destination", @"destinationAmount", @"direction", nil];
    unsigned int i;
    for (i = 0; i < [fields count]; i++) {
        id value = [values objectForKey:[fields objectAtIndex:i]];
        if (value && (![value isKindOfClass:[NSString class]] || [value length] > 16384 || ![value UTF8String])) { HBError(error, @"Champ invalide ou trop long."); return nil; }
    }
    NSString *type = [values objectForKey:@"type"], *accountKey = [values objectForKey:@"account"];
    NSArray *categories = [self categories];
    BOOL transfer = [type isEqualToString:@"transfer"], income = [type isEqualToString:@"income"];
    NSDictionary *account = [self accountWithKey:accountKey], *target = transfer ? [self accountWithKey:[values objectForKey:@"destination"]] : nil;
    NSDictionary *counterpart = record && HBIsTransfer(record) ? [self counterpartForRecord:record] : nil;
    unsigned long status, category, paymode;
    int date = HBOrdinalFromFrenchDate([values objectForKey:@"date"]);
    NSDecimalNumber *magnitude = HBMoneyFromText([values objectForKey:@"amount"]);
    if ((!transfer && !income && ![type isEqualToString:@"expense"]) || !account || !date || !magnitude || [magnitude compare:[NSDecimalNumber zero]] != NSOrderedDescending
        || !HBParseUnsigned([values objectForKey:@"status"], 3, &status) || !HBParseUnsigned([values objectForKey:@"category"], 4294967295UL, &category)
        || !HBParseUnsigned([values objectForKey:@"paymode"], 12, &paymode) || paymode == 5) {
        HBError(error, @"Verifier le compte, la date (JJ/MM/AAAA), le montant positif, le statut et le paiement."); return nil;
    }
    if (([[account objectForKey:@"flags"] intValue] & 2) && (!record || ![accountKey isEqualToString:[record objectForKey:@"account"]])) { HBError(error, @"Le compte est clos."); return nil; }
    if (record && HBIsTransfer(record) && !counterpart) { HBError(error, @"Virement incomplet ou incoherent : modification refusee."); return nil; }
    if (record && HBIsTransfer(record) != transfer) { HBError(error, @"Le type d'un virement existant ne peut pas etre converti."); return nil; }
    if (category) {
        BOOL found = NO;
        for (i = 0; i < [categories count]; i++) if ([[[categories objectAtIndex:i] objectForKey:@"key"] isEqualToString:[values objectForKey:@"category"]]) found = YES;
        if (!found) { HBError(error, @"Categorie introuvable."); return nil; }
    }
    NSString *direction = [values objectForKey:@"direction"];
    if (transfer && (!target || target == account || (([[target objectForKey:@"flags"] intValue] & 2)
        && (!record || ![[target objectForKey:@"key"] isEqualToString:[record objectForKey:@"dst_account"]]))
        || (![direction isEqualToString:@"in"] && ![direction isEqualToString:@"out"]))) { HBError(error, @"Choisir un autre compte ouvert et le sens du virement."); return nil; }
    NSDecimalNumber *amount = income || (transfer && [direction isEqualToString:@"in"]) ? magnitude : HBNegative(magnitude);
    NSDecimalNumber *otherAmount = nil;
    BOOL differentCurrency = transfer && ![[self currencyKeyForAccount:account] isEqualToString:[self currencyKeyForAccount:target]];
    if (transfer) {
        NSDecimalNumber *otherMagnitude = differentCurrency ? HBMoneyFromText([values objectForKey:@"destinationAmount"]) : magnitude;
        if (!otherMagnitude || [otherMagnitude compare:[NSDecimalNumber zero]] != NSOrderedDescending) { HBError(error, @"Montant du compte lie invalide."); return nil; }
        otherAmount = [amount compare:[NSDecimalNumber zero]] == NSOrderedAscending ? otherMagnitude : HBNegative(otherMagnitude);
    }
    NSDecimalNumberHandler *rounding = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain scale:[self fractionDigitsForAccount:account]
        raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO];
    BOOL unchangedAmount = record && [accountKey isEqualToString:[record objectForKey:@"account"]] && [amount isEqualToNumber:[record objectForKey:@"amount"]];
    if (!unchangedAmount && ![[amount decimalNumberByRoundingAccordingToBehavior:rounding] isEqualToNumber:amount]) { HBError(error, @"Trop de decimales pour la devise du compte."); return nil; }
    if (otherAmount) {
        rounding = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain scale:[self fractionDigitsForAccount:target]
            raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO];
        BOOL unchangedOther = counterpart && [[target objectForKey:@"key"] isEqualToString:[counterpart objectForKey:@"account"]] && [otherAmount isEqualToNumber:[counterpart objectForKey:@"amount"]];
        if (!unchangedOther && ![[otherAmount decimalNumberByRoundingAccordingToBehavior:rounding] isEqualToNumber:otherAmount]) { HBError(error, @"Trop de decimales pour le compte lie."); return nil; }
    }
    unsigned long originalCategory = 0;
    HBParseUnsigned([record objectForKey:@"category"], 4294967295UL, &originalCategory);
    BOOL structural = record && (![amount isEqualToNumber:[record objectForKey:@"amount"]] || date != [[record objectForKey:@"date"] intValue]
        || ![accountKey isEqualToString:[record objectForKey:@"account"]] || category != originalCategory
        || (!transfer && paymode != [[record objectForKey:@"paymode"] intValue]) || (transfer && (![otherAmount isEqualToNumber:[counterpart objectForKey:@"amount"]]
            || ![[target objectForKey:@"key"] isEqualToString:[record objectForKey:@"dst_account"]])));
    if (structural && ([[record objectForKey:@"st"] intValue] == 2 || [[counterpart objectForKey:@"st"] intValue] == 2
        || [record objectForKey:@"scat"] || [record objectForKey:@"samt"])) {
        HBError(error, @"Operation rapprochee ou ventilee : seuls les textes et le statut sont editables. Retirer le rapprochement avant de changer les montants."); return nil;
    }
    unsigned long payeeKey = 0, transferKey = record ? strtoul([[record objectForKey:@"kxfer"] UTF8String], NULL, 10) : 0;
    NSString *payeeName = [values objectForKey:@"payeeName"] ? [[values objectForKey:@"payeeName"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
    NSDictionary *originalPayee = record ? [_payees objectForKey:[record objectForKey:@"payee"]] : nil;
    if (record && ![[record objectForKey:@"payee"] isEqualToString:@"0"] && !originalPayee && ![payeeName length]) {
        HBError(error, @"Tiers d'origine introuvable : choisir un tiers."); return nil;
    }
    NSDictionary *matched = [payeeName length] ? [_payeeNameLookup objectForKey:[payeeName lowercaseString]] : nil;
    if (matched) HBParseUnsigned([matched objectForKey:@"key"], 4294967295UL, &payeeKey);
    if (originalPayee && (([payeeName length] && [[originalPayee objectForKey:@"name"] compare:payeeName options:NSCaseInsensitiveSearch] == NSOrderedSame)
        || (![payeeName length] && (![[originalPayee objectForKey:@"name"] length] || [[originalPayee objectForKey:@"name"] isEqualToString:@"(null)"]))))
        HBParseUnsigned([originalPayee objectForKey:@"key"], 4294967295UL, &payeeKey);
    NSDictionary *newPayee = nil;
    if ([payeeName length] && !payeeKey) {
        if (_maxPayeeKey == 4294967295UL) { HBError(error, @"Plus d'identifiants de tiers disponibles."); return nil; }
        payeeKey = _maxPayeeKey + 1;
        newPayee = [NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%lu", payeeKey], @"key", payeeName, @"name", nil];
    }
    if (!record && (_nextOperationID >= 4294967295UL || (transfer && _nextOperationID >= 4294967294UL))) {
        HBError(error, @"Plus d'identifiants internes disponibles. Consolider le fichier XML."); return nil;
    }
    if (transfer && !record) {
        if (_maxTransferKey == 4294967295UL) { HBError(error, @"Plus d'identifiants de virements disponibles."); return nil; }
        transferKey = _maxTransferKey + 1;
    }
    NSMutableDictionary *attributes = record ? [NSMutableDictionary dictionaryWithDictionary:record] : [NSMutableDictionary dictionary];
    NSMutableDictionary *linked = transfer ? (counterpart ? [NSMutableDictionary dictionaryWithDictionary:counterpart] : [NSMutableDictionary dictionary]) : nil;
    unsigned long flags = record ? strtoul([[record objectForKey:@"flags"] UTF8String], NULL, 10) : 0;
    flags = (flags & ~(2UL | 8UL | 16UL)) | (transfer ? 8UL : income ? 2UL : 0UL);
    NSArray *sharedKeys = [NSArray arrayWithObjects:@"date", @"payee", @"category", @"wording", @"info", nil];
    NSArray *sharedValues = [NSArray arrayWithObjects:[NSString stringWithFormat:@"%d", date], [NSString stringWithFormat:@"%lu", payeeKey],
        [NSString stringWithFormat:@"%lu", category], [values objectForKey:@"memo"] ? [values objectForKey:@"memo"] : @"",
        [values objectForKey:@"number"] ? [values objectForKey:@"number"] : @"", nil];
    for (i = 0; i < [sharedKeys count]; i++) {
        [attributes setObject:[sharedValues objectAtIndex:i] forKey:[sharedKeys objectAtIndex:i]];
        if (linked) [linked setObject:[sharedValues objectAtIndex:i] forKey:[sharedKeys objectAtIndex:i]];
    }
    [attributes setObject:accountKey forKey:@"account"]; [attributes setObject:amount forKey:@"amount"];
    [attributes setObject:[NSString stringWithFormat:@"%lu", flags] forKey:@"flags"];
    [attributes setObject:[NSString stringWithFormat:@"%lu", transfer ? 0UL : paymode] forKey:@"paymode"];
    [attributes setObject:[NSString stringWithFormat:@"%lu", status] forKey:@"st"];
    [attributes setObject:transfer ? [target objectForKey:@"key"] : @"0" forKey:@"dst_account"];
    [attributes setObject:[NSString stringWithFormat:@"%lu", transfer ? transferKey : 0UL] forKey:@"kxfer"];
    [attributes setObject:differentCurrency ? HBDecimalText(otherAmount) : @"0" forKey:@"damt"];
    NSMutableArray *changed = [NSMutableArray array];
    [changed addObject:[[[HBOperation alloc] initWithAttributes:attributes identifier:record ? [(HBOperation *)record identifier] : _nextOperationID version:_generation + 1] autorelease]];
    if (linked) {
        unsigned long linkedFlags = counterpart ? strtoul([[counterpart objectForKey:@"flags"] UTF8String], NULL, 10) : 0;
        [linked setObject:[target objectForKey:@"key"] forKey:@"account"]; [linked setObject:accountKey forKey:@"dst_account"];
        [linked setObject:otherAmount forKey:@"amount"]; [linked setObject:differentCurrency ? HBDecimalText(amount) : @"0" forKey:@"damt"];
        [linked setObject:[NSString stringWithFormat:@"%lu", transferKey] forKey:@"kxfer"];
        [linked setObject:[NSString stringWithFormat:@"%lu", (linkedFlags & ~(2UL | 16UL)) | 8UL] forKey:@"flags"];
        [linked setObject:@"0" forKey:@"paymode"];
        [linked setObject:status == 3 ? @"3" : counterpart && [[counterpart objectForKey:@"st"] intValue] != 3 ? [counterpart objectForKey:@"st"] : @"0" forKey:@"st"];
        [changed addObject:[[[HBOperation alloc] initWithAttributes:linked identifier:counterpart ? [(HBOperation *)counterpart identifier] : _nextOperationID + 1 version:_generation + 1] autorelease]];
    }
    return [self commitRecords:changed deleting:[NSArray array] payee:newPayee command:[self command:@"update" record:record values:values] error:error];
}
- (HBWallet *)walletByChangingStatus:(NSString *)status record:(NSDictionary *)record error:(NSString **)error {
    unsigned long value;
    if (error) *error = nil;
    if (![self canEdit] || !record || [self recordWithIdentifier:[record objectForKey:@"__index"]] != record || !HBParseUnsigned(status, 3, &value)) { HBError(error, @"Operation ou statut invalide."); return nil; }
    NSDictionary *other = HBIsTransfer(record) ? [self counterpartForRecord:record] : nil;
    if (value == 3 && HBIsTransfer(record) && !other) { HBError(error, @"Virement incoherent : annulation refusee."); return nil; }
    NSMutableArray *changed = [NSMutableArray array]; NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:record];
    [attributes setObject:[NSString stringWithFormat:@"%lu", value] forKey:@"st"];
    [changed addObject:[[[HBOperation alloc] initWithAttributes:attributes identifier:[(HBOperation *)record identifier] version:_generation + 1] autorelease]];
    if ((value == 3 && other) || (value != 3 && [[record objectForKey:@"st"] intValue] == 3 && other && [[other objectForKey:@"st"] intValue] == 3)) {
        attributes = [NSMutableDictionary dictionaryWithDictionary:other]; [attributes setObject:value == 3 ? @"3" : @"0" forKey:@"st"];
        [changed addObject:[[[HBOperation alloc] initWithAttributes:attributes identifier:[(HBOperation *)other identifier] version:_generation + 1] autorelease]];
    }
    return [self commitRecords:changed deleting:[NSArray array] payee:nil command:[self command:@"status" record:record values:[NSDictionary dictionaryWithObject:status forKey:@"status"]] error:error];
}
- (HBWallet *)walletByDeletingRecord:(NSDictionary *)record error:(NSString **)error {
    if (error) *error = nil;
    if (![self canEdit] || !record || [self recordWithIdentifier:[record objectForKey:@"__index"]] != record) { HBError(error, @"Operation introuvable."); return nil; }
    NSDictionary *other = HBIsTransfer(record) ? [self counterpartForRecord:record] : nil;
    if (HBIsTransfer(record) && !other) { HBError(error, @"Virement incoherent : suppression refusee."); return nil; }
    if ([[record objectForKey:@"st"] intValue] == 2 || [[other objectForKey:@"st"] intValue] == 2) { HBError(error, @"Retirer le rapprochement avant de supprimer cette operation."); return nil; }
    return [self commitRecords:[NSArray array] deleting:other ? [NSArray arrayWithObjects:record, other, nil] : [NSArray arrayWithObject:record]
        payee:nil command:[self command:@"delete" record:record values:nil] error:error];
}
@end

static BOOL HBWriteBytes(int fd, NSData *data) {
    const char *bytes = [data bytes]; unsigned int offset = 0;
    while (offset < [data length]) {
        ssize_t written = write(fd, bytes + offset, [data length] - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return NO;
        offset += written;
    }
    return fsync(fd) == 0;
}
static BOOL HBFileMatchesData(NSString *path, NSData *expected) {
    struct stat before, opened, after;
    const char *name = [path fileSystemRepresentation], *bytes = [expected bytes];
    if (!expected || lstat(name, &before) != 0 || !S_ISREG(before.st_mode) || before.st_size != (off_t)[expected length]) return NO;
    int flags = O_RDONLY;
#ifdef O_NOFOLLOW
    flags |= O_NOFOLLOW;
#endif
    int fd = open(name, flags);
    if (fd < 0) return NO;
    BOOL valid = fstat(fd, &opened) == 0 && S_ISREG(opened.st_mode) && opened.st_dev == before.st_dev &&
        opened.st_ino == before.st_ino && opened.st_size == before.st_size;
    unsigned long offset = 0, length = [expected length]; char buffer[65536];
    // The baseline was already imported: compare bytes without rebuilding its model twice.
    while (valid && offset < length) {
        unsigned long remaining = length - offset;
        ssize_t count = read(fd, buffer, remaining < sizeof(buffer) ? remaining : sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0 || memcmp(buffer, bytes + offset, (size_t)count) != 0) valid = NO;
        else offset += count;
    }
    if (valid) {
        ssize_t count;
        do { count = read(fd, buffer, 1); } while (count < 0 && errno == EINTR);
        valid = count == 0 && lstat(name, &after) == 0 && S_ISREG(after.st_mode) &&
            after.st_dev == opened.st_dev && after.st_ino == opened.st_ino && after.st_size == opened.st_size;
    }
    if (close(fd) != 0) valid = NO;
    return valid;
}
BOOL HBWriteWallet(HBWallet *wallet, NSString *path, NSData *expectedData, NSString **error) {
    if (error) *error = nil;
    NSString *parseError = nil;
    if (!wallet || ![[[HBWallet alloc] initWithData:[wallet sourceData] error:&parseError] autorelease]) return HBError(error, @"Portefeuille invalide : sauvegarde refusee.");
    NSString *lockPath = [path stringByAppendingString:@".panther-lock"];
    int lock = open([lockPath fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (lock < 0) return HBError(error, @"Fichier verrouille ou dossier non accessible.");
    close(lock);
    struct stat info;
    BOOL exists = lstat([path fileSystemRepresentation], &info) == 0;
    BOOL valid = expectedData ? exists && S_ISREG(info.st_mode) && info.st_size <= HB_MAX_FILE_BYTES : !exists && errno == ENOENT;
    if (valid && expectedData) valid = HBFileMatchesData(path, expectedData);
    if (!valid) { unlink([lockPath fileSystemRepresentation]); return HBError(error, @"Le fichier a change, est un lien, ou existe deja. Recharger ou exporter vers un autre nom."); }
    char *temp = strdup([[path stringByAppendingString:@".tmp-XXXXXX"] fileSystemRepresentation]);
    if (!temp) { unlink([lockPath fileSystemRepresentation]); return HBError(error, @"Memoire insuffisante pour enregistrer."); }
    int fd = mkstemp(temp);
    BOOL success = fd >= 0 && HBWriteBytes(fd, [wallet sourceData]);
    if (fd >= 0 && close(fd) != 0) success = NO;
    if (success && expectedData) {
        char *backup = strdup([[path stringByAppendingString:@".backup-XXXXXX"] fileSystemRepresentation]);
        int backupFD = backup ? mkstemp(backup) : -1;
        success = backupFD >= 0 && HBWriteBytes(backupFD, expectedData);
        if (backupFD >= 0 && close(backupFD) != 0) success = NO;
        if (!success && backup) unlink(backup);
        free(backup);
        success = success && HBFileMatchesData(path, expectedData);
        if (success) success = rename(temp, [path fileSystemRepresentation]) == 0;
    } else if (success) success = link(temp, [path fileSystemRepresentation]) == 0;
    unlink(temp); free(temp); unlink([lockPath fileSystemRepresentation]);
    return success ? YES : HBError(error, @"Sauvegarde refusee ou interrompue. Le fichier original est conserve ; les modifications restent en memoire.");
}
