//
//  MBCANRMonitor.m
//  tttttt
//
//  Created by xyl on 2021/7/15.
//  Copyright © 2021 xyl. All rights reserved.
//

#import "MBCANRMonitor.h"
#import "MBCANRLogger.h"
#import "MBCCallStack.h"

@implementation MBCANRMonitor {
    int _anrTime;
    BOOL _isMonitoring;
    BOOL _isStucking;
    BOOL _isLastTimeStuck;
    dispatch_queue_t _anrMonitorQueue;
    dispatch_semaphore_t _anrMonitorSemaphore;
    CFRunLoopObserverRef _runLoopObserver;
    CFRunLoopActivity _runLoopActivity;
    MBCANRLogger *_logger;
}

NSString * const klastTimeStuckKey = @"MBCANRMonitor.isStuck";

#pragma mark - public

+ (instancetype)shared {
    static id _instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _anrThresholdTime = 8;
        _anrMonitorInterval = 1;
        _shouldCaptureStackWhenStuck = YES;
        _anrMonitorQueue = dispatch_queue_create("com.meiyan.anrMonitor", DISPATCH_QUEUE_CONCURRENT);
        _anrMonitorSemaphore = dispatch_semaphore_create(0);
        _isLastTimeStuck = [[NSUserDefaults standardUserDefaults] boolForKey:klastTimeStuckKey];
        _logger = [MBCANRLogger new];
        _anrLog = [_logger readLog];
        
        [self resumeFromStuckHandle];
    }
    return self;
}

- (void)beginMonitor {
    if (_isMonitoring) {
        return;
    }
    _isMonitoring = YES;
    _anrTime = 0;
    CFRunLoopObserverContext context = {0, (__bridge void *)self, NULL, NULL};
    _runLoopObserver = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, &runLoopObserverCallBack, &context);
    CFRunLoopAddObserver(CFRunLoopGetMain(), _runLoopObserver, kCFRunLoopCommonModes);
    
    dispatch_async(_anrMonitorQueue, ^{
        while (YES) {
            long wait = dispatch_semaphore_wait(self->_anrMonitorSemaphore, dispatch_time(DISPATCH_TIME_NOW, self.anrMonitorInterval * NSEC_PER_SEC));
            if (wait != 0) {
                if (self->_runLoopActivity == kCFRunLoopBeforeSources ||
                    self->_runLoopActivity == kCFRunLoopAfterWaiting) {
                    self->_anrTime += self.anrMonitorInterval;
//                    NSLog(@"anr:%d", self->_anrTime);
                    if (self->_anrTime >= self.anrThresholdTime) {
                        self->_isStucking = YES;
                        [self stuckHandle:self->_anrTime];
                    }
                }
            } else if (self->_anrTime > 0) {
                self->_anrTime = 0;
                self->_isStucking = NO;
                [self resumeFromStuckHandle];
            }
        };
    });
}

- (void)endMonitor {
    _isMonitoring = NO;
    if (!_runLoopObserver) return;
    CFRunLoopRemoveObserver(CFRunLoopGetMain(), _runLoopObserver, kCFRunLoopCommonModes);
    CFRelease(_runLoopObserver);
    _runLoopObserver = NULL;
}

#pragma mark - private

static void runLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info){
    MBCANRMonitor *monitor = (__bridge MBCANRMonitor *)info;
    monitor->_runLoopActivity = activity;
    dispatch_semaphore_signal(monitor->_anrMonitorSemaphore);
}

- (void)stuckHandle:(int)stuckTime {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:klastTimeStuckKey];
//    NSLog(@"anrsave");
    if (_shouldCaptureStackWhenStuck) {
        MBCCallStackType type = [_logger hasLog] ? MBCCallStackTypeMain : MBCCallStackTypeAll;
        NSString *log = [MBCCallStack callStackWithType:type needSymbolicate:NO];
        [_logger addNewLog:log anrMoment:_anrTime];
    }
}

- (void)resumeFromStuckHandle {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:klastTimeStuckKey];
    if (_shouldCaptureStackWhenStuck) {
        [_logger deleteLog];
    }
//    NSLog(@"safe");
}

@end
