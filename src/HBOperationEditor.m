#import "HBOperationEditor.h"

@interface HBOperationEditor (PrivateMethods)
- (void)updateType:(id)sender;
@end

static NSTextField *HBEditorLabel(NSView *view, NSString *title, NSRect frame) {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setStringValue:title]; [label setEditable:NO]; [label setSelectable:NO];
    [label setBezeled:NO]; [label setDrawsBackground:NO]; [label setFont:[NSFont systemFontOfSize:12]];
    [view addSubview:label]; return label;
}
static NSTextField *HBInput(NSView *view, NSString *text, NSRect frame) {
    NSTextField *input = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [input setStringValue:text ? text : @""]; [view addSubview:input]; return input;
}
static NSPopUpButton *HBPopup(NSView *view, NSArray *titles, NSRect frame) {
    NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO] autorelease];
    if (titles) [popup addItemsWithTitles:titles]; [view addSubview:popup]; return popup;
}
static NSString *HBChoice(NSPopUpButton *popup) { return [[popup selectedItem] representedObject]; }
static void HBAddChoice(NSPopUpButton *popup, NSString *title, NSString *key) {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""] autorelease];
    [item setRepresentedObject:key]; [[popup menu] addItem:item];
}
static void HBSelectKey(NSPopUpButton *popup, NSString *key) {
    unsigned int i;
    for (i = 0; i < [[popup itemArray] count]; i++) if ([[[[popup itemArray] objectAtIndex:i] representedObject] isEqualToString:key]) { [popup selectItemAtIndex:i]; return; }
}
static NSString *HBPositiveText(NSDecimalNumber *number) {
    if ([number compare:[NSDecimalNumber zero]] == NSOrderedAscending) number = [number decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]];
    return number ? [number descriptionWithLocale:[NSDictionary dictionaryWithObject:@"," forKey:@"NSDecimalSeparator"]] : @"";
}
static HBIndex HBNameOrder(id a, id b, void *context) {
    NSString *left = [a objectForKey:@"name"] ? [a objectForKey:@"name"] : @"";
    NSString *right = [b objectForKey:@"name"] ? [b objectForKey:@"name"] : @"";
    return [left compare:right options:NSCaseInsensitiveSearch];
}
static HBIndex HBCategoryOrder(id a, id b, void *context) {
    HBWallet *wallet = (HBWallet *)context;
    NSString *left = [wallet categoryForRecord:[NSDictionary dictionaryWithObject:[a objectForKey:@"key"] forKey:@"category"]];
    NSString *right = [wallet categoryForRecord:[NSDictionary dictionaryWithObject:[b objectForKey:@"key"] forKey:@"category"]];
    return [left compare:right options:NSCaseInsensitiveSearch];
}

