//
//  BTRouter.m
//  BTFoundation
//
//  Created by chenhaibo on 11/31/16.
//  Copyright (c) 2016 XM. All rights reserved.
//

#import "BTRouter.h"
#import <objc/runtime.h>

static NSString * const BT_ROUTER_WILDCARD_CHARACTER = @"~";
static NSString *specialCharacters = @"/?&.";

NSString *const BTRouterParameterString = @"BTRouterParameter";
NSString *const BTRouterParameterPath = @"BTRouterParameterPath";
NSString *const BTRouterParameterPathToEnd = @"BTRouterParameterPathToEnd";
NSString *const BTRouterParameterURL = @"BTRouterParameterURL";
NSString *const BTRouterParameterCompletion = @"BTRouterParameterCompletion";
NSString *const BTRouterParameterUserInfo = @"BTRouterParameterUserInfo";



@interface BTRouter ()
/**
 *  保存了所有已注册的 URL
 *  结构类似 @{@"beauty": @{@":id": {@"_", [block copy]}}}
 */
@property (nonatomic) NSMutableDictionary *routes;

/**
 *  拦截器block
 *  YES,URL有问题，执行拦截。
 */
@property (nonatomic,copy)BOOL (^interceptor)(NSString *originUrl);

/**
 *  not found url handler block
 */
@property (nonatomic,copy)BOOL (^notFoundHandlerBlock)(NSString *originUrl);
@property (nonatomic,copy)SpeicalSchemeHandler speicalSchemeHandler;

@property (nonatomic,strong) NSString *appScheme;

@end

@implementation BTRouter

