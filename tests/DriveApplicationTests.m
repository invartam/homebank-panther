#import "HBApplication.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

@interface HBApplication (DriveTestSurface)
- (BOOL)drivePending;
- (BOOL)mayDiscard;
- (void)applyWallet:(HBWallet *)wallet;
- (void)saveFile:(id)sender;
- (void)launchLocalSave:(NSDictionary *)context;
- (void)localSaveFinished:(NSDictionary *)result;
- (void)syncDrive:(id)sender;
- (void)openDrive:(id)sender;
- (void)driveFinished:(NSDictionary *)result;
- (void)driveWorker:(NSDictionary *)context;
- (void)filterRecords;
- (void)selectAccount;
- (NSDictionary *)selectedAccount;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (void)adoptCheckpoint:(HBWallet *)wallet;
@end

@interface HBFictiveAccountTable : NSObject { id _target; HBRow _row; }
- (id)initWithTarget:(id)target;
- (HBRow)selectedRow;
- (void)deselectAll:(id)sender;
- (void)reloadData;
- (void)selectRow:(HBRow)row byExtendingSelection:(BOOL)extend;
@end
@implementation HBFictiveAccountTable
- (id)initWithTarget:(id)target { self = [super init]; if (self) { _target = target; _row = 1; } return self; }
- (HBRow)selectedRow { return _row; }
- (void)deselectAll:(id)sender { _row = -1; [_target tableViewSelectionDidChange:[NSNotification notificationWithName:@"Fictive selection" object:self]]; }
- (void)reloadData { }
- (void)selectRow:(HBRow)row byExtendingSelection:(BOOL)extend { _row = row; [_target tableViewSelectionDidChange:[NSNotification notificationWithName:@"Fictive selection" object:self]]; }
@end

@interface HBSelectionTestApplication : HBApplication {
@public
    unsigned int selections;
}
- (id)initWithWallet:(HBWallet *)wallet;
@end
@implementation HBSelectionTestApplication
- (id)initWithWallet:(HBWallet *)wallet {
    self = [super init]; if (self) {
        _wallet = [wallet retain]; _savedData = [[wallet baseSourceData] copy]; _savedWallet = [wallet retain];
        _visibleAccounts = [[NSArray arrayWithObjects:[wallet accountWithKey:@"1"], [wallet accountWithKey:@"2"], [wallet accountWithKey:@"4"], nil] retain];
        _accountsTable = (id)[[HBFictiveAccountTable alloc] initWithTarget:self];
    } return self;
}
- (NSDictionary *)selectedRecord { return nil; }
- (void)selectAccount { selections++; [super selectAccount]; }
- (void)dealloc { [_accountsTable release]; [super dealloc]; }
@end

@interface HBFictiveVisibility : NSObject { BOOL _visible; }
- (BOOL)isVisible;
- (void)makeKeyAndOrderFront:(id)sender;
@end
@implementation HBFictiveVisibility
- (BOOL)isVisible { return _visible; }
- (void)makeKeyAndOrderFront:(id)sender { _visible = YES; }
@end

@interface HBDeferredCalendarTest : HBCalendarWindow {
@public
    unsigned int refreshes;
}
- (id)initForTest;
- (HBWallet *)wallet;
@end
@implementation HBDeferredCalendarTest
- (id)initForTest { self = [super init]; if (self) _window = (id)[[HBFictiveVisibility alloc] init]; return self; }
- (void)modeChanged:(id)sender { refreshes++; _needsRefresh = NO; }
- (HBWallet *)wallet { return _wallet; }
@end

@interface HBCountingWallet : HBWallet {
@public
    unsigned int formattedAmounts;
}
@end
@implementation HBCountingWallet
- (NSString *)formatAmount:(NSDecimalNumber *)amount account:(NSDictionary *)account {
    formattedAmounts++; return [super formatAmount:amount account:account];
}
@end

@interface HBFictiveSearch : NSObject { NSString *_value; }
- (NSString *)stringValue;
- (void)setStringValue:(NSString *)value;
@end
@implementation HBFictiveSearch
- (NSString *)stringValue { return _value; }
- (void)setStringValue:(NSString *)value { [_value release]; _value = [value copy]; }
- (void)dealloc { [_value release]; [super dealloc]; }
@end

