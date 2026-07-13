#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
    });
}

// Hook NSURLSession - 拦截所有 dataTask 方法
%hook NSURLSession

// 方法1: dataTaskWithRequest:
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSString *urlString = request.URL.absoluteString;
    
    if ([urlString containsString:@"song/enhance/player/url"] || 
        [urlString containsString:@"song/enhance/player/url/v1"] ||
        [urlString containsString:@"eapi/song/enhance/player"]) {
        
        NSLog(@"[NCM-Unlock] Found song request: %@", urlString);
        showToastMessage([NSString stringWithFormat:@"[NCM-Unlock] 拦截到歌曲请求: %@", urlString.length > 30 ? [urlString substringToIndex:30] : urlString]);
        
        // 包装 completionHandler
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                if (completionHandler) completionHandler(data, response, error);
                return;
            }
            
            NSError *jsonError;
            NSMutableDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
            
            if (jsonError || !json) {
                if (completionHandler) completionHandler(data, response, error);
                return;
            }
            
            NSLog(@"[NCM-Unlock] Response: %@", json);
            
            // 检查是否需要替换
            NSArray *songs = json[@"data"];
            if ([songs isKindOfClass:[NSArray class]] && songs.count > 0) {
                NSMutableDictionary *song = [songs[0] mutableCopy];
                NSNumber *code = song[@"code"];
                NSString *url = song[@"url"];
                
                if ([code integerValue] != 200 || !url || url.length == 0) {
                    NSLog(@"[NCM-Unlock] Song needs VIP, id=%@", song[@"id"]);
                    showToastMessage([NSString stringWithFormat:@"[NCM-Unlock] 歌曲需要VIP, id=%@", song[@"id"]]);
                    
                    // 尝试获取免费URL
                    NSString *songId = [NSString stringWithFormat:@"%@", song[@"id"]];
                    [[NCMUnlockAPI sharedInstance] getSongUrl:songId completion:^(NSString *freeUrl, NSString *quality) {
                        if (freeUrl) {
                            song[@"url"] = freeUrl;
                            song[@"code"] = @200;
                            song[@"br"] = @320000;
                            NSMutableArray *newSongs = [NSMutableArray arrayWithArray:songs];
                            newSongs[0] = song;
                            json[@"data"] = newSongs;
                            NSData *newData = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
                            
                            if ([SettingsHelper sharedInstance].showToast) {
                                showToastMessage([NSString stringWithFormat:@"已替换为免费音源 (%@)", quality]);
                            }
                            
                            if (completionHandler) completionHandler(newData, response, nil);
                        } else {
                            if (completionHandler) completionHandler(data, response, error);
                        }
                    }];
                    return;
                }
            }
            
            if (completionHandler) completionHandler(data, response, error);
        };
        
        return %orig(request, newHandler);
    }
    
    return %orig;
}

// 方法2: dataTaskWithURL:
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSString *urlString = url.absoluteString;
    
    if ([urlString containsString:@"song/enhance/player/url"] || 
        [urlString containsString:@"song/enhance/player/url/v1"] ||
        [urlString containsString:@"eapi/song/enhance/player"]) {
        
        NSLog(@"[NCM-Unlock] Found song request via URL: %@", urlString);
        showToastMessage([NSString stringWithFormat:@"[NCM-Unlock] 拦截到歌曲请求(URL): %@", urlString.length > 30 ? [urlString substringToIndex:30] : urlString]);
        
        // 包装 completionHandler
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                if (completionHandler) completionHandler(data, response, error);
                return;
            }
            
            NSError *jsonError;
            NSMutableDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
            
            if (jsonError || !json) {
                if (completionHandler) completionHandler(data, response, error);
                return;
            }
            
            NSLog(@"[NCM-Unlock] Response: %@", json);
            
            // 检查是否需要替换
            NSArray *songs = json[@"data"];
            if ([songs isKindOfClass:[NSArray class]] && songs.count > 0) {
                NSMutableDictionary *song = [songs[0] mutableCopy];
                NSNumber *code = song[@"code"];
                NSString *songUrl = song[@"url"];
                
                if ([code integerValue] != 200 || !songUrl || songUrl.length == 0) {
                    NSLog(@"[NCM-Unlock] Song needs VIP, id=%@", song[@"id"]);
                    showToastMessage([NSString stringWithFormat:@"[NCM-Unlock] 歌曲需要VIP, id=%@", song[@"id"]]);
                    
                    // 尝试获取免费URL
                    NSString *songId = [NSString stringWithFormat:@"%@", song[@"id"]];
                    [[NCMUnlockAPI sharedInstance] getSongUrl:songId completion:^(NSString *freeUrl, NSString *quality) {
                        if (freeUrl) {
                            song[@"url"] = freeUrl;
                            song[@"code"] = @200;
                            song[@"br"] = @320000;
                            NSMutableArray *newSongs = [NSMutableArray arrayWithArray:songs];
                            newSongs[0] = song;
                            json[@"data"] = newSongs;
                            NSData *newData = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
                            
                            if ([SettingsHelper sharedInstance].showToast) {
                                showToastMessage([NSString stringWithFormat:@"已替换为免费音源 (%@)", quality]);
                            }
                            
                            if (completionHandler) completionHandler(newData, response, nil);
                        } else {
                            if (completionHandler) completionHandler(data, response, error);
                        }
                    }];
                    return;
                }
            }
            
            if (completionHandler) completionHandler(data, response, error);
        };
        
        return %orig(url, newHandler);
    }
    
    return %orig;
}

%end

// 初始化
%ctor {
    %init;
    
    NSLog(@"[NCM-Unlock] Module loaded successfully");
    
    // 初始化设置
    [SettingsHelper sharedInstance];
    
    // 测试 Toast
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        showToastMessage(@"[NCM-Unlock] 模块已加载");
    });
}
