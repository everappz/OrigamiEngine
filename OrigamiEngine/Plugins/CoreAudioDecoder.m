//
// CoreAudioDecoder.m
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

#import <unistd.h>
#import <AudioToolbox/AudioToolbox.h>
#import "CoreAudioDecoder.h"

const int ID3V1_SIZE = 128;

@interface CoreAudioDecoder () {
    id<ORGMSource>  _source;
    AudioFileID     _audioFile;
    ExtAudioFileRef _in;
    NSMutableDictionary *_metadata;
    
    int _bitrate;
    int _bitsPerSample;
    int _channels;
    float _frequency;
    long _totalFrames;
}

@end

@implementation CoreAudioDecoder

- (void)dealloc {
    [self close];
}

#pragma mark - ORGMDecoder

+ (NSArray *)fileTypes {
    OSStatus err;
    UInt32 size;
    NSArray *sAudioExtensions;
    
    size = sizeof(sAudioExtensions);
    err  = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AllExtensions, 0, NULL, &size, &sAudioExtensions);
    if (noErr != err) {
        return nil;
    }
    
    return sAudioExtensions;
}

- (NSDictionary *)properties {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:_channels], @"channels",
            [NSNumber numberWithInt:_bitsPerSample], @"bitsPerSample",
            [NSNumber numberWithInt:_bitrate], @"bitrate",
            [NSNumber numberWithFloat:_frequency], @"sampleRate",
            [NSNumber numberWithLong:_totalFrames], @"totalFrames",
            [NSNumber numberWithBool:YES], @"seekable",
            @"big", @"endian",
            nil];
}

- (NSDictionary *)metadata {
    return _metadata;
}

- (int)readAudio:(void *)buf frames:(UInt32)frames {
    OSStatus err;
    AudioBufferList bufferList;
    UInt32 frameCount;
    
    bufferList.mNumberBuffers              = 1;
    bufferList.mBuffers[0].mNumberChannels = _channels;
    bufferList.mBuffers[0].mData           = buf;
    bufferList.mBuffers[0].mDataByteSize   = frames * _channels * (_bitsPerSample/8);
    
    frameCount = frames;
    err        = ExtAudioFileRead(_in, &frameCount, &bufferList);
    if (err != noErr) {
        return 0;
    }
    
    return frameCount;
}

- (BOOL)open:(id<ORGMSource>)source {
    _metadata = [[NSMutableDictionary alloc] init];
    _source = source;
    OSStatus result = AudioFileOpenWithCallbacks((__bridge void * _Nonnull)_source,
                                                 audioFile_ReadProc,
                                                 NULL,
                                                 audioFile_GetSizeProc,
                                                 NULL,
                                                 0,
                                                 &_audioFile);
    
    if (noErr != result) {
        return NO;
    }
    
    result = ExtAudioFileWrapAudioFileID(_audioFile, false, &_in);
    if (noErr != result) {
        return NO;
    }
    
    return [self readInfoFromExtAudioFileRef];
}

- (long)seek:(long)frame {
    OSStatus err;
    
    err = ExtAudioFileSeek(_in, frame);
    if (noErr != err) {
        return -1;
    }
    
    return frame;
}

- (void)close {
    ExtAudioFileDispose(_in);
    AudioFileClose(_audioFile);
    [_source close];
}

- (id<ORGMSource>)source{
    return _source;
}

#pragma mark - Private

- (BOOL)readInfoFromExtAudioFileRef {
    OSStatus err;
    UInt32 size;
    AudioStreamBasicDescription asbd;
    
    size = sizeof(asbd);
    err  = ExtAudioFileGetProperty(_in, kExtAudioFileProperty_FileDataFormat, &size, &asbd);
    if (err != noErr) {
        ExtAudioFileDispose(_in);
        return NO;
    }
    
    _bitrate       = 0;
    _bitsPerSample = asbd.mBitsPerChannel;
    _channels      = asbd.mChannelsPerFrame;
    _frequency     = asbd.mSampleRate;
    
    if(0 == _bitsPerSample) {
        _bitsPerSample = 16;
    }
    
    AudioStreamBasicDescription	result;
    bzero(&result, sizeof(AudioStreamBasicDescription));
    
    result.mFormatID    = kAudioFormatLinearPCM;
    result.mFormatFlags = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsBigEndian;
    
    result.mSampleRate       = _frequency;
    result.mChannelsPerFrame = _channels;
    result.mBitsPerChannel   = _bitsPerSample;
    
    result.mBytesPerPacket  = _channels * (_bitsPerSample / 8);
    result.mFramesPerPacket = 1;
    result.mBytesPerFrame   = _channels * (_bitsPerSample / 8);
    
    err = ExtAudioFileSetProperty(_in, kExtAudioFileProperty_ClientDataFormat, sizeof(result), &result);
    if (noErr != err) {
        ExtAudioFileDispose(_in);
        return NO;
    }
    
    AudioFileID audioFile;
    size = sizeof(AudioFileID);
    err = ExtAudioFileGetProperty(_in, kExtAudioFileProperty_AudioFile, &size, &audioFile);
    
    if (err == noErr) {
        _metadata = [self metadataForFile:audioFile];
    }
    
    Float64 total = 0;
    size = sizeof(total);
    err = AudioFileGetProperty(audioFile, kAudioFilePropertyEstimatedDuration, &size, &total);
    if (err == noErr) {
        _totalFrames = total * _frequency;
    }
    
    return YES;
}

