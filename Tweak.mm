// ============================================================
//  Tweak.mm — id5hook
//  纯 ObjC++ 内存扫描悬浮窗 (无 Logos / 无 Substrate)
//  通过 TrollFools 注入目标游戏进程
// ============================================================

#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <vector>

// mach/mach_vm.h 在 iOS SDK 中被编译期禁用（#error预处理），运行时始终可用
// 使用 extern "C" 绕过编译期限制
extern "C" {
    kern_return_t mach_vm_read(vm_map_t, mach_vm_address_t,
                               mach_vm_size_t, vm_offset_t *,
                               mach_msg_type_number_t *);
    kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);
}

// ============================================================
//  MARK: - 前向声明
// ============================================================

static void ScanForCellar(void (^completion)(NSString *result));
static void ShowAlert(NSString *message);

// ============================================================
//  MARK: - 安全内存读取
// ============================================================

/// 底层安全读取：使用 mach_vm_read 读取当前进程内存，失败返回非 KERN_SUCCESS
static kern_return_t SafeReadRaw(uint64_t addr, void *outBuf, mach_vm_size_t size) {
    vm_offset_t data = 0;
    mach_msg_type_number_t dataCnt = 0;

    kern_return_t kr = mach_vm_read(mach_task_self(),
                                     (mach_vm_address_t)addr,
                                     size,
                                     &data,
                                     &dataCnt);
    if (kr != KERN_SUCCESS || dataCnt < size) {
        if (data != 0) {
            mach_vm_deallocate(mach_task_self(), data, dataCnt);
        }
        return (kr == KERN_SUCCESS) ? KERN_FAILURE : kr;
    }

    memcpy(outBuf, (const void *)data, size);
    mach_vm_deallocate(mach_task_self(), data, dataCnt);
    return KERN_SUCCESS;
}

/// 读取 int32_t
static bool ReadI32(uint64_t addr, int32_t *outVal) {
    return SafeReadRaw(addr, outVal, sizeof(int32_t)) == KERN_SUCCESS;
}

/// 读取 int64_t / uint64_t
static bool ReadI64(uint64_t addr, uint64_t *outVal) {
    return SafeReadRaw(addr, outVal, sizeof(uint64_t)) == KERN_SUCCESS;
}

/// 读取单精度浮点数
static bool ReadF32(uint64_t addr, float *outVal) {
    return SafeReadRaw(addr, outVal, sizeof(float)) == KERN_SUCCESS;
}

// ============================================================
//  MARK: - 可拖动悬浮按钮
// ============================================================

@interface DragButton : UIButton {
    CGPoint _panStartCenter;
}
@end

@implementation DragButton

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        [self addTarget:self
                 action:@selector(onTap)
       forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview;
    if (!sv) return;

    switch (gr.state) {
        case UIGestureRecognizerStateBegan:
            _panStartCenter = self.center;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint t = [gr translationInView:sv];
            self.center = CGPointMake(_panStartCenter.x + t.x,
                                       _panStartCenter.y + t.y);
            break;
        }
        default:
            break;
    }
}

- (void)onTap {
    self.enabled = NO;
    [self setTitle:@"扫描中…" forState:UIControlStateNormal];

    ScanForCellar(^(NSString *result) {
        self.enabled = YES;
        [self setTitle:@"找地窖" forState:UIControlStateNormal];
        ShowAlert(result);
    });
}

@end

// ============================================================
//  MARK: - 核心扫描逻辑
// ============================================================

static uint64_t GetImageBase(void) {
    return (uint64_t)_dyld_get_image_header(0);
}

static void ScanForCellar(void (^completion)(NSString *result)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableString *output = [NSMutableString string];

        uint64_t base     = GetImageBase();
        uint64_t coreAddr = base + 0x7A5DF30;

        const uint64_t arrayOffsets[] = { 0x90, 0x98, 0xA0, 0xA8, 0xB0 };
        const int      offsetCount    = sizeof(arrayOffsets) / sizeof(arrayOffsets[0]);
        const int      maxIter        = 1000;

        int foundCount = 0;

        for (int oi = 0; oi < offsetCount; oi++) {
            uint64_t arrBase = coreAddr + arrayOffsets[oi];

            for (int i = 0; i < maxIter; i++) {
                uint64_t entityPtr = 0;
                if (!ReadI64(arrBase + (uint64_t)(i * 8), &entityPtr) || entityPtr == 0) {
                    continue;
                }

                int32_t  cmpVal   = 0;
                bool     matched  = false;
                uint64_t matchOff = 0;

                if (ReadI32(entityPtr + 0x3D0, &cmpVal) && cmpVal == 892759396) {
                    matched  = true;
                    matchOff = 0x3D0;
                } else if (ReadI32(entityPtr + 0xD0, &cmpVal) && cmpVal == 892759396) {
                    matched  = true;
                    matchOff = 0xD0;
                }

                if (!matched) continue;

                uint64_t coordStruct = 0;
                if (!ReadI64(entityPtr + 0x28, &coordStruct) || coordStruct == 0) {
                    continue;
                }

                float x = 0.0f, y = 0.0f, z = 0.0f;
                ReadF32(coordStruct + 0x5C, &x);
                ReadF32(coordStruct + 0x60, &y);
                ReadF32(coordStruct + 0x64, &z);

                [output appendFormat:@"#%d  偏移 +0x%llX  "
                                       @"X=%.2f  Y=%.2f  Z=%.2f\n",
                                       foundCount, matchOff, x, y, z];
                foundCount++;
            }
        }

        if (foundCount == 0) {
            [output appendString:@"未找到匹配的地窖坐标"];
        } else {
            [output insertString:[NSString stringWithFormat:@"共找到 %d 个地窖：\n\n", foundCount]
                         atIndex:0];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(output);
        });
    });
}

// ============================================================
//  MARK: - UI 辅助（兼容 iOS 13+ UIScene / iOS 12 keyWindow 回退）
// ============================================================

/// 获取当前活跃的 keyWindow（兼容多 Scene 和旧版）
static UIWindow *GetKeyWindow(void) {
    // iOS 13+: 遍历 connectedScenes 找 foreground active 的 UIWindowScene
    NSSet<UIScene *> *scenes =
        [[UIApplication sharedApplication] connectedScenes];
    for (UIScene *scene in scenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *w in windowScene.windows) {
            if (w.isKeyWindow) {
                return w;
            }
        }
    }
    // 回退：遍历所有 windows（兼容旧版 / 无 Scene 环境）
    for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
        if (w.isKeyWindow) {
            return w;
        }
    }
    return [[UIApplication sharedApplication] windows].firstObject;
}

static UIViewController *TopmostViewController(void) {
    UIViewController *root = GetKeyWindow().rootViewController;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }
    return root;
}

static void ShowAlert(NSString *message) {
    UIViewController *vc = TopmostViewController();
    if (!vc) return;

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"地窖扫描结果"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

static void InstallFloatingButton(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        UIWindow *win = GetKeyWindow();
        if (!win) return;

        DragButton *btn = [[DragButton alloc] initWithFrame:CGRectMake(120, 300, 80, 44)];
        [btn setTitle:@"找地窖" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        btn.layer.cornerRadius = 8.0;
        btn.clipsToBounds = YES;
        btn.layer.borderColor = [UIColor whiteColor].CGColor;
        btn.layer.borderWidth = 1.0;

        [win addSubview:btn];
    });
}

// ============================================================
//  MARK: - 入口点
// ============================================================

__attribute__((constructor))
static void id5hook_entry(void) {
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(__unused NSNotification * _Nonnull note) {
        InstallFloatingButton();
    }];
}
