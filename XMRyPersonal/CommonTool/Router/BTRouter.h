//
//  BTRouter.h
//  BTFoundation
//
//  Created by skj on 11/31/16.
//  Copyright (c) 2016 XM. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString *const BTRouterParameterPath;
extern NSString *const BTRouterParameterPathToEnd;
extern NSString *const BTRouterParameterURL;
extern NSString *const BTRouterParameterCompletion;
extern NSString *const BTRouterParameterUserInfo;

typedef NS_ENUM(NSUInteger, TaskMode) {
    TaskModeTop = 0, //  a-b-c-a   入栈b     ==> a-b-c-a-b
    TaskModeReplaceTop = 1, // a-b-c 入栈x ==> a-b-x
    TaskModeSingle = 2, // a-b-c-a  入栈b  ==> 先清掉到靠近栈顶b之间的所有元素 （不包括b）, a-b
    TaskModeClear = 3, //  a-b-c-a  入栈b  ==>  先清掉到靠近栈顶b之间的所有元素（包括b）, 得a ,再入栈b, a-b
};

#define ParamPath @"preferPath"
#define ParamQuery @"query"
#define ParamUrl @"url"
#define ParamTaskMode @"task_mode"
#define ParamContainerStyle @"container_style"

/**
 *  routerParameters 里内置的几个参数会用到上面定义的 string
 */
typedef void (^BTRouterHandler)(NSMutableDictionary *routerParameters);

/**
 *  需要返回一个 object，配合 objectForURL: 使用
 */
typedef id (^BTRouterObjectHandler)(NSMutableDictionary *routerParameters);

typedef BOOL(^SpeicalSchemeHandler)(NSString *url);

@interface BTRouter : NSObject


/**
 *  配置URL拦截器block
 */
+(void)configInterceptorBlock:(BOOL (^)(NSString *originUrl))interceptor;
/**
 *  配置app scheme
 */
+(void)configAppScheme:(NSString *)scheme;
/**
 *  配置未找到URL对应handler的block
 */
+(void)configNotFoundHandlerBlock:(BOOL (^)(NSString *originUrl))block;

///特殊Scheme的URL的handler
+(void)configSpeicalSchemeHandler:(SpeicalSchemeHandler)block;
+(SpeicalSchemeHandler)getSpeicalSchemeHandler;

/**
 *  注册 URLPattern 对应的 Handler，在 handler 中可以初始化 VC，然后对 VC 做各种操作
 *
 *  @param URLPattern 带上 scheme，如 BT://beauty/:id
 *  @param handler    该 block 会传一个字典，包含了注册的 URL 中对应的变量。
 *                    假如注册的 URL 为 BT://beauty/:id 那么，就会传一个 @{@"id": 4} 这样的字典过来
 */
+ (void)registerURLPattern:(NSString *)URLPattern toHandler:(BTRouterHandler)handler;

/**
 *  注册 URLPattern 对应的 ObjectHandler，需要返回一个 object 给调用方
 *
 *  @param URLPattern 带上 scheme，如 BT://beauty/:id
 *  @param handler    该 block 会传一个字典，包含了注册的 URL 中对应的变量。
 *                    假如注册的 URL 为 BT://beauty/:id 那么，就会传一个 @{@"id": 4} 这样的字典过来
 *                    自带的 key 为 @"url" 和 @"completion" (如果有的话)
 */
+ (void)registerURLPattern:(NSString *)URLPattern toObjectHandler:(BTRouterObjectHandler)handler;

/**
 *  取消注册某个 URL Pattern
 *
 *  @param URLPattern
 */
+ (void)deregisterURLPattern:(NSString *)URLPattern;

/**
 *  打开此 URL
 *  会在已注册的 URL -> Handler 中寻找，如果找到，则执行 Handler
 *
 *  @param URL 带 Scheme，如 BT://beauty/3
 */
+ (void)openURL:(NSString *)URL;

/**
 *  打开此 URL，同时当操作完成时，执行额外的代码
 *
 *  @param URL        带 Scheme 的 URL，如 BT://beauty/4
 *  @param completion URL 处理完成后的 callback，完成的判定跟具体的业务相关
 */
+ (void)openURL:(NSString *)URL completion:(void (^)(id result))completion;

/**
 *  打开此 URL，带上附加信息，同时当操作完成时，执行额外的代码
 *
 *  @param URL        带 Scheme 的 URL，如 BT://beauty/4
 *  @param parameters 附加参数
 *  @param completion URL 处理完成后的 callback，完成的判定跟具体的业务相关
 */
+ (void)openURL:(NSString *)URL withUserInfo:(NSMutableDictionary *)userInfo completion:(void (^)(id result))completion;

/**
 * 查找谁对某个 URL 感兴趣，如果有的话，返回一个 object
 *
 *  @param URL
 */
+ (id)objectForURL:(NSString *)URL;

/**
 * 查找谁对某个 URL 感兴趣，如果有的话，返回一个 object
 *
 *  @param URL
 *  @param userInfo
 */
+ (id)objectForURL:(NSString *)URL withUserInfo:(NSMutableDictionary *)userInfo;

/**
 *  是否可以打开URL
 *
 *  @param URL
 *
 *  @return
 */
+ (BOOL)canOpenURL:(NSString *)URL;
+(BOOL)isInnerSchemeUrl:(NSString *)url;

/**
 *  调用此方法来拼接 urlpattern 和 parameters
 *
 *  #define BT_ROUTE_BEAUTY @"beauty/:id"
 *  [BTRouter generateURLWithPattern:BT_ROUTE_BEAUTY, @[@13]];
 *
 *
 *  @param pattern    url pattern 比如 @"beauty/:id"
 *  @param parameters 一个数组，数量要跟 pattern 里的变量一致
 *
 *  @return
 */
+ (NSString *)generateURLWithPattern:(NSString *)pattern parameters:(NSArray *)parameters;
+ (void)handleOpenUrlVc:(UIViewController *)vc routerParameters:(NSDictionary *)routerParameters navContainer:(UINavigationController *)nav;
@end
