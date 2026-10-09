#import <Foundation/Foundation.h>
#import "HBWallet.h"

@protocol HBDriveTransport <NSObject>
- (NSDictionary *)requestURL:(NSString *)url method:(NSString *)method headers:(NSDictionary *)headers body:(NSData *)body error:(NSString **)error;
@end

@interface HBCurlTransport : NSObject <HBDriveTransport> {
    NSString *_curlPath, *_caPath;
}
- (id)initWithSettings:(NSDictionary *)settings;
@end

@interface HBDriveClient : NSObject {
    NSDictionary *_settings, *_testCredentials;
    id<HBDriveTransport> _transport;
    NSString *_token;
    NSDate *_expires;
    BOOL _retryable, _fileUnavailable;
}
- (id)initWithSettings:(NSDictionary *)settings transport:(id<HBDriveTransport>)transport credentials:(NSDictionary *)credentials;
- (NSDictionary *)download:(NSString **)error;
- (NSDictionary *)uploadWallet:(HBWallet *)wallet expectedETag:(NSString *)etag error:(NSString **)error;
- (BOOL)retryable;
- (BOOL)fileUnavailable;
@end

NSDictionary *HBDriveParseJSON(NSData *data, NSString **error);
NSString *HBDriveExceptionMessage(NSException *exception);
NSDictionary *HBDriveCredentials(NSData *data, NSString **error);
BOOL HBDriveValidSettings(NSDictionary *settings, NSString **error);
NSString *HBDriveAssertion(NSDictionary *credentials, NSDate *date, NSString **error);
NSString *HBDriveSHA256(NSData *data);
BOOL HBDriveStoreKey(NSData *data, NSString **alias, NSString **error);
BOOL HBDriveDeleteKey(NSString *alias, NSString **error);
NSString *HBDriveDirectory(NSString **error);
NSData *HBDriveReadPrivateFile(NSString *path, unsigned long maximum, NSString **error);
BOOL HBDriveWriteState(NSDictionary *state, NSString *path, NSString **error);
NSDictionary *HBDriveReadState(NSString *path);
