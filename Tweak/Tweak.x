#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "NCMUnlockAPI.h"
#import "SettingsHelper.h"

// Helper: 显示 Toast
static void showToastMessage(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil 
                                                                       message:message 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        [rootVC presentViewController:alert animated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
    });
}

// Hook NSURLSession 拦截网络请求
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    NSString *urlString = request.URL.absoluteString;
    
    // 检查是否是 VIP 歌曲 URL 请求
    if ([urlString containsString:@"song/enhance/player/url"] || 
        [urlString containsString:@"song/enhance/player/url/v1"]) {
        
        NSLog(@"[NCM-Unlock] Intercepting song URL request: %@", urlString);
        
        // 创建新的 completion handler 来替换响应
        void (^newCompletionHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }
            
            // 解析原始响应
            NSError *jsonError;
            NSMutableDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
            
            if (jsonError || !jsonResponse) {
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }
            
            // 检查是否需要替换 URL
            NSArray *songs = jsonResponse[@"data"];
            if ([songs isKindOfClass:[NSArray class]] && songs.count > 0) {
                NSMutableDictionary *songData = [songs[0] mutableCopy];
                NSNumber *code = songData[@"code"];
                NSString *originalUrl = songData[@"url"];
                
                // 如果 code != 200 或 url 为空，说明需要 VIP 权限
                if ([code integerValue] != 200 || !originalUrl || [originalUrl isEqualToString:@""]) {
                    NSLog(@"[NCM-Unlock] Song requires VIP, attempting to get free URL");
                    
                    // 获取歌曲 ID
                    NSString *songId = [NSString stringWithFormat:@"%@", songData[@"id"]];
                    
                    // 使用解锁 API 获取免费 URL
                    [[NCMUnlockAPI sharedInstance] getSongUrl:songId completion:^(NSString *freeUrl, NSString *quality) {
                        if (freeUrl) {
                            // 替换 URL
                            songData[@"url"] = freeUrl;
                            songData[@"code"] = @200;
                            songData[@"br"] = @320000; // 320kbps
                            songData[@"type"] = @"mp3";
                            
                            NSMutableArray *newSongs = [NSMutableArray arrayWithArray:songs];
                            newSongs[0] = songData;
                            jsonResponse[@"data"] = newSongs;
                            
                            // 重新序列化
                            NSData *newData = [NSJSONSerialization dataWithJSONObject:jsonResponse options:0 error:nil];
                            
                            // 显示提示
                            if ([SettingsHelper sharedInstance].showToast) {
                                showToastMessage([NSString stringWithFormat:@"已替换为免费音源 (%@)", quality]);
                            }
                            
                            if (completionHandler) {
                                completionHandler(newData, response, nil);
                            }
                        } else {
                            if (completionHandler) {
                                completionHandler(data, response, error);
                            }
                        }
                    }];
                    return;
                }
            }
            
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };
        
        return %orig(request, newCompletionHandler);
    }
    
    return %orig;
}

%end

// 使用 runtime 方式 hook 设置页面
// 在 %ctor 中使用 method swizzling

