#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "NCMUnlockAPI.h"
#import "SettingsHelper.h"

// 网易云音乐版本号
static NSString *const kNCMPackageName = @"com.netease.cloudmusic";

// Hook 网络请求管理器
%hook NCMusicNetworkManager

// 拦截所有网络请求
- (void)sendRequest:(id)request completion:(void (^)(id response, NSError *error))completion {
    // 调用原始方法
    %orig;
}

%end

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
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if ([SettingsHelper sharedInstance].showToast) {
                                    [self showToast:[NSString stringWithFormat:@"已替换为免费音源 (%@)", quality]];
                                }
                            });
                            
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

// Toast 显示方法
%new
- (void)showToast:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

// Hook 设置页面，添加模块设置入口
%hook NCMSettingViewController

- (void)viewDidLoad {
    %orig;
    
    // 添加模块设置入口
    [self addNCMUnlockSettingsEntry];
}

%new
- (void)addNCMUnlockSettingsEntry {
    // 创建设置入口
    UIView *entryView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 60)];
    entryView.backgroundColor = [UIColor whiteColor];
    entryView.tag = 10086;
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, self.view.frame.size.width - 32, 24)];
    titleLabel.text = @"NCM Unlock 设置";
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor blackColor];
    [entryView addSubview:titleLabel];
    
    // 副标题
    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 32, self.view.frame.size.width - 32, 20)];
    subtitleLabel.text = [NSString stringWithFormat:@"当前音质: %@", [SettingsHelper sharedInstance].qualityName];
    subtitleLabel.font = [UIFont systemFontOfSize:13];
    subtitleLabel.textColor = [UIColor grayColor];
    subtitleLabel.tag = 10087;
    [entryView addSubview:subtitleLabel];
    
    // 点击手势
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showNCMUnlockSettings)];
    [entryView addGestureRecognizer:tap];
    
    // 添加到设置页面底部
    UITableView *tableView = [self valueForKey:@"tableView"];
    if (tableView) {
        UIView *headerView = tableView.tableHeaderView;
        if (headerView) {
            // 添加到 header 下面
            CGRect frame = entryView.frame;
            frame.origin.y = headerView.frame.size.height;
            entryView.frame = frame;
            
            UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, headerView.frame.size.height + 60)];
            [containerView addSubview:headerView];
            [containerView addSubview:entryView];
            tableView.tableHeaderView = containerView;
        }
    }
}

%new
- (void)showNCMUnlockSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"NCM Unlock 设置" 
                                                                   message:nil 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 音质选择
    UIAlertAction *standard = [UIAlertAction actionWithTitle:@"标准 128kbps" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SettingsHelper sharedInstance].audioQuality = NCMQualityStandard;
        [self updateQualityLabel];
    }];
    
    UIAlertAction *higher = [UIAlertAction actionWithTitle:@"较高 192kbps" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SettingsHelper sharedInstance].audioQuality = NCMQualityHigher;
        [self updateQualityLabel];
    }];
    
    UIAlertAction *exhigh = [UIAlertAction actionWithTitle:@"极高 320kbps" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SettingsHelper sharedInstance].audioQuality = NCMQualityExhigh;
        [self updateQualityLabel];
    }];
    
    UIAlertAction *lossless = [UIAlertAction actionWithTitle:@"无损 FLAC (最高可用)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [SettingsHelper sharedInstance].audioQuality = NCMQualityLossless;
        [self updateQualityLabel];
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
    
    [self presentViewController:alert animated:YES completion:nil];
}

%new
- (void)updateQualityLabel {
    UILabel *label = [self.view viewWithTag:10087];
    if (label) {
        label.text = [NSString stringWithFormat:@"当前音质: %@", [SettingsHelper sharedInstance].qualityName];
    }
}

%end

// 初始化
%ctor {
    %init;
    
    NSLog(@"[NCM-Unlock] Module loaded successfully");
    
    // 初始化设置
    [SettingsHelper sharedInstance];
}
