//
//  MBCANRLogger.h
//  tttttt
//
//  Created by xyl on 2021/8/3.
//  Copyright © 2021 xyl. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBCANRLogger : NSObject

/// 添加新的卡顿时刻日志
/// @param logStr 日志
/// @param moment 当时卡顿时刻
- (void)addNewLog:(NSString *)logStr anrMoment:(NSUInteger)moment;
/// 删除日志
- (void)deleteLog;
/// 读取日志
- (nullable NSDictionary<NSString *, NSString *> *)readLog;
/// 是否已有日志
- (BOOL)hasLog;

@end

NS_ASSUME_NONNULL_END