+ (instancetype)sharedInstance
{
    static BTRouter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+(void)configInterceptorBlock:(BOOL (^)(NSString *originUrl))interceptor{
    [[BTRouter sharedInstance] setInterceptor:interceptor];
}

+(void)configAppScheme:(NSString *)scheme{
    [[BTRouter sharedInstance] setAppScheme:scheme];
}

+(void)configNotFoundHandlerBlock:(BOOL (^)(NSString *originUrl))block{
    [[BTRouter sharedInstance] setNotFoundHandlerBlock:block];
}

+(void)configSpeicalSchemeHandler:(SpeicalSchemeHandler)block{
    [[BTRouter sharedInstance] setSpeicalSchemeHandler:block];
}

+(SpeicalSchemeHandler)getSpeicalSchemeHandler{
    return [[BTRouter sharedInstance] speicalSchemeHandler];
}

+ (void)registerURLPattern:(NSString *)URLPattern toHandler:(BTRouterHandler)handler
{
    [[self sharedInstance] addURLPattern:URLPattern andHandler:handler];
}

+ (void)deregisterURLPattern:(NSString *)URLPattern
{
    [[self sharedInstance] removeURLPattern:URLPattern];
}

+ (void)openURL:(NSString *)URL
{
    [self openURL:URL completion:nil];
}

+ (void)openURL:(NSString *)URL completion:(void (^)(id result))completion
{
    [self openURL:URL withUserInfo:nil completion:completion];
}

+ (void)openURL:(NSString *)URL withUserInfo:(NSMutableDictionary *)userInfo completion:(void (^)(id result))completion
{
    NSURL *theURL = [NSURL URLWithString:URL];
    if (!theURL) {
        URL = [URL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }
    ///拦截URL，执行检查
    if ([[self sharedInstance] interceptor]) {
        BTRouter *router = [self sharedInstance];
        if(router.interceptor(URL)){
            return;
        }
    }
    if ([self canOpenURL:URL]) {
        NSMutableDictionary *parameters = [[self sharedInstance] extractParametersFromURL:URL];
        [parameters enumerateKeysAndObjectsUsingBlock:^(id key, NSString *obj, BOOL *stop) {
            if ([obj isKindOfClass:[NSString class]]) {
                parameters[key] = [obj stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            }
        }];
        if (completion) {
            parameters[BTRouterParameterCompletion] = completion;
        }
        ///将解析出来的参数添加到userinfo字典中
        if (userInfo == nil) {
            userInfo = [NSMutableDictionary new];
        }
        else if (![userInfo respondsToSelector:@selector(setObject:forKey:)]) {
            userInfo = userInfo.mutableCopy;
        }
        for (id key in parameters.allKeys) {
            if ([key isKindOfClass:[NSString class]]) {
                if (![key containsString:BTRouterParameterString]) {
                    [userInfo setObject:parameters[key] forKey:key];
                }
            }
        }
        parameters[BTRouterParameterUserInfo] = userInfo;
        BTRouterHandler handler = parameters[@"block"];
        if (handler) {
            [parameters removeObjectForKey:@"block"];
            handler(parameters);
        }
    }else{
        [self invailedUrlHandler:URL];
    }
}

+(void)invailedUrlHandler:(NSString *)url{
    if ([[self sharedInstance] notFoundHandlerBlock]) {
        BTRouter *router = [self sharedInstance];
        router.notFoundHandlerBlock(url);
    }
}



+ (BOOL)canOpenURL:(NSString *)URL
{
    if (URL) {
        NSMutableDictionary *parameters = [[self sharedInstance] extractParametersFromURL:URL];
        BTRouterHandler handler = parameters[@"block"];
        if (handler) {
            return YES;
        }else{
            return NO;
        }
    }else{
        return NO;
    }
}

+(BOOL)isInnerSchemeUrl:(NSString *)url{
    if([url hasPrefix:[NSString stringWithFormat:@"%@://",[[BTRouter sharedInstance] appScheme]]]){
        return YES;
    }else{
        return NO;
    }
}

+ (NSString *)generateURLWithPattern:(NSString *)pattern parameters:(NSArray *)parameters
{
    NSInteger startIndexOfColon = 0;
    
    NSMutableArray *placeholders = [NSMutableArray array];
    
    for (int i = 0; i < pattern.length; i++) {
        NSString *character = [NSString stringWithFormat:@"%c", [pattern characterAtIndex:i]];
        if ([character isEqualToString:@":"]) {
            startIndexOfColon = i;
        }
        if ([specialCharacters rangeOfString:character].location != NSNotFound && i > (startIndexOfColon + 1) && startIndexOfColon) {
            NSRange range = NSMakeRange(startIndexOfColon, i - startIndexOfColon);
            NSString *placeholder = [pattern substringWithRange:range];
            if (![self checkIfContainsSpecialCharacter:placeholder]) {
                [placeholders addObject:placeholder];
                startIndexOfColon = 0;
            }
        }
        if (i == pattern.length - 1 && startIndexOfColon) {
            NSRange range = NSMakeRange(startIndexOfColon, i - startIndexOfColon + 1);
            NSString *placeholder = [pattern substringWithRange:range];
            if (![self checkIfContainsSpecialCharacter:placeholder]) {
                [placeholders addObject:placeholder];
            }
        }
    }
    
    __block NSString *parsedResult = pattern;
    
    [placeholders enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        idx = parameters.count > idx ? idx : parameters.count - 1;
        parsedResult = [parsedResult stringByReplacingOccurrencesOfString:obj withString:parameters[idx]];
    }];
    
    return parsedResult;
}

+ (id)objectForURL:(NSString *)URL withUserInfo:(NSMutableDictionary *)userInfo
{
    BTRouter *router = [BTRouter sharedInstance];
    
    URL = [URL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *parameters = [router extractParametersFromURL:URL];
    BTRouterObjectHandler handler = parameters[@"block"];
    if (handler) {
        if (userInfo == nil) {
            userInfo = [NSMutableDictionary new];
        }
        for (id key in parameters.allKeys) {
            if ([key isKindOfClass:[NSString class]]) {
                if (![key containsString:BTRouterParameterString]) {
                    [userInfo setObject:parameters[key] forKey:key];
                }
            }
        }
        parameters[BTRouterParameterUserInfo] = userInfo;
        [parameters removeObjectForKey:@"block"];
        return handler(parameters);
    }
    return nil;
}

+ (id)objectForURL:(NSString *)URL
{
    return [self objectForURL:URL withUserInfo:nil];
}

+ (void)registerURLPattern:(NSString *)URLPattern toObjectHandler:(BTRouterObjectHandler)handler
{
    [[self sharedInstance] addURLPattern:URLPattern andObjectHandler:handler];
}

- (void)addURLPattern:(NSString *)URLPattern andHandler:(BTRouterHandler)handler
{
    NSMutableDictionary *subRoutes = [self addURLPattern:URLPattern];
    if (handler && subRoutes && ![BTRouter isBlankString:URLPattern]) {
        subRoutes[@"_"] = [handler copy];
    }
}

- (void)addURLPattern:(NSString *)URLPattern andObjectHandler:(BTRouterObjectHandler)handler
{
    NSMutableDictionary *subRoutes = [self addURLPattern:URLPattern];
    if (handler && subRoutes && ![BTRouter isBlankString:URLPattern]) {
        subRoutes[@"_"] = [handler copy];
    }
}

- (NSMutableDictionary *)addURLPattern:(NSString *)URLPattern
{
    NSArray *pathComponents = [self pathComponentsFromURL:URLPattern];
    
    NSInteger index = 0;
    NSMutableDictionary* subRoutes = self.routes;
    
    while (index < pathComponents.count) {
        NSString* pathComponent = pathComponents[index];
        if (![subRoutes objectForKey:pathComponent]) {
            subRoutes[pathComponent] = [[NSMutableDictionary alloc] init];
        }
        subRoutes = subRoutes[pathComponent];
        index++;
    }
    return subRoutes;
}

#pragma mark - Utils

- (NSMutableDictionary *)extractParametersFromURL:(NSString *)url
{
    if (![NSURL URLWithString:url]) {
        url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }
    NSMutableDictionary* parameters = [NSMutableDictionary dictionary];
    parameters[BTRouterParameterURL] = url;
    parameters[BTRouterParameterPath] = [[NSURL URLWithString:url] path];
    if (parameters[BTRouterParameterPath]) {
        NSRange range = [url rangeOfString:parameters[BTRouterParameterPath]];
        if (range.location != NSNotFound) {
            parameters[BTRouterParameterPathToEnd] = [url substringFromIndex:range.location];
        }
    }
    NSMutableDictionary* subRoutes = self.routes;
    NSArray* pathComponents = [self pathComponentsFromURL:url];
    
    BOOL found = NO;
    for (NSString* pathComponent in pathComponents) {
        
        // 对 key 进行排序，这样可以把 ~ 放到最后
        NSArray *subRoutesKeys =[subRoutes.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
            return [obj1 compare:obj2];
        }];
        
        for (NSString* key in subRoutesKeys) {
            if ([key isEqualToString:pathComponent] || [key isEqualToString:BT_ROUTER_WILDCARD_CHARACTER]) {
                found = YES;
                subRoutes = subRoutes[key];
                break;
            } else if ([key hasPrefix:@":"]) {
                found = YES;
                subRoutes = subRoutes[key];
                NSString *newKey = [key substringFromIndex:1];
                NSString *newPathComponent = pathComponent;
                // 再做一下特殊处理，比如 :id.html -> :id
                if ([self.class checkIfContainsSpecialCharacter:key]) {
                    NSCharacterSet *specialCharacterSet = [NSCharacterSet characterSetWithCharactersInString:specialCharacters];
                    NSRange range = [key rangeOfCharacterFromSet:specialCharacterSet];
                    if (range.location != NSNotFound) {
                        // 把 pathComponent 后面的部分也去掉
                        newKey = [newKey substringToIndex:range.location - 1];
                        NSString *suffixToStrip = [key substringFromIndex:range.location];
                        newPathComponent = [newPathComponent stringByReplacingOccurrencesOfString:suffixToStrip withString:@""];
                    }
                }
                parameters[newKey] = newPathComponent;
                break;
            }
        }
        
        // 如果没有找到该 pathComponent 对应的 handler，则以上一层的 handler 作为 fallback
        if (!found && !subRoutes[@"_"]) {
            return nil;
        }
    }
    
    // Extract Params From Query.
    NSArray* pathInfo = [url componentsSeparatedByString:@"?"];
    if (pathInfo.count > 1) {
        NSString* parametersString = [pathInfo objectAtIndex:1];
        NSArray* paramStringArr = [parametersString componentsSeparatedByString:@"&"];
        for (NSString* paramString in paramStringArr) {
            NSArray* paramArr = [paramString componentsSeparatedByString:@"="];
            if (paramArr.count > 1) {
                NSString* key = [paramArr objectAtIndex:0];
                NSString* value = [paramArr objectAtIndex:1];
                parameters[key] = value;
            }
        }
    }
    
    if (subRoutes[@"_"]) {
        parameters[@"block"] = [subRoutes[@"_"] copy];
    }
    
    return parameters;
}

- (void)removeURLPattern:(NSString *)URLPattern
{
    NSMutableArray *pathComponents = [NSMutableArray arrayWithArray:[self pathComponentsFromURL:URLPattern]];
    
    // 只删除该 pattern 的最后一级
    if (pathComponents.count >= 1) {
        // 假如 URLPattern 为 a/b/c, components 就是 @"a.b.c" 正好可以作为 KVC 的 key
        NSString *components = [pathComponents componentsJoinedByString:@"."];
        NSMutableDictionary *route = [self.routes valueForKeyPath:components];
        
        if (route.count >= 1) {
            NSString *lastComponent = [pathComponents lastObject];
            [pathComponents removeLastObject];
            
            // 有可能是根 key，这样就是 self.routes 了
            route = self.routes;
            if (pathComponents.count) {
                NSString *componentsWithoutLast = [pathComponents componentsJoinedByString:@"."];
                route = [self.routes valueForKeyPath:componentsWithoutLast];
            }
            [route removeObjectForKey:lastComponent];
        }
    }
}

- (NSArray*)pathComponentsFromURL:(NSString*)URL
{
    NSMutableArray *pathComponents = [NSMutableArray array];
    if ([URL rangeOfString:@"://"].location != NSNotFound) {
        NSArray *pathSegments = [URL componentsSeparatedByString:@"://"];
        // 如果 URL 包含协议，那么把协议作为第一个元素放进去
        [pathComponents addObject:[pathSegments firstObject]];
        
        // 如果只有协议，那么放一个占位符
        if (pathSegments.count == 1) {
            [pathComponents addObject:BT_ROUTER_WILDCARD_CHARACTER];
        }
    }
    if ([[NSURL URLWithString:URL] path]) {
        [pathComponents addObject:[[NSURL URLWithString:URL] path]];
    }
    return [pathComponents copy];
}

- (NSMutableDictionary *)routes
{
    if (!_routes) {
        _routes = [[NSMutableDictionary alloc] init];
    }
    return _routes;
}

#pragma mark - Utils

+ (BOOL)checkIfContainsSpecialCharacter:(NSString *)checkedString {
    NSCharacterSet *specialCharactersSet = [NSCharacterSet characterSetWithCharactersInString:specialCharacters];
    return [checkedString rangeOfCharacterFromSet:specialCharactersSet].location != NSNotFound;
}

+ (BOOL) isBlankString:(NSString *)string {
    if (string == nil || string == NULL) {
        return YES;
    }
    if ([string isKindOfClass:[NSNull class]]) {
        return YES;
    }
    if ([string isKindOfClass:[NSString class]]) {
        if ([[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length]==0) {
            return YES;
        }
    }
    return NO;
}
+ (void)handleOpenUrlVc:(UIViewController *)vc routerParameters:(NSDictionary *)routerParameters navContainer:(UINavigationController *)nav{
    ///取taskmode，进入taskmode处理逻辑
    NSDictionary *userInfo = routerParameters[BTRouterParameterUserInfo];
    NSNumber* task_mode = userInfo[ParamTaskMode];
    void(^completion)(id result) = routerParameters[BTRouterParameterCompletion];
    if (completion) {
        if ([vc respondsToSelector:@selector(task_mode)]) {
            [vc setValue:task_mode forKey:ParamTaskMode];
        }
        completion(vc);
    } else {
        if ([task_mode integerValue] == TaskModeClear) {
            NSMutableArray *vcs = [[nav viewControllers] mutableCopy];
            __block NSInteger targetIndex = -1;
            [vcs enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if([NSStringFromClass([obj class]) isEqualToString:NSStringFromClass([vc class])]){
                    targetIndex = idx;
                    *stop = YES;
                }
            }];
            if (targetIndex != -1) {
                [vcs removeObjectsInRange:NSMakeRange(targetIndex, vcs.count-targetIndex)];
            }
            [vcs addObject:vc];
            [nav setViewControllers:vcs animated:YES];
        }else if([task_mode integerValue] == TaskModeSingle){
            NSMutableArray *vcs = [[nav viewControllers] mutableCopy];
            __block NSInteger targetIndex = -1;
            [vcs enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    if([NSStringFromClass([obj class]) isEqualToString:NSStringFromClass([vc class])]){
                        targetIndex = idx;
                        *stop = YES;
                    }
            }];
            if (targetIndex != -1) {
                [nav popToViewController:[vcs objectAtIndex:targetIndex] animated:YES];
            }else{
                [nav pushViewController:vc animated:YES];
            }
        }else if ([task_mode integerValue] == TaskModeReplaceTop){
            NSMutableArray *vcs = [[nav viewControllers] mutableCopy];
            [[[vcs lastObject] navigationController] setNavigationBarHidden:NO animated:NO];
            [vcs removeLastObject];
            [vcs addObject:vc];
            [nav setViewControllers:vcs animated:YES];
        }else{
            [nav pushViewController:vc animated:YES];
        }
    }
}

@end