- (NSMutableDictionary *)metadataForFile:(AudioFileID)audioFile {
    
    if ([_source isKindOfClass:NSClassFromString(@"HTTPSource")] &&
        [[[_source url] pathExtension] isEqualToString:@"mp3"])
    {
        uint16_t data;
        [_source seek:0 whence:SEEK_SET];
        [_source read:&data amount:2];
        if (data != 17481) return nil; // ID == 17481
    }
    
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    
    NSDictionary *infoDict = [self getInfoDictionaryForFile:audioFile];
    if (infoDict != nil) {
        [result addEntriesFromDictionary:infoDict];
    }
    
    NSDictionary *id3Dict = [self getID3TagDictionaryForAudioFile:audioFile];
    if (id3Dict != nil) {
        [result addEntriesFromDictionary:id3Dict];
        [CoreAudioDecoder parseStringValueForID3Key:@"TALB" fromDictionary:id3Dict toDictionary:result key:@"album"];
        [CoreAudioDecoder parseStringValueForID3Key:@"TCON" fromDictionary:id3Dict toDictionary:result key:@"genre"];
        [CoreAudioDecoder parseStringValueForID3Key:@"TIT2" fromDictionary:id3Dict toDictionary:result key:@"title"];
        [CoreAudioDecoder parseStringValueForID3Key:@"TPE1" fromDictionary:id3Dict toDictionary:result key:@"artist"];
        [CoreAudioDecoder parseStringValueForID3Key:@"TRCK" fromDictionary:id3Dict toDictionary:result key:@"track number"];
        [CoreAudioDecoder parseStringValueForID3Key:@"TPOS" fromDictionary:id3Dict toDictionary:result key:@"disc number"];
        [CoreAudioDecoder parseNumberValueForID3Key:@"TDRC" fromDictionary:id3Dict toDictionary:result key:@"year"];
        [CoreAudioDecoder parseDictValueForID3Key:@"APIC" ID3DataKey:@"data" fromDictionary:id3Dict toDictionary:result key:@"picture"];
        [CoreAudioDecoder parseDictValueForID3Key:@"COMM" ID3DataKey:@"text" fromDictionary:id3Dict toDictionary:result key:@"comment"];
    }
    
    NSData *picture = [self getAlbumArtworkDataForAudioFile:audioFile];
    if (picture != nil) {
        [result setObject:picture forKey:@"picture"];
    }
    
    return result.count > 0 ? result : nil;
}

+ (void)parseStringValueForID3Key:(NSString *)ID3Key 
                   fromDictionary:(NSDictionary *)fromDict
                     toDictionary:(NSMutableDictionary *)toDictionary
                              key:(NSString *)toKey {
    NSString *value = fromDict[ID3Key];
    if ([value isKindOfClass:[NSString class]] && value.length > 0) {
        [toDictionary setObject:value forKey:toKey];
    }
}

+ (void)parseNumberValueForID3Key:(NSString *)ID3Key
                   fromDictionary:(NSDictionary *)fromDict
                     toDictionary:(NSMutableDictionary *)toDictionary
                              key:(NSString *)toKey {
    NSNumber *value = fromDict[ID3Key];
    if ([value isKindOfClass:[NSNumber class]] && value.unsignedIntValue > 0) {
        [toDictionary setObject:value forKey:toKey];
    }
}