@interface HBFilteringTestApplication : HBApplication
- (id)initWithWallet:(HBWallet *)wallet;
- (void)query:(NSString *)query;
- (NSArray *)visibleRecords;
@end
@implementation HBFilteringTestApplication
- (id)initWithWallet:(HBWallet *)wallet {
    self = [super init]; if (self) { _wallet = [wallet retain]; _search = (id)[[HBFictiveSearch alloc] init]; } return self;
}
- (NSDictionary *)selectedAccount { return [[_wallet accounts] objectAtIndex:0]; }
- (NSDictionary *)selectedRecord { return nil; }
- (void)query:(NSString *)query { [_search setStringValue:query]; [self filterRecords]; }
- (NSArray *)visibleRecords { return _visibleRecords; }
- (void)dealloc { [_search release]; [super dealloc]; }
@end

@interface HBFixtureDriveClient : HBDriveClient {
@public
    BOOL offMain;
    BOOL failUpload;
    NSData *uploadedData;
    HBWallet *fixture;
    NSThread *mainThread;
}
- (id)initWithWallet:(HBWallet *)wallet;
@end
@implementation HBFixtureDriveClient
- (id)initWithWallet:(HBWallet *)wallet {
    self = [super init]; if (self) { fixture = [wallet retain]; mainThread = [[NSThread currentThread] retain]; } return self;
}
- (NSDictionary *)download:(NSString **)error {
    offMain = [NSThread currentThread] != mainThread;
    return [NSDictionary dictionaryWithObjectsAndKeys:fixture, @"wallet",
        [NSDictionary dictionaryWithObjectsAndKeys:@"\"v2\"", @"etag", @"Fictive wallet", @"title", nil], @"metadata", nil];
}
- (NSDictionary *)uploadWallet:(HBWallet *)wallet expectedETag:(NSString *)etag error:(NSString **)error {
    offMain = [NSThread currentThread] != mainThread;
    [uploadedData release]; uploadedData = [[wallet sourceData] copy];
    if (failUpload) { if (error) *error = @"Fictive upload failure"; return nil; }
    return [NSDictionary dictionaryWithObjectsAndKeys:@"\"v3\"", @"etag", @"Fictive wallet", @"title", nil];
}
- (void)dealloc { [fixture release]; [mainThread release]; [uploadedData release]; [super dealloc]; }
@end

