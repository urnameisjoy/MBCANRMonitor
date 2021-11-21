//
//  MBCANRLogger.m
//  tttttt
//
//  Created by xyl on 2021/8/3.
//  Copyright © 2021 xyl. All rights reserved.
//

#import "MBCANRLogger.h"
#import <CommonCrypto/CommonCrypto.h>

@interface MBCANRLog : NSObject
@property (nonatomic, copy) NSString *log;
@property (nonatomic, copy) NSString *md5;
@property (nonatomic, assign) NSUInteger begin;
@property (nonatomic, assign) NSUInteger end;
@end

@implementation MBCANRLog
@end

static NSUInteger const kMBCANRLoggerCapacity = 10;

static NSString *MBCStringMD5(NSString *string) {
    if (!string) return nil;
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    return [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0],  result[1],  result[2],  result[3],
            result[4],  result[5],  result[6],  result[7],
            result[8],  result[9],  result[10], result[11],
            result[12], result[13], result[14], result[15]];
}

@implementation MBCANRLogger {
    NSString *_anrLogPath;
    NSMutableArray<MBCANRLog *> *_mainThreadLogs;
    NSMutableDictionary<NSString *, id> *_anrLogs;
}

- (instancetype)init {
    if (self = [super init]) {
        _mainThreadLogs = [NSMutableArray arrayWithCapacity:kMBCANRLoggerCapacity];
        _anrLogs = [NSMutableDictionary dictionaryWithCapacity:kMBCANRLoggerCapacity + 1];
        NSString *anrLogDirectory = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"ANRLog"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:anrLogDirectory]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:anrLogDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        }
        _anrLogPath = [anrLogDirectory stringByAppendingPathComponent:@"Log"];
    }
    return self;
}

#pragma mark - public

- (void)addNewLog:(NSString *)logStr anrMoment:(NSUInteger)moment {
    if (!logStr.length) {
        return;
    }
    
    if (!_anrLogs.count) { // 全线程日志
        NSString *all = [NSString stringWithFormat:@"ANR moment:%lu, snapshot:%@", moment, logStr];
        [_anrLogs setValue:all forKey:@"allThreadLog"];
    } else { // 后续主线程日志
        // md5校验是否相同日志
        NSString *md5 = MBCStringMD5(logStr);
        MBCANRLog *lastLog = [_mainThreadLogs lastObject];
        if ([md5 isEqualToString:lastLog.md5]) {
            lastLog.end = moment;
        } else {
            MBCANRLog *log = [MBCANRLog new];
            log.begin = moment;
            log.log = logStr;
            log.md5 = md5;
            if (_mainThreadLogs.count >= kMBCANRLoggerCapacity) {
                [_mainThreadLogs removeObjectAtIndex:0];
            }
            [_mainThreadLogs addObject:log];
        }
        
        [_anrLogs setValue:[self mainThreadLogsOutputLog] forKey:@"mainLogs"];
    }
    [_anrLogs writeToFile:_anrLogPath atomically:YES];
}

- (NSDictionary<NSString *, NSString *> *)readLog {
    if (![[NSFileManager defaultManager] fileExistsAtPath:_anrLogPath]) {
        return nil;
    }
    return [NSDictionary dictionaryWithContentsOfFile:_anrLogPath];
}

- (void)deleteLog {
    [_anrLogs removeAllObjects];
    [_mainThreadLogs removeAllObjects];
    if (![[NSFileManager defaultManager] fileExistsAtPath:_anrLogPath]) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:_anrLogPath error:nil];
}

- (BOOL)hasLog {
    return _anrLogs.count > 0;
}

#pragma mark - private

- (NSDictionary<NSString *, NSString *> *)mainThreadLogsOutputLog {
    NSMutableDictionary *output = [NSMutableDictionary dictionaryWithCapacity:kMBCANRLoggerCapacity];
    [_mainThreadLogs enumerateObjectsUsingBlock:^(MBCANRLog * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *key;
        if (obj.end != 0) {
            key = [NSString stringWithFormat:@"ANR moment:%lu to %lu", obj.begin, obj.end];
        } else {
            key = [NSString stringWithFormat:@"ANR moment:%lu", obj.begin];
        }
        [output setValue:obj.log forKey:key];
    }];
    return output.copy;
}

@end