+ (void)parseDictValueForID3Key:(NSString *)ID3Key
                         ID3DataKey:(NSString *)ID3DataKey
                   fromDictionary:(NSDictionary *)fromDict
                     toDictionary:(NSMutableDictionary *)toDictionary
                              key:(NSString *)toKey {
    NSDictionary *topLevelDict = fromDict[ID3Key];
    if (topLevelDict != nil) {
        NSString *lowLevelKey = [[topLevelDict allKeys] lastObject];
        NSDictionary *lowLevelDict = topLevelDict[lowLevelKey];
        if (lowLevelDict != nil) {
            id data = lowLevelDict[ID3DataKey];
            if (data != nil) {
                [toDictionary setObject:data forKey:toKey];
            }
        }
    }
}

- (nullable NSDictionary *)getInfoDictionaryForFile:(AudioFileID)audioFile {
    
    NSDictionary *result = nil;
    UInt32 dataSize = 0;
    OSStatus err;
    
    err = AudioFileGetPropertyInfo(audioFile, kAudioFilePropertyInfoDictionary, &dataSize, 0);
    
    if (err != noErr) return result;
    
    CFDictionaryRef dictionary;
    err = AudioFileGetProperty(audioFile, kAudioFilePropertyInfoDictionary, &dataSize, &dictionary);
    if (err != noErr) return result;
    
    result = [[NSDictionary alloc] initWithDictionary:(__bridge NSDictionary *)dictionary];
    CFRelease(dictionary);
    
    return result;
}


- (nullable NSDictionary *)getID3TagDictionaryForAudioFile:(AudioFileID)inputFile {
    
    //read raw ID3Tag size
    UInt32 id3DataSize = 0;
    char *rawID3Tag = NULL;
    OSStatus err;
    NSDictionary *result = nil;
    
    err = AudioFileGetPropertyInfo(inputFile, kAudioFilePropertyID3Tag, &id3DataSize, NULL);
    
    if (err != noErr) {
        return result;
    }
    
    if (id3DataSize == 0) {
        return result;
    }
    
    rawID3Tag = (char *)malloc(id3DataSize);
    
    err = AudioFileGetProperty(inputFile, kAudioFilePropertyID3Tag, &id3DataSize, rawID3Tag);
    
    if (err != noErr) {
        free(rawID3Tag);
        return result;
    }
    
    CFDictionaryRef piDict = nil;
    UInt32 piDataSize = sizeof(piDict);
    
    err = AudioFormatGetProperty(kAudioFormatProperty_ID3TagToDictionary, id3DataSize, rawID3Tag, &piDataSize, &piDict);
    
    free(rawID3Tag);
    
    if (err != noErr) {
        return result;
    }
    
    NSDictionary *tagsDictionary = (__bridge NSDictionary*)piDict;
    
    NSLog (@"ID3TagDictionary: %@", tagsDictionary);
    
    if (tagsDictionary != nil) {
        result = [[NSDictionary alloc] initWithDictionary:tagsDictionary];
    }
    
    CFRelease(piDict);
    
    return result;
}

- (nullable NSData *)getAlbumArtworkDataForAudioFile:(AudioFileID)audioFile {
    
    UInt32 dataSize = 0;
    NSData *albumArtwork = nil;
    
    OSStatus status = AudioFileGetPropertyInfo(audioFile, kAudioFilePropertyAlbumArtwork, &dataSize, NULL);
    
    if (status == noErr) {
        void *artworkData = malloc(dataSize);
        status = AudioFileGetProperty(audioFile, kAudioFilePropertyAlbumArtwork, &dataSize, artworkData);
        
        if (status == noErr) {
            albumArtwork = [[NSData alloc] initWithBytes:artworkData length:dataSize];
            free(artworkData);
        }
    }
    
    return albumArtwork.length > 512 ? albumArtwork : nil;
}

#pragma mark - callback functions

static OSStatus audioFile_ReadProc(void *inClientData,
                                   SInt64 inPosition,
                                   UInt32 requestCount,
                                   void *buffer,
                                   UInt32 *actualCount) 
{
    id<ORGMSource> source = (__bridge id<ORGMSource>)inClientData;
    
    // Skip potential id3v1 tags over HTTP connection
    if ([NSStringFromClass([source class]) isEqualToString:@"HTTPSource"] &&
        [source size] - inPosition == ID3V1_SIZE) {
        
        *actualCount = ID3V1_SIZE;
        return noErr;
    }
    
    [source seek:(long)inPosition whence:0];
    *actualCount = [source read:buffer amount:requestCount];
    
    return noErr;
}

static SInt64 audioFile_GetSizeProc(void *inClientData) {
    id<ORGMSource> source = (__bridge id<ORGMSource>)inClientData;
    SInt64 len = [source size];
    return len;
}

@end
