#import "HBWallet.h"
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
typedef NSUInteger HBCollectionCount;
#else
typedef unsigned int HBCollectionCount;
#endif

/* Immutable dictionary adapters keep existing Cocoa views compatible with typed records. */
@interface HBOperation : NSDictionary {
    NSDictionary *_attributes;
    unsigned long _identifier;
    unsigned int _version, _date, _status;
    NSString *_accountKey;
    NSDecimalNumber *_amount;
}
- (id)initWithAttributes:(NSDictionary *)attributes identifier:(unsigned long)identifier version:(unsigned int)version;
- (unsigned long)identifier;
- (unsigned int)version;
- (unsigned int)date;
- (unsigned int)status;
- (NSString *)accountKey;
- (NSDecimalNumber *)amount;
@end

@interface HBAccount : NSDictionary {
    NSDictionary *_attributes;
    NSString *_key;
    NSDecimalNumber *_initial;
}
- (id)initWithAttributes:(NSDictionary *)attributes;
- (NSString *)key;
- (NSDecimalNumber *)initial;
@end

@interface HBWalletStore : HBWallet
@end

@interface HBWallet (WorkingStore)
- (HBWalletStore *)workingCopy;
- (HBWallet *)commitRecords:(NSArray *)records deleting:(NSArray *)deleted payee:(NSDictionary *)payee command:(NSDictionary *)command error:(NSString **)error;
- (NSDictionary *)command:(NSString *)kind record:(NSDictionary *)record values:(NSDictionary *)values;
- (HBWallet *)walletByApplyingCommand:(NSDictionary *)command error:(NSString **)error;
- (NSArray *)journalCommands;
- (unsigned int)generation;
- (NSData *)baseSourceData;
- (NSDictionary *)xmlChanges;
- (NSArray *)newPayees;
- (NSDictionary *)recordWithIdentifier:(NSNumber *)identifier;
- (NSNumber *)createdIdentifier;
- (BOOL)canEdit;
@end
