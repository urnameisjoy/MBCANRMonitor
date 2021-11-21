//
//  ViewController.m
//  MBCANRMonitorDemo
//
//  Created by xyl on 2021/11/21.
//

#import "ViewController.h"
#import "MBCANRMonitor.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self setupUI];
}

- (void)setupUI {
    [self setupStuckButton];
    [self setupLogTextView];
}

- (void)setupStuckButton {
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(10, 100, 100, 40)];
    [button setTitle:@"点我卡死" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(stuck) forControlEvents:UIControlEventTouchUpInside];
    [button setBackgroundColor:[UIColor grayColor]];
    [self.view addSubview:button];
}

- (void)setupLogTextView {
    UITextView *logView = [[UITextView alloc] initWithFrame:CGRectMake(10, 150, 300, 300)];
    if ([MBCANRMonitor shared].isLastTimeStuck) {
        NSDictionary *log = [MBCANRMonitor shared].anrLog;
        if (log) {
            logView.text = [NSString stringWithFormat:@"上次app卡死了, log:\n%@", log];;
        } else {
            logView.text = @"上次app卡死了，但是没抓到堆栈";
        }
    } else {
        logView.text = @"上次app运行期间未卡死，点击卡死按钮，8s后杀掉app重启";
    }
    [self.view addSubview:logView];
}

- (void)stuck {
    void (^dispatchOnceBlock)(void) = ^ {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sleep(2);
            dispatch_sync(dispatch_get_main_queue(), ^{
                NSLog(@"");
            });
        });
    };
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatchOnceBlock();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        dispatchOnceBlock();
    });
}

@end