@implementation HBOperationEditor
- (id)initWithWallet:(HBWallet *)wallet record:(NSDictionary *)record account:(NSDictionary *)account {
    self = [super init]; if (!self) return nil;
    _wallet = [wallet retain]; _record = [record retain];
    NSDecimalNumber *recordAmount = [record objectForKey:@"amount"];
    NSDictionary *other = [wallet counterpartForRecord:record];
    _locked = record && ([[record objectForKey:@"st"] intValue] == 2 || [[other objectForKey:@"st"] intValue] == 2 || [record objectForKey:@"scat"] || [record objectForKey:@"samt"]);
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 680, 474) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [_panel setTitle:record ? @"Modifier l'operation" : @"Nouvelle operation"]; [_panel center];
    NSView *view = [_panel contentView]; unsigned int i;
    HBEditorLabel(view, @"Type", NSMakeRect(16, 432, 110, 20));
    _type = HBPopup(view, [NSArray arrayWithObjects:@"Depense", @"Revenu", @"Virement interne", nil], NSMakeRect(140, 429, 210, 26));
    [_type selectItemAtIndex:HBIsTransfer(record) ? 2 : [recordAmount compare:[NSDecimalNumber zero]] == NSOrderedDescending ? 1 : 0];
    [_type setEnabled:!_locked && !HBIsTransfer(record)]; [_type setTarget:self]; [_type setAction:@selector(updateType:)];
    _direction = HBPopup(view, [NSArray arrayWithObjects:@"Sortant", @"Entrant", nil], NSMakeRect(480, 429, 180, 26));
    [_direction selectItemAtIndex:record && [recordAmount compare:[NSDecimalNumber zero]] == NSOrderedDescending ? 1 : 0];
    HBEditorLabel(view, @"Compte", NSMakeRect(16, 394, 110, 20)); _account = HBPopup(view, nil, NSMakeRect(140, 391, 520, 26));
    HBEditorLabel(view, @"Compte lie", NSMakeRect(16, 356, 110, 20)); _destination = HBPopup(view, nil, NSMakeRect(140, 353, 520, 26));
    for (i = 0; i < [[wallet accounts] count]; i++) {
        NSDictionary *item = [[wallet accounts] objectAtIndex:i];
        BOOL closed = ([[item objectForKey:@"flags"] intValue] & 2) != 0;
        NSString *key = [item objectForKey:@"key"];
        if (!closed || [key isEqualToString:[record objectForKey:@"account"]] || [key isEqualToString:[record objectForKey:@"dst_account"]]) {
            NSString *title = closed ? [[item objectForKey:@"name"] stringByAppendingString:@" (clos)"] : [item objectForKey:@"name"];
            HBAddChoice(_account, title, key); HBAddChoice(_destination, title, key);
        }
    }
    HBSelectKey(_account, record ? [record objectForKey:@"account"] : [account objectForKey:@"key"]);
    if (record && HBIsTransfer(record)) HBSelectKey(_destination, [record objectForKey:@"dst_account"]);
    else if ([_destination numberOfItems] > 1) [_destination selectItemAtIndex:[_account indexOfSelectedItem] == 0 ? 1 : 0];
    [_account setTarget:self]; [_account setAction:@selector(updateType:)]; [_destination setTarget:self]; [_destination setAction:@selector(updateType:)];
    HBEditorLabel(view, @"Date JJ/MM/AAAA", NSMakeRect(16, 318, 120, 20));
    _date = HBInput(view, [record ? HBDateFromOrdinal([[record objectForKey:@"date"] intValue]) : HBToday() descriptionWithCalendarFormat:@"%d/%m/%Y"], NSMakeRect(140, 315, 150, 24));
    _amountTitle = HBEditorLabel(view, @"Montant", NSMakeRect(350, 318, 120, 20));
    _amount = HBInput(view, record ? HBPositiveText([record objectForKey:@"amount"]) : @"", NSMakeRect(480, 315, 180, 24));
    _destinationTitle = HBEditorLabel(view, @"Montant compte lie", NSMakeRect(16, 280, 200, 20));
    _destinationAmount = HBInput(view, other ? HBPositiveText([other objectForKey:@"amount"]) : @"", NSMakeRect(260, 277, 150, 24));
    HBEditorLabel(view, @"Tiers", NSMakeRect(16, 242, 110, 20));
    _payee = [[[NSComboBox alloc] initWithFrame:NSMakeRect(140, 239, 520, 26)] autorelease]; [view addSubview:_payee];
    NSArray *payees = [[wallet payees] sortedArrayUsingFunction:HBNameOrder context:NULL];
    for (i = 0; i < [payees count]; i++) {
        NSDictionary *payee = [payees objectAtIndex:i]; NSString *name = [payee objectForKey:@"name"];
        if ([name isEqualToString:@"(null)"]) name = @"";
        if ([name length]) [_payee addItemWithObjectValue:name];
        if ([[payee objectForKey:@"key"] isEqualToString:[record objectForKey:@"payee"]]) [_payee setStringValue:name ? name : @""];
    }
    HBEditorLabel(view, @"Categorie", NSMakeRect(16, 204, 110, 20)); _category = HBPopup(view, nil, NSMakeRect(140, 201, 520, 26));
    HBAddChoice(_category, @"Sans categorie", @"0");
    NSArray *categories = [[wallet categories] sortedArrayUsingFunction:HBCategoryOrder context:wallet];
    for (i = 0; i < [categories count]; i++) {
        NSDictionary *category = [categories objectAtIndex:i]; NSString *key = [category objectForKey:@"key"];
        if ([key isEqualToString:@"0"]) continue;
        HBAddChoice(_category, [wallet categoryForRecord:[NSDictionary dictionaryWithObject:key forKey:@"category"]], key);
    }
    if (record) HBSelectKey(_category, [record objectForKey:@"category"]);
    if (record && ![[record objectForKey:@"category"] isEqualToString:HBChoice(_category)]) {
        HBAddChoice(_category, @"Categorie introuvable", [record objectForKey:@"category"]); HBSelectKey(_category, [record objectForKey:@"category"]);
    }
    HBEditorLabel(view, @"Paiement", NSMakeRect(16, 166, 110, 20));
    _paymode = HBPopup(view, [NSArray arrayWithObjects:@"Aucun", @"Carte credit", @"Cheque", @"Especes", @"Virement", @"Interne", @"Carte debit", @"Recurrent", @"Electronique", @"Depot", @"Frais", @"Prelevement", @"Mobile", nil], NSMakeRect(140, 163, 200, 26));
    [[_paymode itemAtIndex:5] setEnabled:NO];
    int payment = [[record objectForKey:@"paymode"] intValue]; [_paymode selectItemAtIndex:payment >= 0 && payment <= 12 && payment != 5 ? payment : 0];
    HBEditorLabel(view, @"Numero", NSMakeRect(370, 166, 100, 20)); _number = HBInput(view, [record objectForKey:@"info"], NSMakeRect(480, 163, 180, 24));
    HBEditorLabel(view, @"Statut", NSMakeRect(16, 128, 110, 20));
    _status = HBPopup(view, [NSArray arrayWithObjects:@"Non pointe", @"Pointe", @"Rapproche", @"Annule", nil], NSMakeRect(140, 125, 200, 26));
    [_status selectItemAtIndex:[[record objectForKey:@"st"] intValue]];
    HBEditorLabel(view, @"Memo", NSMakeRect(16, 90, 110, 20)); _memo = HBInput(view, [record objectForKey:@"wording"], NSMakeRect(140, 87, 520, 24));
    _error = HBEditorLabel(view, @"", NSMakeRect(16, 47, 644, 34)); [[_error cell] setWraps:YES];
    NSButton *cancel = [[[NSButton alloc] initWithFrame:NSMakeRect(430, 10, 110, 30)] autorelease];
    [cancel setTitle:@"Annuler"]; [cancel setBezelStyle:NSRoundedBezelStyle]; [cancel setTarget:self]; [cancel setAction:@selector(cancel:)]; [cancel setKeyEquivalent:@"\033"]; [view addSubview:cancel];
    NSButton *save = [[[NSButton alloc] initWithFrame:NSMakeRect(550, 10, 110, 30)] autorelease];
    [save setTitle:@"Valider"]; [save setBezelStyle:NSRoundedBezelStyle]; [save setTarget:self]; [save setAction:@selector(submit:)]; [save setKeyEquivalent:@"\r"]; [view addSubview:save];
    if (_locked) { [_date setEditable:NO]; [_amount setEditable:NO]; [_account setEnabled:NO]; [_category setEnabled:NO]; }
    [self updateType:nil]; return self;
}
- (void)updateType:(id)sender {
    BOOL transfer = [_type indexOfSelectedItem] == 2;
    NSDictionary *source = [_wallet accountWithKey:HBChoice(_account)], *target = [_wallet accountWithKey:HBChoice(_destination)];
    BOOL different = transfer && ![[_wallet currencyKeyForAccount:source] isEqualToString:[_wallet currencyKeyForAccount:target]];
    [_destination setEnabled:transfer && !_locked]; [_direction setEnabled:transfer && !_locked];
    [_destinationAmount setEnabled:different && !_locked]; [_paymode setEnabled:!transfer && !_locked];
    [_destinationTitle setStringValue:different ? @"Montant compte lie" : @""];
    [_amountTitle setToolTip:[_wallet formatAmount:[NSDecimalNumber zero] account:source]];
    [_destinationAmount setToolTip:[_wallet formatAmount:[NSDecimalNumber zero] account:target]];
}
- (void)cancel:(id)sender { [NSApp stopModal]; }
- (void)submit:(id)sender {
    NSString *types[] = { @"expense", @"income", @"transfer" };
    NSDictionary *values = [NSDictionary dictionaryWithObjectsAndKeys:types[[_type indexOfSelectedItem]], @"type", HBChoice(_account) ? HBChoice(_account) : @"", @"account",
        [_date stringValue], @"date", [_amount stringValue], @"amount", HBChoice(_destination) ? HBChoice(_destination) : @"", @"destination",
        [_destinationAmount stringValue], @"destinationAmount", [_direction indexOfSelectedItem] == 1 ? @"in" : @"out", @"direction",
        HBChoice(_category), @"category", [NSString stringWithFormat:@"%ld", (long)[_paymode indexOfSelectedItem]], @"paymode",
        [NSString stringWithFormat:@"%ld", (long)[_status indexOfSelectedItem]], @"status", [_payee stringValue], @"payeeName", [_memo stringValue], @"memo", [_number stringValue], @"number", nil];
    NSString *error = nil;
    HBWallet *result = [_wallet walletByUpdatingRecord:_record values:values error:&error];
    if (!result) { [_error setStringValue:error ? error : @"Operation invalide."]; return; }
    [_result release]; _result = [result retain]; [NSApp stopModal];
}
- (HBWallet *)run {
    [_panel makeKeyAndOrderFront:nil]; [NSApp runModalForWindow:_panel]; [_panel orderOut:nil];
    return [[_result retain] autorelease];
}
- (void)dealloc { [_wallet release]; [_record release]; [_result release]; [_panel release]; [super dealloc]; }
@end
