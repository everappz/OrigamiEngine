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
{
    long _byteCount;
    long _bytesRead;
    long long _bytesExpected;
    long long _bytesWaitingFromCache;
    dispatch_semaphore_t _downloadingSemaphore;

    BOOL _connectionDidFail;
}

@property (copy, nonatomic) NSString *cachedFilePath;
@property (strong, nonatomic) NSMutableURLRequest *request;
@property (strong, nonatomic) NSFileHandle *fileHandle;
@property (strong, nonatomic) NSURLSession *session;
@property (strong, nonatomic) NSURLSessionTask *sessionTask;

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
    return [_request URL];
}

- (long)size {
    return (long)_bytesExpected;
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.sessionTask resume];
    });

    _bytesExpected = 0;
    _bytesRead    = 0;
    _byteCount     = 0;
    _connectionDidFail = NO;

    [self prepareCache:[NSString stringWithFormat:@"%lx.%@",
                        (unsigned long)[[url absoluteString] hash],
                        url.pathExtension]];

    _downloadingSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_wait(_downloadingSemaphore, DISPATCH_TIME_FOREVER);

    return YES;
}

- (BOOL)seekable {
    return YES;
}

- (BOOL)seek:(long)position whence:(int)whence {
    switch (whence) {
        case SEEK_SET:
            _bytesRead = position;
            break;
        case SEEK_CUR:
            _bytesRead += position;
            break;
        case SEEK_END:
            _bytesRead = (long)_bytesExpected - position;
            break;
    }
    return YES;
}

- (long)tell {
    return _bytesRead;
}

- (int)read:(void *)buffer amount:(int)amount {
    if (_bytesRead + amount > _bytesExpected)
        return 0;

    while(_byteCount < _bytesRead + amount) {
        if (_connectionDidFail) return 0;
        _bytesWaitingFromCache = _bytesRead + amount;
        if (_downloadingSemaphore != NULL) {
            dispatch_semaphore_wait(_downloadingSemaphore, dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC));
        }
    }

    int result = 0;
    @autoreleasepool {
        NSData *data = nil;
        @synchronized(_fileHandle) {
            [_fileHandle seekToFileOffset:_bytesRead];
            data = [_fileHandle readDataOfLength:amount];
        }
        [data getBytes:buffer length:data.length];
        _bytesRead += data.length;

        result = data.length;
    }

    return result;
}

- (void)close {
    [_sessionTask cancel];
    _sessionTask = nil;
    [_session invalidateAndCancel];
    _session = nil;
    [self unprepareCache];
}

#pragma mark - private

+ (dispatch_queue_t)cachingQueue {
    static dispatch_queue_t _cachingQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _cachingQueue = dispatch_queue_create("com.origami.httpcache",
                                              DISPATCH_QUEUE_SERIAL);
    });
    return _cachingQueue;
}

- (void)prepareCache:(NSString*)fileName {
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
    if (session != _session) {
        return;
    }
    
    if (_downloadingSemaphore != NULL) {
        dispatch_semaphore_signal(_downloadingSemaphore);
    }
    
    _connectionDidFail = YES;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    if (task != _sessionTask) {
        return;
    }
    
    if (_downloadingSemaphore != NULL) {
        dispatch_semaphore_signal(_downloadingSemaphore);
    }
    
    if (error != nil) {
        _connectionDidFail = YES;
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    if (dataTask != _sessionTask) {
        return;
    }
    
    _bytesExpected = response.expectedContentLength;
    
    if (_downloadingSemaphore != NULL) {
        dispatch_semaphore_signal(_downloadingSemaphore);
    }
    
    NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;

    if ([_fileHandle seekToEndOfFile] == _bytesExpected) {
        disposition = NSURLSessionResponseCancel;
        _byteCount = (long)_bytesExpected;
    }
    
    if (completionHandler) {
        completionHandler(disposition);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    if (dataTask != _sessionTask) {
        return;
    }
    
    if(_byteCount >= _bytesWaitingFromCache) {
        if (_downloadingSemaphore != NULL) {
            dispatch_semaphore_signal(_downloadingSemaphore);
        }
    }

    if (data && _fileHandle) {
        dispatch_async([HTTPSource cachingQueue], ^{
            @synchronized(_fileHandle) {
                [_fileHandle seekToFileOffset:_byteCount];
                [_fileHandle writeData:data];
            }
            _byteCount += data.length;
        });
    }
}

@end
