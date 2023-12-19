//
// HTTPSource.m
//
// Copyright (c) 2012 ap4y (lod@pisem.net)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "HTTPSource.h"

@interface HTTPSource () <NSURLSessionDelegate, NSURLSessionDataDelegate>

@property (assign, nonatomic) long byteCount;
@property (assign, nonatomic) long bytesRead;
@property (assign, nonatomic) long long bytesExpected;
@property (assign, nonatomic) long long bytesWaitingFromCache;
@property (assign, nonatomic) BOOL connectionDidFail;
@property (strong, nonatomic) dispatch_semaphore_t downloadingSemaphore;
@property (strong, nonatomic) NSMutableURLRequest *request;
@property (strong, nonatomic) NSFileHandle *fileHandle;
@property (strong, nonatomic) NSURLSession *session;
@property (strong, nonatomic) NSURLSessionTask *sessionTask;
@property (copy, nonatomic) NSString *cachedFilePath;

@end

@implementation HTTPSource

const NSTimeInterval readTimeout = 1.0;

- (void)dealloc {
    [self close];
}

#pragma mark - ORGMSource

+ (NSString *)scheme {
    return @"http";
}

- (NSURL *)url {
    return [self.request URL];
}

- (long)size {
    return (long)self.bytesExpected;
}

- (BOOL)open:(NSURL *)url {
    self.request = [NSMutableURLRequest requestWithURL:url];
    [self.request addValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.allowsCellularAccess = YES;
    configuration.timeoutIntervalForRequest = 30.0;
    configuration.HTTPMaximumConnectionsPerHost = 5;
    
    NSOperationQueue *delegateQueue = [[NSOperationQueue alloc] init];
    delegateQueue.maxConcurrentOperationCount = 1;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:delegateQueue];
    
    self.sessionTask = [self.session dataTaskWithRequest:self.request];
    dispatch_async([HTTPSource cachingQueue], ^{
        [self.sessionTask resume];
    });
    
    self.bytesExpected = 0;
    self.bytesRead = 0;
    self.byteCount = 0;
    self.connectionDidFail = NO;
    
    NSString *fileName = [NSString stringWithFormat:@"%@.%@",[NSUUID UUID].UUIDString,url.pathExtension];
    [self prepareCache:fileName];
    
    self.downloadingSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_wait(self.downloadingSemaphore, DISPATCH_TIME_FOREVER);
    
    return YES;
}

- (BOOL)seekable {
    return YES;
}

- (BOOL)seek:(long)position whence:(int)whence {
    switch (whence) {
        case SEEK_SET:
            self.bytesRead = position;
            break;
        case SEEK_CUR:
            self.bytesRead += position;
            break;
        case SEEK_END:
            self.bytesRead = (long)self.bytesExpected - position;
            break;
    }
    return YES;
}

- (long)tell {
    return self.bytesRead;
}

- (int)read:(void *)buffer amount:(int)amount {
    if (self.bytesRead + amount > self.bytesExpected) {
        return 0;
    }
    
    while (self.byteCount < self.bytesRead + amount) {
        if (self.connectionDidFail) {
            return 0;
        }
        
        self.bytesWaitingFromCache = self.bytesRead + amount;
        
        if (self.downloadingSemaphore != NULL) {
            dispatch_semaphore_wait(self.downloadingSemaphore, dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC));
        }
    }
    
    int result = 0;
    
    @autoreleasepool {
        NSData *data = nil;
        @try {
            @synchronized(self.fileHandle) {
                [self.fileHandle seekToFileOffset:self.bytesRead];
                data = [self.fileHandle readDataOfLength:amount];
            }
        } @catch (NSException *exception) {
            NSLog(@"exc: %@",exception);
        }
        
        [data getBytes:buffer length:data.length];
        self.bytesRead += data.length;
        
        result = data.length;
    }
    
    return result;
}

- (void)close {
    [self.sessionTask cancel];
    self.sessionTask = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
    [self unprepareCache];
}

#pragma mark - private

+ (dispatch_queue_t)cachingQueue {
    static dispatch_queue_t cachingQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachingQueue = dispatch_queue_create("com.origami.httpcache", DISPATCH_QUEUE_SERIAL);
    });
    return cachingQueue;
}

- (void)prepareCache:(NSString *)fileName {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *dataPath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"StreamCache"];
    
    NSFileManager *defaultFileManger = [NSFileManager defaultManager];
    
    if (![defaultFileManger fileExistsAtPath:dataPath]) {
        if (![defaultFileManger createDirectoryAtPath:dataPath
                          withIntermediateDirectories:NO
                                           attributes:nil
                                                error:nil]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:NSLocalizedString(@"Unable create cache directory", nil)
                                         userInfo:nil];
        }
    }
    
    NSString *filePath = [dataPath stringByAppendingPathComponent:fileName];
    
    if (![defaultFileManger fileExistsAtPath:filePath]) {
        if (![defaultFileManger createFileAtPath:filePath
                                        contents:nil
                                      attributes:nil]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:NSLocalizedString(@"Unable create cache file", nil)
                                         userInfo:nil];
        }
    }
    
    self.cachedFilePath = filePath;
    self.fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:filePath];
}

- (void)unprepareCache {
    if (self.fileHandle) {
        [self.fileHandle closeFile];
        self.fileHandle = nil;
    }
    
    if (self.cachedFilePath.length > 0) {
        @try{[[NSFileManager defaultManager] removeItemAtPath:self.cachedFilePath error:nil];}
        @catch(NSException *exc){}
        self.cachedFilePath = nil;
    }
}

#pragma mark - NSURLSession delegate

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error {
    if (session != self.session) {
        return;
    }
    
    if (self.downloadingSemaphore != NULL) {
        dispatch_semaphore_signal(self.downloadingSemaphore);
    }
    
    self.connectionDidFail = YES;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    if (task != self.sessionTask) {
        return;
    }
    
    if (self.downloadingSemaphore != NULL) {
        dispatch_semaphore_signal(self.downloadingSemaphore);
    }
    
    if (error != nil) {
        self.connectionDidFail = YES;
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    if (dataTask != self.sessionTask) {
        if (completionHandler) {
            completionHandler(NSURLSessionResponseAllow);
        }
        return;
    }
    
    self.bytesExpected = response.expectedContentLength;
    
    if (self.downloadingSemaphore != NULL) {
        dispatch_semaphore_signal(self.downloadingSemaphore);
    }
    
    if (completionHandler) {
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    if (dataTask != self.sessionTask) {
        return;
    }
    
    if (self.byteCount >= self.bytesWaitingFromCache) {
        if (self.downloadingSemaphore != NULL) {
            dispatch_semaphore_signal(self.downloadingSemaphore);
        }
    }
    
    if (data && self.fileHandle) {
        dispatch_async([HTTPSource cachingQueue], ^{
            @try {
                @synchronized(self.fileHandle) {
                    [self.fileHandle seekToFileOffset:self.byteCount];
                    [self.fileHandle writeData:data];
                }
                self.byteCount += data.length;
            } @catch (NSException *exception) {
                NSLog(@"exc: %@",exception);
            }
        });
    }
}

@end
