#import "HBJournal.h"
#import "HBDrive.h"
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>

#define HB_JOURNAL_MAX (16UL * 1024 * 1024)
#define HB_FRAME_MAX (256UL * 1024)
#define HB_HEADER_SIZE 71

static BOOL HJError(NSString **error, NSString *message) { if (error) *error = message; return NO; }
static BOOL HJHash(NSString *hash) {
    if (![hash isKindOfClass:[NSString class]] || [hash length] != 64) return NO;
    const char *p = [hash UTF8String]; while (*p) { if (!(*p >= '0' && *p <= '9') && !(*p >= 'a' && *p <= 'f')) return NO; p++; } return YES;
}
static NSData *HJHeader(NSString *hash) { return [[NSString stringWithFormat:@"HBPJ1:%@\n", hash] dataUsingEncoding:NSASCIIStringEncoding]; }
static BOOL HJIO(int fd, void *bytes, unsigned long length, BOOL writing) {
    unsigned long offset = 0;
    while (offset < length) {
        ssize_t count = writing ? write(fd, (char *)bytes + offset, length - offset) : read(fd, (char *)bytes + offset, length - offset);
        if (count < 0 && errno == EINTR) continue; if (count <= 0) return NO; offset += count;
    } return YES;
}
static BOOL HJPrivate(struct stat *info) { return S_ISREG(info->st_mode) && info->st_uid == getuid() && !(info->st_mode & 0077) && info->st_size <= HB_JOURNAL_MAX; }
static int HJOpen(NSString *path, int flags) {
    struct stat before, after;
    if (lstat([path fileSystemRepresentation], &before) != 0 || !HJPrivate(&before)) return -1;
    int fd = open([path fileSystemRepresentation], flags | O_NOFOLLOW);
    if (fd >= 0 && (fstat(fd, &after) != 0 || !HJPrivate(&after) || before.st_dev != after.st_dev || before.st_ino != after.st_ino)) { close(fd); return -1; }
    return fd;
}
static NSString *HJSignature(struct stat *info) {
    return [NSString stringWithFormat:@"%llu:%llu:%llu:%ld.%ld:%ld.%ld", (unsigned long long)info->st_dev, (unsigned long long)info->st_ino,
        (unsigned long long)info->st_size, (long)info->st_mtimespec.tv_sec, (long)info->st_mtimespec.tv_nsec,
        (long)info->st_ctimespec.tv_sec, (long)info->st_ctimespec.tv_nsec];
}
static NSDictionary *HJEmpty(void) { return [NSDictionary dictionaryWithObjectsAndKeys:[NSArray array], @"commands", @"0", @"count", @"0", @"length", nil]; }
static BOOL HJValue(id value, unsigned int depth) {
    if (depth > 8) return NO;
    if ([value isKindOfClass:[NSString class]]) return [value length] <= 65536;
    if ([value isKindOfClass:[NSDictionary class]]) {
        if ([value count] > 64) return NO; NSEnumerator *keys = [value keyEnumerator]; id key;
        while ((key = [keys nextObject])) if (![key isKindOfClass:[NSString class]] || [key length] > 64 || !HJValue([value objectForKey:key], depth + 1)) return NO;
        return YES;
    } return NO;
}
static NSData *HJPayload(NSDictionary *command) {
    if (!HJValue(command, 0)) return nil;
    NSString *description = nil; NSData *data = [NSPropertyListSerialization dataFromPropertyList:command format:NSPropertyListBinaryFormat_v1_0 errorDescription:&description]; [description release];
    return [data length] && [data length] <= HB_FRAME_MAX ? data : nil;
}
static NSDictionary *HJReadFD(int fd, NSString *baseHash, NSString **error) {
    struct stat before, after; NSData *header = HJHeader(baseHash); unsigned char head[HB_HEADER_SIZE];
    if (fstat(fd, &before) != 0 || !HJPrivate(&before) || lseek(fd, 0, SEEK_SET) < 0 || !HJIO(fd, head, HB_HEADER_SIZE, NO) || memcmp(head, [header bytes], HB_HEADER_SIZE)) {
        HJError(error, @"Journal incompatible avec le fichier XML, non prive ou incomplet. Fichiers conserves."); return nil;
    }
    NSMutableArray *commands = [NSMutableArray array]; unsigned long position = HB_HEADER_SIZE, total = before.st_size, lastOffset = 0; NSString *tailHash = nil;
    while (position < total) {
        if (total - position < 4) break;
        unsigned char lengthBytes[4]; if (!HJIO(fd, lengthBytes, 4, NO)) { HJError(error, @"Lecture du journal interrompue."); return nil; }
        unsigned long length = ((unsigned long)lengthBytes[0] << 24) | ((unsigned long)lengthBytes[1] << 16) | ((unsigned long)lengthBytes[2] << 8) | lengthBytes[3];
        if (!length || length > HB_FRAME_MAX || [commands count] >= 10000) { HJError(error, @"Limites ou longueur du journal invalides."); return nil; }
        if (total - position < 68 + length) break;
        char digest[65]; digest[64] = 0; NSMutableData *payload = [NSMutableData dataWithLength:length];
        if (!HJIO(fd, digest, 64, NO) || !HJIO(fd, [payload mutableBytes], length, NO)) { HJError(error, @"Lecture du journal interrompue."); return nil; }
        NSString *hash = [NSString stringWithUTF8String:digest];
        if (!HJHash(hash) || ![hash isEqualToString:HBDriveSHA256(payload)]) { HJError(error, @"Integrite du journal invalide. Aucun rejeu automatique."); return nil; }
        NSString *description = nil; id command = [NSPropertyListSerialization propertyListFromData:payload mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&description]; [description release];
        if (![command isKindOfClass:[NSDictionary class]] || !HJValue(command, 0)) { HJError(error, @"Schema du journal invalide."); return nil; }
        [commands addObject:command]; lastOffset = position; tailHash = hash; position += 68 + length;
    }
    if (fstat(fd, &after) != 0 || ![HJSignature(&before) isEqualToString:HJSignature(&after)]) { HJError(error, @"Le journal a change pendant sa lecture."); return nil; }
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithObjectsAndKeys:commands, @"commands", [NSString stringWithFormat:@"%lu", (unsigned long)[commands count]], @"count",
        [NSString stringWithFormat:@"%lu", position], @"length", HJSignature(&after), @"signature", [NSNumber numberWithBool:position < total], @"recoveredTail", nil];
    if (tailHash) { [state setObject:tailHash forKey:@"tailSHA"]; [state setObject:[NSString stringWithFormat:@"%lu", lastOffset] forKey:@"lastOffset"]; }
    return state;
}
NSDictionary *HBJournalRead(NSString *path, NSString *baseHash, NSString **error) {
    if (error) *error = nil;
    if (!HJHash(baseHash)) { HJError(error, @"Empreinte du fichier de reference invalide."); return nil; }
    struct stat info; if (lstat([path fileSystemRepresentation], &info) != 0 && errno == ENOENT) return HJEmpty();
    int fd = HJOpen(path, O_RDONLY); if (fd < 0) { HJError(error, @"Journal inaccessible, lien symbolique ou permissions non privees."); return nil; }
    NSDictionary *state = [[HJReadFD(fd, baseHash, error) retain] autorelease]; close(fd); return state;
}
static int HJLock(NSString *path, NSString **error) {
    int fd = open([[path stringByAppendingString:@".lock"] fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) HJError(error, @"Journal verrouille ou dossier inaccessible."); return fd;
}
NSDictionary *HBJournalAppend(NSString *path, NSString *baseHash, NSArray *commands, NSDictionary *expectedState, NSString **error) {
    if (error) *error = nil; unsigned long expectedCount, expectedLength;
    if (!HJHash(baseHash) || ![commands isKindOfClass:[NSArray class]] || !HBParseUnsigned([expectedState objectForKey:@"count"], 10000, &expectedCount) ||
        !HBParseUnsigned([expectedState objectForKey:@"length"], HB_JOURNAL_MAX, &expectedLength) || expectedCount + [commands count] > 10000) {
        HJError(error, @"Etat de sauvegarde du journal invalide ou limite atteinte. Consolider le XML."); return nil;
    }
    NSMutableArray *payloads = [NSMutableArray array]; NSEnumerator *entries = [commands objectEnumerator]; NSDictionary *command; unsigned long added = 0;
    while ((command = [entries nextObject])) {
        NSData *payload = HJPayload(command); if (!payload) { HJError(error, @"Commande trop volumineuse ou invalide. Non enregistree."); return nil; }
        [payloads addObject:payload]; added += 68 + [payload length];
    }
    if (expectedLength + added + HB_HEADER_SIZE > HB_JOURNAL_MAX) { HJError(error, @"Journal trop volumineux. Consolider le XML."); return nil; }
    int lock = HJLock(path, error); if (lock < 0) return nil;
    int fd = -1; NSDictionary *result = nil; struct stat info; BOOL exists = lstat([path fileSystemRepresentation], &info) == 0;
    if (!exists && errno == ENOENT && !expectedCount && !expectedLength) {
        fd = open([path fileSystemRepresentation], O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        NSData *header = HJHeader(baseHash);
        if (fd < 0 || !HJIO(fd, (void *)[header bytes], [header length], YES)) goto done;
        expectedLength = HB_HEADER_SIZE;
    } else {
        fd = HJOpen(path, O_RDWR); if (fd < 0) goto done;
        BOOL fast = fstat(fd, &info) == 0 && info.st_size == (off_t)expectedLength &&
            [[expectedState objectForKey:@"signature"] isEqualToString:HJSignature(&info)] && ![[expectedState objectForKey:@"recoveredTail"] boolValue];
        char header[HB_HEADER_SIZE]; NSData *expectedHeader = HJHeader(baseHash);
        fast = fast && HJIO(fd, header, HB_HEADER_SIZE, NO) && !memcmp(header, [expectedHeader bytes], HB_HEADER_SIZE);
        if (!fast) {
            NSDictionary *actual = HJReadFD(fd, baseHash, error); if (!actual) goto done;
            unsigned long count, length; HBParseUnsigned([actual objectForKey:@"count"], 10000, &count); HBParseUnsigned([actual objectForKey:@"length"], HB_JOURNAL_MAX, &length);
            NSArray *saved = [actual objectForKey:@"commands"];
            if (count == expectedCount + [commands count] && count >= expectedCount &&
                [[saved subarrayWithRange:NSMakeRange(expectedCount, [commands count])] isEqualToArray:commands]) {
                if (ftruncate(fd, length) == 0 && fsync(fd) == 0) result = HJReadFD(fd, baseHash, error); goto done;
            }
            if (count < expectedCount || count > expectedCount + [commands count]) { HJError(error, @"Journal modifie par un autre client."); goto done; }
            unsigned long existing = count - expectedCount;
            if (existing && ![[saved subarrayWithRange:NSMakeRange(expectedCount, existing)] isEqualToArray:[commands subarrayWithRange:NSMakeRange(0, existing)]]) {
                HJError(error, @"Conflit de commandes dans le journal."); goto done;
            }
            if (ftruncate(fd, length) != 0) goto done;
            if (existing) [payloads removeObjectsInRange:NSMakeRange(0, existing)];
            expectedCount = count; expectedLength = length;
        }
    }
    if (lseek(fd, expectedLength, SEEK_SET) < 0) goto done;
    unsigned long position = expectedLength, lastOffset = 0; NSString *tailHash = nil;
    entries = [payloads objectEnumerator]; NSData *payload;
    while ((payload = [entries nextObject])) {
        unsigned long length = [payload length]; unsigned char size[4] = { length >> 24, length >> 16, length >> 8, length };
        NSString *hash = HBDriveSHA256(payload); if (!hash || !HJIO(fd, size, 4, YES) || !HJIO(fd, (void *)[hash UTF8String], 64, YES) || !HJIO(fd, (void *)[payload bytes], length, YES)) goto done;
        lastOffset = position; tailHash = hash; position += 68 + length; expectedCount++;
    }
    if (fsync(fd) != 0 || fstat(fd, &info) != 0) goto done;
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%lu", expectedCount], @"count", [NSString stringWithFormat:@"%lu", position], @"length", HJSignature(&info), @"signature", nil];
    if (tailHash) { [state setObject:tailHash forKey:@"tailSHA"]; [state setObject:[NSString stringWithFormat:@"%lu", lastOffset] forKey:@"lastOffset"]; }
    result = state;
done:
    if (fd >= 0 && close(fd) != 0) result = nil;
    close(lock); unlink([[path stringByAppendingString:@".lock"] fileSystemRepresentation]);
    if (!result && error && !*error) *error = @"Journal non confirme sur disque. Modifications en memoire conservees."; return result;
}
static BOOL HJClearUnlocked(NSString *path, NSString *baseHash, unsigned int count, NSString **error) {
    NSDictionary *state = HBJournalRead(path, baseHash, error); unsigned long actual = 0;
    BOOL ok = state && HBParseUnsigned([state objectForKey:@"count"], 10000, &actual) && actual == count && ![[state objectForKey:@"recoveredTail"] boolValue];
    struct stat info;
    if (ok && lstat([path fileSystemRepresentation], &info) == 0) ok = HJPrivate(&info) && [[state objectForKey:@"signature"] isEqual:HJSignature(&info)] && unlink([path fileSystemRepresentation]) == 0;
    return ok ? YES : HJError(error, @"Journal conserve : son contenu n'est pas celui du point de consolidation.");
}
BOOL HBJournalClear(NSString *path, NSString *baseHash, unsigned int count, NSString **error) {
    int lock = HJLock(path, error); if (lock < 0) return NO;
    BOOL ok = HJClearUnlocked(path, baseHash, count, error);
    close(lock); unlink([[path stringByAppendingString:@".lock"] fileSystemRepresentation]); return ok;
}
static BOOL HJRemoveReceipt(NSString *path) {
    struct stat info; if (lstat([path fileSystemRepresentation], &info) != 0) return errno == ENOENT;
    return HJPrivate(&info) && unlink([path fileSystemRepresentation]) == 0;
}
HBWallet *HBRestoreWallet(NSString *path, NSDictionary **state, NSString **error) {
    HBWallet *base = [HBWallet walletAtPath:path error:error]; if (!base) return nil;
    NSString *hash = HBDriveSHA256([base baseSourceData]), *journalPath = [path stringByAppendingString:@".panther-journal"], *receiptPath = [path stringByAppendingString:@".panther-commit.plist"];
    NSDictionary *receipt = HBDriveReadState(receiptPath); unsigned long count;
    if (HJHash([receipt objectForKey:@"oldSHA"]) && HJHash([receipt objectForKey:@"newSHA"]) && [[receipt objectForKey:@"newSHA"] isEqualToString:hash] && HBParseUnsigned([receipt objectForKey:@"count"], 10000, &count)) {
        struct stat info;
        if (lstat([journalPath fileSystemRepresentation], &info) == 0 && !HBJournalClear(journalPath, [receipt objectForKey:@"oldSHA"], count, error)) return nil;
        if (!HJRemoveReceipt(receiptPath)) { HJError(error, @"Consolidation terminee, mais recu prive non nettoyable."); return nil; }
    }
    NSDictionary *loaded = HBJournalRead(journalPath, hash, error); if (!loaded) return nil;
    HBWallet *current = [base retain]; NSEnumerator *commands = [[loaded objectForKey:@"commands"] objectEnumerator]; NSDictionary *command;
    while ((command = [commands nextObject])) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; NSString *failure = nil;
        HBWallet *next = [[current walletByApplyingCommand:command error:&failure] retain]; NSString *message = [failure copy];
        [pool release]; [current release]; current = next;
        if (!current) { if (error) *error = [message autorelease]; else [message release]; return nil; } [message release];
    }
    if (state) *state = loaded; return [current autorelease];
}
HBWallet *HBCheckpointWallet(HBWallet *wallet, NSString *path, NSString **error) {
    NSString *hash = HBDriveSHA256([wallet baseSourceData]), *journalPath = [path stringByAppendingString:@".panther-journal"], *receiptPath = [path stringByAppendingString:@".panther-commit.plist"];
    int lock = HJLock(journalPath, error); if (lock < 0) return nil;
    HBWallet *result = nil; NSDictionary *state = HBJournalRead(journalPath, hash, error);
    if (!state || ![[state objectForKey:@"commands"] isEqualToArray:[wallet journalCommands]]) {
        HJError(error, @"Attendre la sauvegarde complete du journal avant de consolider."); goto finished;
    }
    if ([[state objectForKey:@"recoveredTail"] boolValue]) {
        int fd = HJOpen(journalPath, O_RDWR); unsigned long length; HBParseUnsigned([state objectForKey:@"length"], HB_JOURNAL_MAX, &length);
        BOOL repaired = fd >= 0 && ftruncate(fd, length) == 0 && fsync(fd) == 0; if (fd >= 0) close(fd);
        if (!repaired) { HJError(error, @"Derniere trame incomplete non nettoyable. Journal conserve."); goto finished; }
        state = HBJournalRead(journalPath, hash, error); if (!state) goto finished;
    }
    HBWallet *exported = [wallet walletForHomeBankExport:error]; if (!exported) goto finished;
    NSString *newHash = HBDriveSHA256([exported baseSourceData]);
    NSDictionary *receipt = [NSDictionary dictionaryWithObjectsAndKeys:hash, @"oldSHA", newHash, @"newSHA", [state objectForKey:@"count"], @"count", nil];
    if (!HBDriveWriteState(receipt, receiptPath, error) || !HBWriteWallet(exported, path, [wallet baseSourceData], error)) goto finished;
    if (!HJClearUnlocked(journalPath, hash, [[state objectForKey:@"count"] intValue], error) || !HJRemoveReceipt(receiptPath)) goto finished;
    result = exported;
finished:
    close(lock); unlink([[journalPath stringByAppendingString:@".lock"] fileSystemRepresentation]); return result;
}
