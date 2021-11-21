//
//  MBCCallStack.h
//  tttttt
//
//  Created by xyl on 2021/7/28.
//  Copyright © 2021 xyl. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MBCCallStackType) {
    MBCCallStackTypeCurrent,    /**< 当前线程 */
    MBCCallStackTypeAll,        /**< 全部线程 */
    MBCCallStackTypeMain        /**< 主线程 */
};

@interface MBCCallStack : NSObject

/// 抓取指定线程调用栈
/// @param type 线程类型
/// @param symbolicate 是否需要符号解析
+ (NSString *)callStackWithType:(MBCCallStackType)type needSymbolicate:(BOOL)symbolicate;

@end

NS_ASSUME_NONNULL_END
