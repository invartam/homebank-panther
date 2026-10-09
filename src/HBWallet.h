#import <Foundation/Foundation.h>

#define HB_MAX_FILE_BYTES (8 * 1024 * 1024)

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
typedef NSInteger HBIndex;
#else
typedef int HBIndex;
#endif

@interface HBWallet : NSObject {
    NSMutableArray *_accounts;
    NSMutableArray *_records;
    NSMutableDictionary *_currencies;
    NSMutableDictionary *_payees;
    NSMutableDictionary *_categories;
    NSMutableDictionary *_balances;
    NSMutableDictionary *_recordsByAccount;
    NSString *_error;
    NSString *_owner;
    NSString *_baseCurrency;
    unsigned int _depth;
    BOOL _seenRoot;
    NSData *_sourceData;
    NSMutableArray *_templates;
    NSMutableDictionary *_moneyFormatters;
    NSLock *_moneyLock;
    NSMutableDictionary *_accountLookup, *_recordLookup, *_recordSlots, *_transferLookup, *_payeeNameLookup;
    NSMutableArray *_journalCommands, *_newPayees;
    NSMutableDictionary *_xmlChanges;
    NSData *_serializedData;
    unsigned int _generation;
    unsigned long _nextOperationID, _maxPayeeKey, _maxTransferKey;
    BOOL _canEdit;
    NSNumber *_createdIdentifier;
}
+ (id)walletAtPath:(NSString *)path error:(NSString **)error;
- (id)initWithData:(NSData *)data error:(NSString **)error;
- (NSArray *)accounts;
- (NSString *)owner;
- (NSArray *)recordsForAccount:(NSDictionary *)account;
- (NSDictionary *)balancesForAccount:(NSDictionary *)account;
- (NSString *)payeeForRecord:(NSDictionary *)record;
- (NSString *)categoryForRecord:(NSDictionary *)record;
- (NSString *)formatAmount:(NSDecimalNumber *)amount account:(NSDictionary *)account;
- (NSData *)sourceData;
- (NSArray *)records;
- (NSArray *)templates;
- (NSArray *)payees;
- (NSArray *)categories;
- (NSDictionary *)accountWithKey:(NSString *)key;
- (NSString *)currencyKeyForAccount:(NSDictionary *)account;
- (unsigned int)fractionDigitsForAccount:(NSDictionary *)account;
@end

@interface HBWallet (Editing)
- (HBWallet *)walletForHomeBankExport:(NSString **)error;
- (HBWallet *)walletByUpdatingRecord:(NSDictionary *)record values:(NSDictionary *)values error:(NSString **)error;
- (HBWallet *)walletByChangingStatus:(NSString *)status record:(NSDictionary *)record error:(NSString **)error;
- (HBWallet *)walletByDeletingRecord:(NSDictionary *)record error:(NSString **)error;
- (NSDictionary *)counterpartForRecord:(NSDictionary *)record;
@end

@interface HBWallet (Calendar)
- (NSArray *)calendarEntriesFrom:(int)start to:(int)end today:(int)today account:(NSString *)accountKey includeClosed:(BOOL)includeClosed issues:(NSArray **)issues;
- (NSArray *)recurringEntriesForAccount:(NSString *)accountKey includeClosed:(BOOL)includeClosed issues:(NSArray **)issues;
- (NSArray *)totalsForEntries:(NSArray *)entries;
@end

NSCalendarDate *HBDateFromOrdinal(int ordinal);
NSCalendarDate *HBToday(void);
int HBOrdinalFromDate(NSCalendarDate *date);
int HBOrdinalFromFrenchDate(NSString *text);
NSDecimalNumber *HBMoneyFromText(NSString *text);
BOOL HBParseUnsigned(NSString *text, unsigned long maximum, unsigned long *value);
BOOL HBIsTransfer(NSDictionary *record);
BOOL HBWriteWallet(HBWallet *wallet, NSString *path, NSData *expectedData, NSString **error);
