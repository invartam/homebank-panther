#import <Cocoa/Cocoa.h>
#import "HBWallet.h"

@interface HBOperationEditor : NSObject {
    HBWallet *_wallet, *_result;
    NSDictionary *_record;
    NSPanel *_panel;
    NSPopUpButton *_type, *_account, *_destination, *_category, *_paymode, *_status, *_direction;
    NSTextField *_date, *_amount, *_destinationAmount, *_memo, *_number, *_error, *_amountTitle, *_destinationTitle;
    NSComboBox *_payee;
    BOOL _locked;
}
- (id)initWithWallet:(HBWallet *)wallet record:(NSDictionary *)record account:(NSDictionary *)account;
- (HBWallet *)run;
@end
