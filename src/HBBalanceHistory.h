#import "HBWallet.h"

typedef struct { int date; double balance; } HBBalancePoint;
typedef struct { int start, end; } HBHistoryRange;

/* Exact decimal balances are kept separately from the drawing-only double coordinates. */
@interface HBBalanceHistory : NSObject {
    HBBalancePoint *_points;
    unsigned int _count;
    NSArray *_balances, *_accounts, *_issues;
    int _start, _end, _today;
}
+ (NSArray *)accountsForWallet:(HBWallet *)wallet scope:(NSString *)scope currency:(NSString *)currency;
- (id)initWithWallet:(HBWallet *)wallet accounts:(NSArray *)accounts today:(int)today months:(int)months error:(NSString **)error;
- (int)start;
- (int)end;
- (int)today;
- (NSArray *)accounts;
- (NSArray *)issues;
- (NSDecimalNumber *)balanceAt:(int)date;
- (HBBalancePoint *)copyPointsFrom:(int)start to:(int)end limit:(unsigned int)limit count:(unsigned int *)count;
@end

HBHistoryRange HBHistoryClamp(HBHistoryRange range, HBBalanceHistory *history);
HBHistoryRange HBHistoryPreset(HBBalanceHistory *history, unsigned int preset);
HBHistoryRange HBHistoryZoom(HBHistoryRange range, HBBalanceHistory *history, double factor);
NSDecimalNumber *HBHistoryOverdraft(NSDictionary *account);