/* No windows, credentials or network. Capture snapshots to control completion order. */
@interface HBDriveTestApplication : HBApplication {
@public
    unsigned int saves, requests;
    NSDictionary *saveContext;
    NSString *lastAction;
    BOOL realWrites;
}
- (id)initWithWallet:(HBWallet *)wallet linked:(BOOL)linked;
- (void)markSynced;
- (void)setBusy:(BOOL)busy;
- (BOOL)dirty;
- (BOOL)saving;
- (BOOL)syncRequested;
- (void)finishSave:(BOOL)success;
- (void)setTestPath:(NSString *)path;
- (void)setTestCachePath:(NSString *)path;
- (void)setBaselineWallet:(HBWallet *)wallet;
- (BOOL)driveBusy;
- (NSData *)savedData;
@end
@implementation HBDriveTestApplication
- (id)initWithWallet:(HBWallet *)wallet linked:(BOOL)linked {
    self = [super init]; if (self) {
        _wallet = [wallet retain]; _savedData = [[wallet baseSourceData] copy]; _savedWallet = [wallet retain];
        _journalState = [[NSDictionary dictionaryWithObjectsAndKeys:@"0", @"count", @"0", @"length", nil] retain];
        _driveCachePath = [@"/fictive/cache.xhb" copy]; _path = [linked ? _driveCachePath : @"/fictive/local.xhb" copy];
        _driveSettings = [[NSDictionary dictionaryWithObject:@"fictive-file" forKey:@"fileID"] retain];
        _driveActive = linked; [self markSynced];
    } return self;
}
- (void)markSynced {
    if ([_wallet generation]) [self adoptCheckpoint:[_wallet walletForHomeBankExport:NULL]];
    [_driveState release]; _driveState = [[NSDictionary dictionaryWithObjectsAndKeys:HBDriveSHA256([_wallet baseSourceData]), @"syncedSHA256", @"\"v1\"", @"etag", nil] retain];
}
- (NSDictionary *)selectedAccount { return nil; }
- (NSDictionary *)selectedRecord { return nil; }
- (void)filterAccounts:(id)sender { }
- (void)selectAccount { }
- (void)updateDocumentState { }
- (void)updateButtons { }
- (void)launchLocalSave:(NSDictionary *)context {
    saves++; [saveContext release]; saveContext = [context copy];
    if (realWrites) [super launchLocalSave:context];
}
- (void)startDriveAction:(NSString *)action manual:(BOOL)manual {
    requests++; [lastAction release]; lastAction = [action copy];
}
- (void)finishSave:(BOOL)success {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:saveContext];
    if (success) {
        [result setObject:[NSNumber numberWithBool:YES] forKey:@"saved"];
        [result setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%u", [[saveContext objectForKey:@"wallet"] generation]], @"count", @"71", @"length", nil] forKey:@"journalState"];
    }
    else [result setObject:@"Fictive write failure" forKey:@"error"];
    [self localSaveFinished:result];
}
- (void)setBusy:(BOOL)busy { _driveBusy = busy; }
- (BOOL)dirty { return _dirty; }
- (BOOL)saving { return _saveBusy || _saveTimer != nil; }
- (BOOL)syncRequested { return _syncRequested; }
- (void)setTestPath:(NSString *)path { [_path release]; _path = [path copy]; }
- (void)setTestCachePath:(NSString *)path { [self setTestPath:path]; [_driveCachePath release]; _driveCachePath = [path copy]; }
- (void)setBaselineWallet:(HBWallet *)wallet {
    [_driveState release]; _driveState = [[NSDictionary dictionaryWithObjectsAndKeys:HBDriveSHA256([wallet sourceData]), @"syncedSHA256", @"\"v1\"", @"etag", nil] retain];
}
- (BOOL)driveBusy { return _driveBusy; }
- (NSData *)savedData { return _savedData; }
- (void)dealloc { [saveContext release]; [lastAction release]; [super dealloc]; }
@end

