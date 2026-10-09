#import "HBJournal.h"
#import "HBDrive.h"
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>

static int checks, failures;
static void check(BOOL ok, const char *message) { checks++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message); } }
static NSMutableDictionary *values(NSString *type) {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:type, @"type", @"1", @"account", @"15/10/2026", @"date", @"15,25", @"amount",
        @"0", @"status", @"0", @"category", @"0", @"paymode", @"Fictive new payee", @"payeeName", @"Memo & <test>", @"memo", @"CH-1", @"number",
        @"2", @"destination", @"out", @"direction", nil];
}
static BOOL balancesEqual(HBWallet *a, HBWallet *b) {
    NSEnumerator *accounts = [[a accounts] objectEnumerator]; NSDictionary *account;
    while ((account = [accounts nextObject])) if (![[a balancesForAccount:account] isEqual:[b balancesForAccount:[b accountWithKey:[account objectForKey:@"key"]]]]) return NO;
    return YES;
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; char directory[] = "/tmp/homebank-journal-tests-XXXXXX";
    if (!mkdtemp(directory)) return 1;
    NSString *folder = [NSString stringWithUTF8String:directory], *path = [folder stringByAppendingPathComponent:@"wallet.xhb"], *journal = [path stringByAppendingString:@".panther-journal"], *error = nil;
    NSString *xml = @"<homebank v='1.6' custom='keep' xmlns:x='urn:test'><!--keep--><account key='1' initial='100'/><account key='2' initial='10'/><ope account='1' date='739900' amount='-12' custom='opaque'><x:note value='keep'/></ope><ope account='2' date='739901' amount='5' st='2'/><fav recflg='1' account='1' amount='-20' nextdate='739920' unit='2' every='1'/></homebank>";
    HBWallet *base = [[[HBWallet alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error] autorelease];
    NSString *hash = HBDriveSHA256([base baseSourceData]);
    check([[[base records] objectAtIndex:0] isKindOfClass:[HBOperation class]] && [[[base accounts] objectAtIndex:0] isKindOfClass:[HBAccount class]], "imports typed immutable records and accounts");
    id constructorObjects[] = { @"value" }; id<NSCopying> constructorKeys[] = { @"opaque" };
    HBOperation *adapter = [[[HBOperation alloc] initWithObjects:constructorObjects forKeys:constructorKeys count:1] autorelease];
    check([adapter count] == 1 && [[adapter objectForKey:@"opaque"] isEqualToString:@"value"], "operation adapter implements dictionary designated constructor without adding fields");
    HBAccount *accountAdapter = [[[HBAccount alloc] initWithObjects:constructorObjects forKeys:constructorKeys count:1] autorelease];
    check([[NSDictionary dictionaryWithDictionary:accountAdapter] isEqualToDictionary:[NSDictionary dictionaryWithObject:@"value" forKey:@"opaque"]], "account adapter preserves dictionary primitive contract");
    check(HBWriteWallet(base, path, nil, &error), "creates isolated fictive XML baseline");
    NSDictionary *empty = HBJournalRead(journal, hash, &error);
    check(empty && [[empty objectForKey:@"count"] intValue] == 0, "missing journal is an empty durable prefix");
    HBWallet *first = [base walletByChangingStatus:@"2" record:[[base records] objectAtIndex:0] error:&error];
    check([first generation] == 1 && [first baseSourceData] == [base baseSourceData], "status edit does not serialize or replace XML baseline");
    check([[first records] objectAtIndex:1] == [[base records] objectAtIndex:1], "unchanged operations retain identity across snapshots");
    check([[[[base records] objectAtIndex:0] objectForKey:@"st"] intValue] == 0, "working snapshot does not mutate original record");
    check(balancesEqual(first, [first walletForHomeBankExport:&error]), "incremental status balances match full XML reimport");
    NSDictionary *state = HBJournalAppend(journal, hash, [first journalCommands], empty, &error);
    check(state && [[state objectForKey:@"count"] intValue] == 1, "appends a checksum-protected durable command");
    struct stat info; stat([journal fileSystemRepresentation], &info); check((info.st_mode & 0777) == 0600, "journal permissions are private");
    check([[NSData dataWithContentsOfFile:path] isEqualToData:[base baseSourceData]], "journal append never writes main XML");
    check(HBJournalAppend(journal, hash, [first journalCommands], empty, &error) != nil, "lost acknowledgement retry does not duplicate transaction");
    check([[HBJournalRead(journal, hash, NULL) objectForKey:@"count"] intValue] == 1, "idempotent append retains exactly one command");
    check(HBJournalRead(journal, HBDriveSHA256([@"different" dataUsingEncoding:NSUTF8StringEncoding]), &error) == nil, "journal rejects unrelated XML baseline");
    HBWallet *second = [first walletByChangingStatus:@"0" record:[[first records] objectAtIndex:0] error:&error];
    NSDictionary *next = HBJournalAppend(journal, hash, [NSArray arrayWithObject:[[second journalCommands] lastObject]], state, &error);
    check(next && [[next objectForKey:@"count"] intValue] == 2, "appends only new command to confirmed prefix");
    HBWallet *edited = [second walletByUpdatingRecord:[[second records] objectAtIndex:0] values:values(@"expense") error:&error];
    NSMutableDictionary *transferValues = values(@"transfer"); [transferValues setObject:@"10" forKey:@"amount"];
    HBWallet *transferred = [edited walletByUpdatingRecord:nil values:transferValues error:&error];
    check([transferred generation] == 4 && [[transferred records] count] == 4, "internal transfer creates two records in one transaction");
    check(balancesEqual(transferred, [transferred walletForHomeBankExport:&error]), "incremental amount and transfer balances match full reimport");
    state = HBJournalAppend(journal, hash, [[transferred journalCommands] subarrayWithRange:NSMakeRange(2, 2)], next, &error);
    check(state && [[state objectForKey:@"count"] intValue] == 4, "persists compound transfer as one frame");
    NSDictionary *restoredState = nil; HBWallet *restored = HBRestoreWallet(path, &restoredState, &error);
    check(restored && [restored generation] == 4 && [[restored records] isEqual:[transferred records]], "replays all edits with stable operation IDs");
    check(balancesEqual(restored, transferred), "replayed balances match acknowledged in-memory balances");
    NSString *exportedXML = [[[NSString alloc] initWithData:[restored sourceData] encoding:NSUTF8StringEncoding] autorelease];
    check([exportedXML rangeOfString:@"x:note"].location != NSNotFound && [exportedXML rangeOfString:@"<!--keep-->"].location != NSNotFound && [exportedXML rangeOfString:@"<fav"].location != NSNotFound, "deferred XML export preserves nested extensions, comments and templates");
    check([base walletByApplyingCommand:[[second journalCommands] lastObject] error:&error] == nil, "replay refuses mismatched record version");
    NSMutableDictionary *bad = [NSMutableDictionary dictionaryWithDictionary:[[first journalCommands] lastObject]]; [bad setObject:@"unknown" forKey:@"kind"];
    check([base walletByApplyingCommand:bad error:&error] == nil, "unknown command is refused without model mutation");
    bad = [NSMutableDictionary dictionaryWithDictionary:[[first journalCommands] lastObject]]; [bad setObject:@"2" forKey:@"generation"];
    check([base walletByApplyingCommand:bad error:&error] == nil, "command sequence detects reordered independent transactions");

    NSData *good = [NSData dataWithContentsOfFile:journal];
    int fd = open([journal fileSystemRepresentation], O_WRONLY | O_APPEND); write(fd, "\0\0", 2); close(fd);
    NSDictionary *torn = HBJournalRead(journal, hash, &error);
    check(torn && [[torn objectForKey:@"recoveredTail"] boolValue] && [[torn objectForKey:@"count"] intValue] == 4, "ignores incomplete final frame, retaining all complete transactions");
    HBWallet *third = [transferred walletByChangingStatus:@"1" record:[[transferred records] lastObject] error:&error];
    NSDictionary *repaired = HBJournalAppend(journal, hash, [NSArray arrayWithObject:[[third journalCommands] lastObject]], state, &error);
    check(repaired && [[repaired objectForKey:@"count"] intValue] == 5, "append safely truncates incomplete tail before next transaction");
    check([[HBJournalRead(journal, hash, NULL) objectForKey:@"count"] intValue] == 5, "recovered journal remains fully replayable");
    HBWallet *deleted = [third walletByDeletingRecord:[[third records] objectAtIndex:0] error:&error];
    HBWallet *added = [deleted walletByUpdatingRecord:nil values:values(@"income") error:&error];
    check([[[[added records] lastObject] objectForKey:@"__index"] unsignedIntValue] == 4, "deletion does not recycle existing operation identifiers");
    check([added recordWithIdentifier:[NSNumber numberWithInt:0]] == nil && [added recordWithIdentifier:[NSNumber numberWithInt:2]] != nil, "stable lookup remains valid after array compaction");
    check(balancesEqual(added, [added walletForHomeBankExport:&error]), "delete and insert balances match full serialization");

    [good writeToFile:journal atomically:NO];
    NSMutableData *corrupted = [NSMutableData dataWithData:good]; ((char *)[corrupted mutableBytes])[[corrupted length] - 1] ^= 1;
    [corrupted writeToFile:journal atomically:NO];
    check(HBJournalRead(journal, hash, &error) == nil, "complete corrupted frame blocks replay instead of dropping data");
    [good writeToFile:journal atomically:NO];
    check(!HBJournalClear(journal, hash, 3, &error) && [[NSFileManager defaultManager] fileExistsAtPath:journal], "cleanup refuses unacknowledged journal count");
    NSString *alias = [folder stringByAppendingPathComponent:@"alias"]; symlink([journal fileSystemRepresentation], [alias fileSystemRepresentation]);
    check(HBJournalRead(alias, hash, &error) == nil, "refuses symlink journal");
    NSString *fifo = [folder stringByAppendingPathComponent:@"fifo"]; mkfifo([fifo fileSystemRepresentation], 0600);
    check(HBJournalRead(fifo, hash, &error) == nil, "refuses FIFO without blocking");
    NSString *lock = [journal stringByAppendingString:@".lock"]; [[@"locked" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:lock atomically:NO];
    check(HBJournalAppend(journal, hash, [NSArray array], restoredState, &error) == nil, "refuses concurrent journal writer"); unlink([lock fileSystemRepresentation]);

    fd = open([journal fileSystemRepresentation], O_WRONLY | O_APPEND); write(fd, "\0\0", 2); close(fd);
    check([[HBJournalRead(journal, hash, NULL) objectForKey:@"recoveredTail"] boolValue], "checkpoint fixture contains recoverable incomplete tail");
    HBWallet *checkpoint = HBCheckpointWallet(transferred, path, &error);
    check(checkpoint && ![checkpoint generation] && ![[NSFileManager defaultManager] fileExistsAtPath:journal], "checkpoint atomically consolidates XML and clears matching journal");
    check(balancesEqual(checkpoint, transferred), "checkpoint preserves current account balances");
    check([HBRestoreWallet(path, NULL, &error) generation] == 0, "checkpoint restart does not replay already consolidated commands");

    NSString *crashPath = [folder stringByAppendingPathComponent:@"crash.xhb"], *crashJournal = [crashPath stringByAppendingString:@".panther-journal"];
    HBWriteWallet(base, crashPath, nil, NULL); HBJournalAppend(crashJournal, hash, [first journalCommands], empty, NULL);
    HBWallet *serialized = [first walletForHomeBankExport:NULL];
    NSDictionary *receipt = [NSDictionary dictionaryWithObjectsAndKeys:hash, @"oldSHA", HBDriveSHA256([serialized baseSourceData]), @"newSHA", @"1", @"count", nil];
    HBDriveWriteState(receipt, [crashPath stringByAppendingString:@".panther-commit.plist"], NULL);
    check([HBRestoreWallet(crashPath, NULL, &error) generation] == 1, "crash before XML replacement replays original journal");
    HBWriteWallet(serialized, crashPath, [base baseSourceData], NULL);
    HBWallet *afterCrash = HBRestoreWallet(crashPath, NULL, &error);
    check(afterCrash && ![afterCrash generation] && ![[NSFileManager defaultManager] fileExistsAtPath:crashJournal], "crash after XML replacement recognizes receipt and avoids duplicate replay");

    NSString *externalPath = [folder stringByAppendingPathComponent:@"external.xhb"], *externalJournal = [externalPath stringByAppendingString:@".panther-journal"];
    HBWriteWallet(base, externalPath, nil, NULL); HBJournalAppend(externalJournal, hash, [first journalCommands], empty, NULL);
    HBWriteWallet(serialized, externalPath, [base baseSourceData], NULL);
    check(HBRestoreWallet(externalPath, NULL, &error) == nil && [[NSFileManager defaultManager] fileExistsAtPath:externalJournal], "external XML replacement refuses incompatible journal and preserves it");
    [[NSFileManager defaultManager] removeFileAtPath:folder handler:nil];
    printf("%d/%d model and journal checks passed (fictive data, no network or Keychain)\n", checks - failures, checks);
    [pool release]; return failures ? 1 : 0;
}