%hookf(void, UIApplication, sendAction:to:from:forEvent:, SEL action, id target, id sender, UIEvent *event) {
    %orig;
    
    // 检查是否是设置页面
    if ([target isKindOfClass:NSClassFromString(@"NCMSettingViewController")]) {
        static BOOL added = NO;
        if (!added) {
            added = YES;
            
            UIViewController *settingVC = (UIViewController *)target;
            UIView *selfView = settingVC.view;
            
            // 创建设置入口
            UIView *entryView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, selfView.frame.size.width, 60)];
            entryView.backgroundColor = [UIColor whiteColor];
            entryView.tag = 10086;
            
            // 标题
            UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, selfView.frame.size.width - 32, 24)];
            titleLabel.text = @"NCM Unlock 设置";
            titleLabel.font = [UIFont boldSystemFontOfSize:16];
            titleLabel.textColor = [UIColor blackColor];
            [entryView addSubview:titleLabel];
            
            // 副标题
            UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 32, selfView.frame.size.width - 32, 20)];
            subtitleLabel.text = [NSString stringWithFormat:@"当前音质: %@", [SettingsHelper sharedInstance].qualityName];
            subtitleLabel.font = [UIFont systemFontOfSize:13];
            subtitleLabel.textColor = [UIColor grayColor];
            subtitleLabel.tag = 10087;
            [entryView addSubview:subtitleLabel];
            
            // 点击手势
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:settingVC action:@selector(showNCMUnlockSettings)];
            [entryView addGestureRecognizer:tap];
            
            // 添加到设置页面
            UITableView *tableView = [settingVC valueForKey:@"tableView"];
            if (tableView) {
                UIView *headerView = tableView.tableHeaderView;
                if (headerView) {
                    CGRect frame = entryView.frame;
                    frame.origin.y = headerView.frame.size.height;
                    entryView.frame = frame;
                    
                    UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, selfView.frame.size.width, headerView.frame.size.height + 60)];
                    [containerView addSubview:headerView];
                    [containerView addSubview:entryView];
                    tableView.tableHeaderView = containerView;
                }
            }
            
            // 添加方法
            class_addMethod([settingVC class], @selector(showNCMUnlockSettings), (IMP)showNCMUnlockSettingsIMP, "v@:");
            class_addMethod([settingVC class], @selector(updateQualityLabel), (IMP)updateQualityLabelIMP, "v@:");
        }
    }
}

// 方法实现
void showNCMUnlockSettingsIMP(id self, SEL _cmd) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"NCM Unlock 设置" 
                                                                   message:nil 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 音质选择
    UIAlertAction *standard = [UIAlertAction actionWithTitle:@"标准 128kbps" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SettingsHelper sharedInstance].audioQuality = NCMQualityStandard;
        updateQualityLabelIMP(self, _cmd);
    }];
    
    UIAlertAction *higher = [UIAlertAction actionWithTitle:@"较高 192kbps" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SettingsHelper sharedInstance].audioQuality = NCMQualityHigher;
        updateQualityLabelIMP(self, _cmd);
    }];
    
    UIAlertAction *exhigh = [UIAlertAction actionWithTitle:@"极高 320kbps" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SettingsHelper sharedInstance].audioQuality = NCMQualityExhigh;
        updateQualityLabelIMP(self, _cmd);
    }];
    
    UIAlertAction *lossless = [UIAlertAction actionWithTitle:@"无损 FLAC (最高可用)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SettingsHelper sharedInstance].audioQuality = NCMQualityLossless;
        updateQualityLabelIMP(self, _cmd);
    }];
    
    // Toast 开关
    UIAlertAction *toastAction = [UIAlertAction actionWithTitle:[SettingsHelper sharedInstance].showToast ? @"✓ 显示替换提示" : @"显示替换提示" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SettingsHelper sharedInstance].showToast = ![SettingsHelper sharedInstance].showToast;
    }];
    
    // 取消
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:standard];
    [alert addAction:higher];
    [alert addAction:exhigh];
    [alert addAction:lossless];
    [alert addAction:toastAction];
    [alert addAction:cancel];
    
    [(UIViewController *)self presentViewController:alert animated:YES completion:nil];
}

void updateQualityLabelIMP(id self, SEL _cmd) {
    UIView *selfView = ((UIViewController *)self).view;
    UILabel *label = [selfView viewWithTag:10087];
    if (label) {
        label.text = [NSString stringWithFormat:@"当前音质: %@", [SettingsHelper sharedInstance].qualityName];
    }
}

// 初始化
%ctor {
    %init;
    
    NSLog(@"[NCM-Unlock] Module loaded successfully");
    
    // 初始化设置
    [SettingsHelper sharedInstance];
}
