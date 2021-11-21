//
//  MBCANRMonitor.h
//  tttttt
//
//  Created by xyl on 2021/7/15.
//  Copyright © 2021 xyl. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBCANRMonitor : NSObject

#pragma mark - 配置

/// 判定卡死阈值 default is 8s
@property (nonatomic, assign) int anrThresholdTime;
/// 检测间隔 default is 1s
@property (nonatomic, assign) float anrMonitorInterval;
/// 达到卡死阈值是否抓栈 default is YES
@property (nonatomic, assign) BOOL shouldCaptureStackWhenStuck;

#pragma mark - 状态信息

/// 当前是否卡住
@property (nonatomic, assign, readonly) BOOL isStucking;
/// 是否监测中
@property (nonatomic, assign, readonly) BOOL isMonitoring;
/// 上次app是否卡死
@property (nonatomic, assign, readonly) BOOL isLastTimeStuck;
/// 上次anr log
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *anrLog;

+ (instancetype)shared;
- (void)beginMonitor;
- (void)endMonitor;

@end

NS_ASSUME_NONNULL_END
