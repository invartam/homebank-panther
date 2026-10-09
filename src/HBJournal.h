#import "HBWalletStore.h"

NSDictionary *HBJournalRead(NSString *path, NSString *baseHash, NSString **error);
NSDictionary *HBJournalAppend(NSString *path, NSString *baseHash, NSArray *commands, NSDictionary *expectedState, NSString **error);
BOOL HBJournalClear(NSString *path, NSString *baseHash, unsigned int count, NSString **error);
HBWallet *HBRestoreWallet(NSString *path, NSDictionary **state, NSString **error);
HBWallet *HBCheckpointWallet(HBWallet *wallet, NSString *path, NSString **error);