static int failures, checks;
static void check(BOOL ok, const char *message) { checks++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message); } }
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    HBWallet *wallet = [HBWallet walletAtPath:@"tests/demo.xhb" error:NULL];
    HBWallet *edited = [wallet walletByChangingStatus:@"1" record:[[wallet records] objectAtIndex:0] error:NULL];
    HBWallet *newer = [edited walletByChangingStatus:@"2" record:[[edited records] objectAtIndex:0] error:NULL];
    HBCountingWallet *counting = [[[HBCountingWallet alloc] initWithData:[wallet sourceData] error:NULL] autorelease];
    HBFilteringTestApplication *filter = [[[HBFilteringTestApplication alloc] initWithWallet:counting] autorelease];
    [filter query:@""];
    check(counting->formattedAmounts == 0 && [[filter visibleRecords] isEqualToArray:[counting recordsForAccount:[[counting accounts] objectAtIndex:0]]], "empty search adopts sorted account records without formatting every amount");
    [filter query:@"Courses"];
    check([[filter visibleRecords] count] == 1 && [[[[filter visibleRecords] objectAtIndex:0] objectForKey:@"wording"] isEqualToString:@"Courses"], "text and hierarchical category search still works");
    [filter query:@"-10,00"];
    check([[filter visibleRecords] count] == 1 && [[[[filter visibleRecords] objectAtIndex:0] objectForKey:@"amount"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"-10"]], "French amount search still works");
    [filter query:@"123"]; check([[filter visibleRecords] count] == 1, "payment number search is preserved");
    unsigned int formatted = counting->formattedAmounts;
    [filter query:@""]; check(counting->formattedAmounts == formatted && [[filter visibleRecords] count] == 5, "clearing search does not perform another full formatting pass");
    HBSelectionTestApplication *selection = [[[HBSelectionTestApplication alloc] initWithWallet:wallet] autorelease];
    [selection applyWallet:wallet];
    check(selection->selections == 1, "programmatic account notifications do not trigger duplicate refreshes");
    check([[[selection selectedAccount] objectForKey:@"key"] isEqualToString:@"2"], "refresh preserves selected account rather than first account");
    HBDeferredCalendarTest *calendar = [[[HBDeferredCalendarTest alloc] initForTest] autorelease];
    [calendar setWallet:wallet]; [calendar setWallet:edited]; [calendar setWallet:newer];
    check(calendar->refreshes == 1, "hidden calendar does not recalculate projections on every edit");
    [calendar show];
    check(calendar->refreshes == 2 && [calendar wallet] == newer, "opening calendar refreshes latest snapshot exactly once");
    [calendar setWallet:edited];
    check(calendar->refreshes == 3 && [calendar wallet] == edited, "visible calendar keeps its projections current");
    HBDriveTestApplication *local = [[[HBDriveTestApplication alloc] initWithWallet:wallet linked:NO] autorelease];
    check(![local drivePending], "unrelated local wallet is not bound to Drive");
    [local applyWallet:edited];
    check([local dirty] && [local saving] && local->saves == 0 && local->requests == 0, "local edit queues persistence without blocking or sending");
    check(![local mayDiscard], "close or file switch refused while a local save is queued");
    [local saveFile:nil];
    check(local->saves == 1 && [local dirty], "manual save launches a worker without claiming success early");
    [local finishSave:YES];
    check(![local dirty] && ![local saving] && local->requests == 0, "local completion clears dirty state without network");

    HBDriveTestApplication *linked = [[[HBDriveTestApplication alloc] initWithWallet:wallet linked:YES] autorelease];
    check(![linked drivePending], "matching persisted baseline is clean");
    [linked applyWallet:edited]; [linked saveFile:nil];
    check(linked->saves == 1 && linked->requests == 0 && [linked drivePending], "Drive edit saves locally only");
    [linked applyWallet:newer];
    check(linked->saves == 1 && [linked dirty], "edits during persistence do not start concurrent writers");
    [linked syncDrive:nil];
    check([linked syncRequested] && linked->requests == 0, "explicit sync waits for durable local data");
    [linked syncDrive:nil]; check(linked->requests == 0 && linked->saves == 1, "repeated sync clicks are coalesced");
    [linked finishSave:YES];
    check(linked->saves == 2 && linked->requests == 0 && [linked dirty], "old snapshot completion queues latest edit before sending");
    check([[[linked->saveContext objectForKey:@"journalState"] objectForKey:@"count"] intValue] == 1 &&
        [[linked->saveContext objectForKey:@"wallet"] generation] == 2, "next save appends only commands after confirmed journal prefix");
    check(![linked mayDiscard], "close refused while writer is active");
    [linked finishSave:YES];
    check(![linked dirty] && linked->requests == 1 && [linked->lastAction isEqualToString:@"upload"] && ![linked syncRequested], "requested sync starts after latest successful save only");
    check([linked drivePending], "local save alone never acknowledges remote synchronization");
    [linked markSynced]; check(![linked drivePending], "confirmed remote baseline clears pending changes");
    [linked syncDrive:nil]; check(linked->requests == 2 && [linked->lastAction isEqualToString:@"download"], "manual clean sync requests remote updates");

    HBDriveTestApplication *pending = [[[HBDriveTestApplication alloc] initWithWallet:wallet linked:YES] autorelease];
    [pending applyWallet:edited]; [pending saveFile:nil]; [pending finishSave:YES]; [pending openDrive:nil];
    check(pending->requests == 0 && [pending drivePending], "opening active pending cache never uploads automatically");
    [pending driveFinished:[NSDictionary dictionaryWithObjectsAndKeys:@"upload", @"action", @"Fictive transient error", @"error", [NSNumber numberWithBool:YES], @"retryable", nil]];
    check(pending->requests == 0 && [pending drivePending], "network failure retains edits without automatic retry");
    HBDriveTestApplication *restored = [[[HBDriveTestApplication alloc] initWithWallet:edited linked:YES] autorelease];
    [restored setBaselineWallet:wallet]; [restored openDrive:nil];
    check(![restored dirty] && [restored drivePending] && restored->requests == 0, "restored durable changes remain pending without automatic upload");
    check([restored mayDiscard], "durable unsent changes can survive normal exit without mandatory network");

    HBDriveTestApplication *failed = [[[HBDriveTestApplication alloc] initWithWallet:wallet linked:YES] autorelease];
    [failed applyWallet:edited]; [failed syncDrive:nil]; [failed finishSave:NO];
    check([failed dirty] && ![failed saving] && ![failed syncRequested] && failed->requests == 0, "write failure cancels requested sync and retains edits");
    check([[failed savedData] isEqualToData:[wallet sourceData]], "failed save does not advance durable baseline");
    [failed saveFile:nil]; [failed finishSave:YES];
    check(![failed dirty] && failed->requests == 0 && [failed drivePending], "local retry never revives canceled network request");
    [failed setBusy:YES]; [failed applyWallet:newer]; [failed saveFile:nil];
    check(failed->saves == 2 && [failed dirty], "manual save cannot race active Drive job");
    [failed setBusy:NO]; [failed saveFile:nil]; [failed finishSave:YES];

    HBDriveTestApplication *reverted = [[[HBDriveTestApplication alloc] initWithWallet:wallet linked:NO] autorelease];
    [reverted applyWallet:edited]; [reverted applyWallet:wallet]; [reverted saveFile:nil];
    check(![reverted saving] && reverted->saves == 0, "reverting to durable bytes clears debounce without stuck timer");
    HBDriveTestApplication *repair = [[[HBDriveTestApplication alloc] initWithWallet:wallet linked:YES] autorelease];
    [repair applyWallet:[wallet commitRecords:[NSArray array] deleting:[NSArray array] payee:nil command:[wallet command:@"normalize" record:nil values:nil] error:NULL]]; [repair saveFile:nil]; [repair finishSave:YES];
    check(repair->saves == 1 && repair->requests == 0 && [repair drivePending], "format repair saves locally and requires explicit sync");

    /* Real background writes, isolated fictive wallet, no credentials. */
    char directory[] = "/tmp/homebank-async-save-XXXXXX";
    char *created = mkdtemp(directory);
    check(created != NULL, "private integration directory created");
    if (created) {
        NSString *folder = [NSString stringWithUTF8String:created], *path = [folder stringByAppendingPathComponent:@"wallet.xhb"];
        check(HBWriteWallet(wallet, path, nil, NULL), "fictive initial wallet persisted");
        HBDriveTestApplication *disk = [[[HBDriveTestApplication alloc] initWithWallet:wallet linked:NO] autorelease];
        [disk setTestPath:path]; disk->realWrites = YES;
        [disk applyWallet:edited]; [disk saveFile:nil]; [disk applyWallet:newer];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while ([disk saving] && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        check(![disk saving] && ![disk dirty] && disk->saves == 2, "real asynchronous queue drains both snapshots");
        HBWallet *saved = HBRestoreWallet(path, NULL, NULL);
        check([[saved sourceData] isEqualToData:[newer sourceData]], "disk retains newest edit, not older worker snapshot");
        check(disk->requests == 0, "real background persistence never invokes Drive");
        NSString *debouncePath = [folder stringByAppendingPathComponent:@"debounce.xhb"];
        check(HBWriteWallet(wallet, debouncePath, nil, NULL), "fictive debounce wallet persisted");
        HBDriveTestApplication *debounced = [[[HBDriveTestApplication alloc] initWithWallet:wallet linked:NO] autorelease];
        [debounced setTestPath:debouncePath]; debounced->realWrites = YES;
        [debounced applyWallet:edited]; [debounced applyWallet:newer];
        check(debounced->saves == 0, "rapid edits do not write synchronously");
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while ([debounced saving] && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        check(debounced->saves == 1 && ![debounced dirty] && ![debounced saving], "debounce automatically persists rapid edits in one background write");
        check([[HBRestoreWallet(debouncePath, NULL, NULL) sourceData] isEqualToData:[newer sourceData]], "debounced journal restores latest edit");
        check([[NSData dataWithContentsOfFile:path] isEqualToData:[wallet baseSourceData]], "ordinary edits never rewrite base XML");
        HBDriveTestApplication *upload = [[[HBDriveTestApplication alloc] initWithWallet:wallet linked:YES] autorelease];
        [upload setTestCachePath:path]; [upload setBusy:YES];
        HBFixtureDriveClient *uploadClient = [[[HBFixtureDriveClient alloc] initWithWallet:wallet] autorelease];
        NSDictionary *uploadContext = [NSDictionary dictionaryWithObjectsAndKeys:uploadClient, @"client", @"upload", @"action", newer, @"wallet", newer, @"localWallet",
            path, @"cachePath", @"fictive-file", @"fileID", @"\"v1\"", @"etag", nil];
        [NSThread detachNewThreadSelector:@selector(driveWorker:) toTarget:upload withObject:uploadContext];
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while ([upload driveBusy] && [deadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        check(![upload driveBusy] && ![upload drivePending] && [uploadClient->uploadedData isEqualToData:[newer sourceData]], "explicit upload consolidates latest durable journal and sends its XML snapshot");
        check(![[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingString:@".panther-journal"]], "confirmed XML consolidation clears only the acknowledged journal");
        HBWallet *checkpointBase = [HBWallet walletAtPath:path error:NULL];
        HBWallet *pendingFailure = [checkpointBase walletByChangingStatus:@"0" record:[[checkpointBase records] objectAtIndex:0] error:NULL];
        NSString *journalPath = [path stringByAppendingString:@".panther-journal"], *baseHash = HBDriveSHA256([checkpointBase baseSourceData]);
        HBJournalAppend(journalPath, baseHash, [pendingFailure journalCommands], HBJournalRead(journalPath, baseHash, NULL), NULL);
        uploadClient->failUpload = YES; [upload setBusy:YES];
        uploadContext = [NSDictionary dictionaryWithObjectsAndKeys:uploadClient, @"client", @"upload", @"action", pendingFailure, @"wallet", pendingFailure, @"localWallet",
            path, @"cachePath", @"fictive-file", @"fileID", @"\"v3\"", @"etag", nil];
        [NSThread detachNewThreadSelector:@selector(driveWorker:) toTarget:upload withObject:uploadContext];
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while ([upload driveBusy] && [deadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        check(![upload driveBusy] && [upload drivePending] && ![upload dirty], "network failure retains a durable checkpoint and remote-pending indicator");
        check([[HBRestoreWallet(path, NULL, NULL) sourceData] isEqualToData:[pendingFailure sourceData]], "restart after failed upload retains every consolidated local change");
        path = [folder stringByAppendingPathComponent:@"network.xhb"];
        HBWallet *networkBase = [newer walletForHomeBankExport:NULL]; HBWriteWallet(networkBase, path, nil, NULL);
        HBDriveTestApplication *download = [[[HBDriveTestApplication alloc] initWithWallet:networkBase linked:YES] autorelease];
        [download setTestCachePath:path]; [download setBusy:YES];
        HBFixtureDriveClient *client = [[[HBFixtureDriveClient alloc] initWithWallet:wallet] autorelease];
        NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:client, @"client", @"download", @"action",
            path, @"cachePath", @"fictive-file", @"fileID", [newer sourceData], @"expectedCacheData", nil];
        [NSThread detachNewThreadSelector:@selector(driveWorker:) toTarget:download withObject:context];
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while ([download driveBusy] && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        check(![download driveBusy] && client->offMain, "Drive processing runs on background thread with fictive transport");
        check([[download savedData] isEqualToData:[wallet sourceData]] && ![download drivePending], "completed download adopts already persisted immutable wallet");
        NSDictionary *state = HBDriveReadState([path stringByAppendingString:@".drive-state.plist"]);
        check([[state objectForKey:@"etag"] isEqualToString:@"\"v2\""] && [[state objectForKey:@"syncedSHA256"] isEqualToString:HBDriveSHA256([wallet sourceData])], "download worker persists confirmed Drive reference");
        [download setBusy:YES];
        context = [NSDictionary dictionaryWithObjectsAndKeys:client, @"client", @"upload", @"action", wallet, @"wallet",
            path, @"cachePath", @"fictive-file", @"fileID", @"\"v2\"", @"etag", nil];
        [NSThread detachNewThreadSelector:@selector(driveWorker:) toTarget:download withObject:context];
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while ([download driveBusy] && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        state = HBDriveReadState([path stringByAppendingString:@".drive-state.plist"]);
        check(![download driveBusy] && [[state objectForKey:@"etag"] isEqualToString:@"\"v3\""], "upload worker persists acknowledgement off the UI thread");
        if (![disk saving]) [[NSFileManager defaultManager] removeFileAtPath:folder handler:nil];
    }
    printf("%d/%d asynchronous persistence and manual Drive checks passed (fictive data, no UI, network or Keychain)\n", checks - failures, checks);
    [pool release]; return failures ? 1 : 0;
}
