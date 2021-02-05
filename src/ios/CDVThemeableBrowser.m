/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVThemeableBrowser.h"

#if __has_include("CDVWKProcessPoolFactory.h")
#import "CDVWKProcessPoolFactory.h"
#endif

#import <Cordova/CDVPluginResult.h>

#define    kThemeableBrowserTargetSelf @"_self"
#define    kThemeableBrowserTargetSystem @"_system"
#define    kThemeableBrowserTargetBlank @"_blank"

#define    kThemeableBrowserToolbarBarPositionBottom @"bottom"
#define    kThemeableBrowserToolbarBarPositionTop @"top"

#define    kThemeableBrowserAlignLeft @"left"
#define    kThemeableBrowserAlignRight @"right"

#define    kThemeableBrowserPropEvent @"event"
#define    kThemeableBrowserPropLabel @"label"
#define    kThemeableBrowserPropColor @"color"
#define    kThemeableBrowserPropHeight @"height"
#define    kThemeableBrowserPropImage @"image"
#define    kThemeableBrowserPropWwwImage @"wwwImage"
#define    kThemeableBrowserPropImagePressed @"imagePressed"
#define    kThemeableBrowserPropWwwImagePressed @"wwwImagePressed"
#define    kThemeableBrowserPropWwwImageDensity @"wwwImageDensity"
#define    kThemeableBrowserPropStaticText @"staticText"
#define    kThemeableBrowserPropShowProgress @"showProgress"
#define    kThemeableBrowserPropProgressBgColor @"progressBgColor"
#define    kThemeableBrowserPropProgressColor @"progressColor"
#define    kThemeableBrowserPropShowPageTitle @"showPageTitle"
#define    kThemeableBrowserPropSize @"size"
#define    kThemeableBrowserPropShowFirstTime @"showFirstTime"
#define    kThemeableBrowserPropAlign @"align"
#define    kThemeableBrowserPropTitle @"title"
#define    kThemeableBrowserPropCancel @"cancel"
#define    kThemeableBrowserPropItems @"items"

#define    kThemeableBrowserEmitError @"ThemeableBrowserError"
#define    kThemeableBrowserEmitWarning @"ThemeableBrowserWarning"
#define    kThemeableBrowserEmitCodeCritical @"critical"
#define    kThemeableBrowserEmitCodeLoadFail @"loadfail"
#define    kThemeableBrowserEmitCodeUnexpected @"unexpected"
#define    kThemeableBrowserEmitCodeUndefined @"undefined"

#define    IAB_BRIDGE_NAME @"cordova_iab"

#define    TOOLBAR_DEF_HEIGHT 44.0
#define    LOCATIONBAR_HEIGHT 21.0
#define    FOOTER_HEIGHT ((TOOLBAR_HEIGHT) + (LOCATIONBAR_HEIGHT))
#define    TAG_SALT 100
#define SCREEN_WIDTH ([[UIScreen mainScreen] bounds].size.width)
#define SCREEN_HEIGHT ([[UIScreen mainScreen] bounds].size.height)

#pragma mark CDVThemeableBrowser

@interface CDVThemeableBrowser () {
    BOOL _isShown;
    int _framesOpened;  // number of frames opened since the last time browser exited
    NSURL *initUrl;  // initial URL ThemeableBrowser opened with
    NSURL *originalUrl;
}
@property (nonatomic,strong) dispatch_source_t timer;

@end

@implementation CDVThemeableBrowser

#ifdef __CORDOVA_4_0_0
- (void)pluginInitialize
{
    _isShown = NO;
    _framesOpened = 0;
    _callbackIdPattern = nil;
}
#else
- (CDVThemeableBrowser*)initWithWebView:(WKWebView*)theWebView
{
    self = [super initWithWebView:theWebView];
    if (self != nil) {
        _isShown = NO;
        _framesOpened = 0;
        _callbackIdPattern = nil;
    }

    return self;
}
#endif

- (void)onReset
{
    [self close:nil];
}

- (void)close:(CDVInvokedUrlCommand*)command
{
    if (self.themeableBrowserViewController == nil) {
        [self emitWarning:kThemeableBrowserEmitCodeUnexpected
              withMessage:@"Close called but already closed."];
        return;
    }

    dispatch_source_cancel(_timer);
    // Things are cleaned up in browserExit.
    [self.themeableBrowserViewController close];
}

- (BOOL) isSystemUrl:(NSURL*)url
{
  NSDictionary *systemUrls = @{
    @"itunes.apple.com": @YES,
    @"search.itunes.apple.com": @YES,
    @"appsto.re": @YES
  };

  if (systemUrls[[url host]]) {
    return YES;
  }

  return NO;
}

- (void)open:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult;

    NSString* url = [command argumentAtIndex:0];
    NSString* target = [command argumentAtIndex:1 withDefault:kThemeableBrowserTargetSelf];
    NSString* options = [command argumentAtIndex:2 withDefault:@"" andClass:[NSString class]];

    self.callbackId = command.callbackId;

    if (url != nil) {
#ifdef __CORDOVA_4_0_0
        NSURL* baseUrl = [self.webViewEngine URL];
#else
        NSURL* baseUrl = [self.webView.request URL];
#endif
        NSURL* absoluteUrl = [[NSURL URLWithString:url relativeToURL:baseUrl] absoluteURL];

        initUrl = absoluteUrl;

        if ([self isSystemUrl:absoluteUrl]) {
            target = kThemeableBrowserTargetSystem;
        }

        if ([target isEqualToString:kThemeableBrowserTargetSelf]) {
            [self openInCordovaWebView:absoluteUrl withOptions:options];
        } else if ([target isEqualToString:kThemeableBrowserTargetSystem]) {
            [self openInSystem:absoluteUrl];
        } else { // _blank or anything else
            [self openInThemeableBrowser:absoluteUrl withOptions:options];
        }

        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"incorrect number of arguments"];
    }

    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    NSTimeInterval delayTime=3.0f;
    NSTimeInterval timeInterval=1.0f;
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_time_t startDelayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayTime * NSEC_PER_SEC));
    dispatch_source_set_timer(_timer, startDelayTime, timeInterval * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(_timer, ^{
        CDVPluginResult* pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    });
    dispatch_resume(_timer);
}

- (void)reload:(CDVInvokedUrlCommand*)command
{
    if (self.themeableBrowserViewController) {
        [self.themeableBrowserViewController reload];
    }
}

- (void)changeButtonImage:(CDVInvokedUrlCommand *)command {
    if (self.themeableBrowserViewController) {
        NSInteger buttonIndex = [[command.arguments objectAtIndex:0] integerValue];
        NSDictionary* buttonProps = [command.arguments objectAtIndex:1];;
        [self.themeableBrowserViewController changeButtonImage:buttonIndex buttonProps:buttonProps];
    }
}
    
- (CDVThemeableBrowserOptions*)parseOptions:(NSString*)options
{
    CDVThemeableBrowserOptions* obj = [[CDVThemeableBrowserOptions alloc] init];

    if (options && [options length] > 0) {
        // Min support, iOS 5. We will use the JSON parser that comes with iOS
        // 5.
        NSError *error = nil;
        NSData *data = [options dataUsingEncoding:NSUTF8StringEncoding];
        id jsonObj = [NSJSONSerialization
                      JSONObjectWithData:data
                      options:0
                      error:&error];

        if(error) {
            [self emitError:kThemeableBrowserEmitCodeCritical
                withMessage:[NSString stringWithFormat:@"Invalid JSON %@", error]];
        } else if([jsonObj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = jsonObj;
            for (NSString *key in dict) {
                if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                    [obj setValue:dict[key] forKey:key];
                }
            }
        }
    } else {
        [self emitWarning:kThemeableBrowserEmitCodeUndefined
            withMessage:@"No config was given, defaults will be used, which is quite boring."];
    }

    return obj;
}

- (void)openInThemeableBrowser:(NSURL*)url withOptions:(NSString*)options
{
    [UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleLightContent;
    CDVThemeableBrowserOptions* browserOptions = [self parseOptions:options];

    // Among all the options, there are a few that ThemedBrowser would like to
    // disable, since ThemedBrowser's purpose is to provide an integrated look
    // and feel that is consistent across platforms. We'd do this hack to
    // minimize changes from the original ThemeableBrowser so when merge from the
    // ThemeableBrowser is needed, it wouldn't be super pain in the ass.
    browserOptions.toolbarposition = kThemeableBrowserToolbarBarPositionTop;

    if (browserOptions.clearcache) {
        NSHTTPCookie *cookie;
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (cookie in [storage cookies])
        {
            if (![cookie.domain isEqual: @".^filecookies^"]) {
                [storage deleteCookie:cookie];
            }
        }
    }

    if (browserOptions.clearsessioncache) {
        NSHTTPCookie *cookie;
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (cookie in [storage cookies])
        {
            if (![cookie.domain isEqual: @".^filecookies^"] && cookie.isSessionOnly) {
                [storage deleteCookie:cookie];
            }
        }
    }

    if (self.themeableBrowserViewController == nil) {
        self.themeableBrowserViewController = [[CDVThemeableBrowserViewController alloc]
                                               initWithBrowserOptions: browserOptions
                                               navigationDelete:self
                                               statusBarStyle:[UIApplication sharedApplication].statusBarStyle
                                               settings:self.commandDelegate.settings];
        
        if ([self.viewController conformsToProtocol:@protocol(CDVScreenOrientationDelegate)]) {
            self.themeableBrowserViewController.orientationDelegate = (UIViewController <CDVScreenOrientationDelegate>*)self.viewController;
        }
    }

    [self.themeableBrowserViewController showLocationBar:browserOptions.location];
    [self.themeableBrowserViewController showToolBar:YES:browserOptions.toolbarposition];
    if (browserOptions.closebuttoncaption != nil) {
        // [self.themeableBrowserViewController setCloseButtonTitle:browserOptions.closebuttoncaption];
    }
    // Set Presentation Style
    UIModalPresentationStyle presentationStyle = UIModalPresentationFullScreen; // default
    if (browserOptions.presentationstyle != nil) {
        if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"pagesheet"]) {
            presentationStyle = UIModalPresentationPageSheet;
        } else if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"formsheet"]) {
            presentationStyle = UIModalPresentationFormSheet;
        }
    }
    self.themeableBrowserViewController.modalPresentationStyle = presentationStyle;

    // Set Transition Style
    UIModalTransitionStyle transitionStyle = UIModalTransitionStyleCoverVertical; // default
    if (browserOptions.transitionstyle != nil) {
        if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"fliphorizontal"]) {
            transitionStyle = UIModalTransitionStyleFlipHorizontal;
        } else if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"crossdissolve"]) {
            transitionStyle = UIModalTransitionStyleCrossDissolve;
        }
    }
    self.themeableBrowserViewController.modalTransitionStyle = transitionStyle;

    // prevent webView from bouncing
    if (browserOptions.disallowoverscroll) {
        if ([self.themeableBrowserViewController.webView respondsToSelector:@selector(scrollView)]) {
            ((UIScrollView*)[self.themeableBrowserViewController.webView scrollView]).bounces = NO;
        } else {
            for (id subview in self.themeableBrowserViewController.webView.subviews) {
                if ([[subview class] isSubclassOfClass:[UIScrollView class]]) {
                    ((UIScrollView*)subview).bounces = NO;
                }
            }
        }
    }
    
    // Todo: options need to be updated based on WKWebView which are not directly translatable from UIWebView

    // UIWebView options
    
    //self.themeableBrowserViewController.webView.scalesPageToFit = browserOptions.zoom;
    //self.themeableBrowserViewController.webView.mediaPlaybackRequiresUserAction = browserOptions.mediaplaybackrequiresuseraction;
    //self.themeableBrowserViewController.webView.allowsInlineMediaPlayback = browserOptions.allowinlinemediaplayback;
    //if (IsAtLeastiOSVersion(@"6.0")) {
        //self.themeableBrowserViewController.webView.keyboardDisplayRequiresUserAction = browserOptions.keyboarddisplayrequiresuseraction;
        //self.themeableBrowserViewController.webView.suppressesIncrementalRendering = browserOptions.suppressesincrementalrendering;
   // }

    self.themeableBrowserViewController.webView.navigationDelegate = self;
    [self.themeableBrowserViewController navigateTo:url];
    if (!browserOptions.hidden) {
        [self show:nil withAnimation:!browserOptions.disableAnimation];
    }
}

- (void)show:(CDVInvokedUrlCommand*)command
{
    [self show:command withAnimation:YES];
}

- (void)show:(CDVInvokedUrlCommand*)command withAnimation:(BOOL)animated
{
    if (self.themeableBrowserViewController == nil) {
        [self emitWarning:kThemeableBrowserEmitCodeUnexpected
              withMessage:@"Show called but already closed."];
        return;
    }
    if (_isShown) {
        [self emitWarning:kThemeableBrowserEmitCodeUnexpected
              withMessage:@"Show called but already shown"];
        return;
    }

    _isShown = YES;

    CDVThemeableBrowserNavigationController* nav = [[CDVThemeableBrowserNavigationController alloc]
                                   initWithRootViewController:self.themeableBrowserViewController];
    nav.orientationDelegate = self.themeableBrowserViewController;
    nav.navigationBarHidden = YES;
    nav.modalPresentationStyle = self.themeableBrowserViewController.modalPresentationStyle;
    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.themeableBrowserViewController != nil) {
            [self.viewController presentViewController:nav animated:animated completion:nil];
        }
    });
}

- (void)hide:(CDVInvokedUrlCommand*)command
{
    if (self.themeableBrowserViewController != nil) {
        [[self.themeableBrowserViewController presentingViewController] dismissViewControllerAnimated:YES completion:nil];
        _isShown = NO;
    }
}

- (void)openInCordovaWebView:(NSURL*)url withOptions:(NSString*)options
{
    NSURLRequest* request = [NSURLRequest requestWithURL:url];

#ifdef __CORDOVA_4_0_0
    // the webview engine itself will filter for this according to <allow-navigation> policy
    // in config.xml for cordova-ios-4.0
    [self.webViewEngine loadRequest:request];
#else
    if ([self.commandDelegate URLIsWhitelisted:url]) {
        [self.webView loadRequest:request];
    } else { // this assumes the openInThemeableBrowser can be excepted from the white-list
        [self openInThemeableBrowser:url withOptions:options];
    }
#endif
}

- (void)openInSystem:(NSURL*)url
{
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url];
    } else { // handle any custom schemes to plugins
        [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:url]];
    }
}

// This is a helper method for the inject{Script|Style}{Code|File} API calls, which
// provides a consistent method for injecting JavaScript code into the document.
//
// If a wrapper string is supplied, then the source string will be JSON-encoded (adding
// quotes) and wrapped using string formatting. (The wrapper string should have a single
// '%@' marker).
//
// If no wrapper is supplied, then the source string is executed directly.

- (void)injectDeferredObject:(NSString*)source withWrapper:(NSString*)jsWrapper
{
    // Ensure a message handler bridge is created to communicate with the CDVThemeableBrowserViewController
    [self evaluateJavaScript: [NSString stringWithFormat:@"(function(w){if(!w._cdvMessageHandler) {w._cdvMessageHandler = function(id,d){w.webkit.messageHandlers.%@.postMessage({d:d, id:id});}}})(window)", IAB_BRIDGE_NAME]];

    if (jsWrapper != nil) {
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:@[source] options:0 error:nil];
        NSString* sourceArrayString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        if (sourceArrayString) {
            NSString* sourceString = [sourceArrayString substringWithRange:NSMakeRange(1, [sourceArrayString length] - 2)];
            NSString* jsToInject = [NSString stringWithFormat:jsWrapper, sourceString];
            [self evaluateJavaScript:jsToInject];
        }
    } else {
        [self evaluateJavaScript:source];
    }
}

//Synchronus helper for javascript evaluation
- (void)evaluateJavaScript:(NSString *)script {
    __block NSString* _script = script;
    [self.themeableBrowserViewController.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error == nil) {
            if (result != nil) {
                NSLog(@"%@", result);
            }
        } else {
            NSLog(@"evaluateJavaScript error : %@ : %@", error.localizedDescription, _script);
        }
    }];
}

- (void)injectScriptCode:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper = nil;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"_cdvMessageHandler('%@',JSON.stringify([eval(%%@)]));", command.callbackId];
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectScriptFile:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('script'); c.src = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('script'); c.src = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleCode:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('style'); c.innerHTML = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('style'); c.innerHTML = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleFile:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('link'); c.rel='stylesheet', c.type='text/css'; c.href = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (BOOL)isValidCallbackId:(NSString *)callbackId
{
    NSError *err = nil;
    // Initialize on first use
    if (self.callbackIdPattern == nil) {
        self.callbackIdPattern = [NSRegularExpression regularExpressionWithPattern:@"^ThemeableBrowser[0-9]{1,10}$" options:0 error:&err];
        if (err != nil) {
            // Couldn't initialize Regex; No is safer than Yes.
            return NO;
        }
    }
    if ([self.callbackIdPattern firstMatchInString:callbackId options:0 range:NSMakeRange(0, [callbackId length])]) {
        return YES;
    }
    return NO;
}

/**
 * The iframe bridge provided for the ThemeableBrowser is capable of executing any oustanding callback belonging
 * to the ThemeableBrowser plugin. Care has been taken that other callbacks cannot be triggered, and that no
 * other code execution is possible.
 *
 * To trigger the bridge, the iframe (or any other resource) should attempt to load a url of the form:
 *
 * gap-iab://<callbackId>/<arguments>
 *
 * where <callbackId> is the string id of the callback to trigger (something like "ThemeableBrowser0123456789")
 *
 * If present, the path component of the special gap-iab:// url is expected to be a URL-escaped JSON-encoded
 * value to pass to the callback. [NSURL path] should take care of the URL-unescaping, and a JSON_EXCEPTION
 * is returned if the JSON is invalid.
 */


//- (BOOL)webView:(WKWebView*)theWebView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType
//{
//    NSURL* url = request.URL;
//    BOOL isTopLevelNavigation = [request.URL isEqual:[request mainDocumentURL]];
//
//    // See if the url uses the 'gap-iab' protocol. If so, the host should be the id of a callback to execute,
//    // and the path, if present, should be a JSON-encoded value to pass to the callback.
//    if ([[url scheme] isEqualToString:@"gap-iab"]) {
//        NSString* scriptCallbackId = [url host];
//        CDVPluginResult* pluginResult = nil;
//
//        if ([self isValidCallbackId:scriptCallbackId]) {
//            NSString* scriptResult = [url path];
//            NSError* __autoreleasing error = nil;
//
//            // The message should be a JSON-encoded array of the result of the script which executed.
//            if ((scriptResult != nil) && ([scriptResult length] > 1)) {
//                scriptResult = [scriptResult substringFromIndex:1];
//                NSData* decodedResult = [NSJSONSerialization JSONObjectWithData:[scriptResult dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
//                if ((error == nil) && [decodedResult isKindOfClass:[NSArray class]]) {
//                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:(NSArray*)decodedResult];
//                } else {
//                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_JSON_EXCEPTION];
//                }
//            } else {
//                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[]];
//            }
//            [self.commandDelegate sendPluginResult:pluginResult callbackId:scriptCallbackId];
//            return NO;
//        }
//    } else if ([self isSystemUrl:url]) {
//      // Do not allow iTunes store links from ThemeableBrowser as they do not work
//      // instead open them with App Store app or Safari
//      [[UIApplication sharedApplication] openURL:url];
//
//      // only in the case where a redirect link is opened in a freshly started
//      // ThemeableBrowser frame, trigger ThemeableBrowserRedirectExternalOnOpen
//      // event. This event can be handled in the app-side -- for instance, to
//      // close the ThemeableBrowser as the frame will contain a blank page
//      if (
//        originalUrl != nil
//        && [[originalUrl absoluteString] isEqualToString:[initUrl absoluteString]]
//        && _framesOpened == 1
//      ) {
//        NSDictionary *event = @{
//          @"type": @"ThemeableBrowserRedirectExternalOnOpen",
//          @"message": @"ThemeableBrowser redirected to open an external app on fresh start"
//        };
//
//        [self emitEvent:event];
//      }
//
//      // do not load content in the web view since this URL is handled by an
//      // external app
//      return NO;
//    } else if ((self.callbackId != nil) && isTopLevelNavigation) {
//        // Send a loadstart event for each top-level navigation (includes redirects).
//        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
//                                                      messageAsDictionary:@{@"type":@"loadstart", @"url":[url absoluteString]}];
//        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
//
//        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
//    }
//
//    // originalUrl is used to detect redirect. This works by storing the
//    // request URL of the original frame when it's about to be loaded. A redirect
//    // will cause shouldStartLoadWithRequest to be called again before the
//    // original frame finishes loading (originalUrl becomes nil upon the frame
//    // finishing loading). On second time shouldStartLoadWithRequest
//    // is called, this stored original frame's URL can be compared against
//    // the URL of the new request. A mismatch implies redirect.
//    originalUrl = request.URL;
//
//    return YES;
//}

- (void)webViewDidStartLoad:(WKWebView*)theWebView
{
    _framesOpened++;
}


- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSURLRequest *request = navigationAction.request;

    NSURL* url = request.URL;
    NSURL* mainDocumentURL = request.mainDocumentURL;
    BOOL isTopLevelNavigation = [url isEqual:mainDocumentURL];
    BOOL shouldStart = YES;
    
    //if is an app store link, let the system handle it, otherwise it fails to load it
    if ([[ url scheme] isEqualToString:@"itms-appss"] || [[ url scheme] isEqualToString:@"itms-apps"]) {
        [webView stopLoading];
        [self openInSystem:url];
        shouldStart = NO;
    } else if ([self isSystemUrl:url]) {
        // Do not allow iTunes store links from ThemeableBrowser as they do not work
        // instead open them with App Store app or Safari
        [webView stopLoading];
        [self openInSystem:url];
        
        // only in the case where a redirect link is opened in a freshly started
        // ThemeableBrowser frame, trigger ThemeableBrowserRedirectExternalOnOpen
        // event. This event can be handled in the app-side -- for instance, to
        // close the ThemeableBrowser as the frame will contain a blank page
        if (
            originalUrl != nil
            && [[originalUrl absoluteString] isEqualToString:[initUrl absoluteString]]
            && _framesOpened == 1
            ) {
            NSDictionary *event = @{
                                    @"type": @"ThemeableBrowserRedirectExternalOnOpen",
                                    @"message": @"ThemeableBrowser redirected to open an external app on fresh start"
                                    };
            
            [self emitEvent:event];
        }
        
        // do not load content in the web view since this URL is handled by an
        // external app
        shouldStart = NO;
    } else if ((self.callbackId != nil) && isTopLevelNavigation) {
        self.themeableBrowserViewController.currentURL = request.URL;
        // Send a loadstart event for each top-level navigation (includes redirects).
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstart", @"url":[url absoluteString]}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
    
    if(shouldStart){
        // Fix GH-417 & GH-424: Handle non-default target attribute
        // Based on https://stackoverflow.com/a/25713070/777265
        if (!navigationAction.targetFrame){
            [webView loadRequest:navigationAction.request];
            decisionHandler(WKNavigationActionPolicyCancel);
        }else{

            // originalUrl is used to detect redirect. This works by storing the
            // request URL of the original frame when it's about to be loaded. A redirect
            // will cause shouldStartLoadWithRequest to be called again before the
            // original frame finishes loading (originalUrl becomes nil upon the frame
            // finishing loading). On second time shouldStartLoadWithRequest
            // is called, this stored original frame's URL can be compared against
            // the URL of the new request. A mismatch implies redirect.
            originalUrl = request.URL;

            decisionHandler(WKNavigationActionPolicyAllow);
        }
    }else{
        decisionHandler(WKNavigationActionPolicyCancel);
    }
}

#pragma mark WKScriptMessageHandler delegate
- (void)userContentController:(nonnull WKUserContentController *)userContentController didReceiveScriptMessage:(nonnull WKScriptMessage *)message {
    
    CDVPluginResult* pluginResult = nil;
    
    if([message.body isKindOfClass:[NSDictionary class]]){
        NSDictionary* messageContent = (NSDictionary*) message.body;
        NSString* scriptCallbackId = messageContent[@"id"];
        
        if([messageContent objectForKey:@"d"]){
            NSString* scriptResult = messageContent[@"d"];
            NSError* __autoreleasing error = nil;
            NSData* decodedResult = [NSJSONSerialization JSONObjectWithData:[scriptResult dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
            if ((error == nil) && [decodedResult isKindOfClass:[NSArray class]]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:(NSArray*)decodedResult];
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_JSON_EXCEPTION];
            }
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[]];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:scriptCallbackId];
    }else if(self.callbackId != nil){
        // Send a message event
        NSString* messageContent = (NSString*) message.body;
        NSError* __autoreleasing error = nil;
        NSData* decodedResult = [NSJSONSerialization JSONObjectWithData:[messageContent dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
        if (error == nil) {
            NSMutableDictionary* dResult = [NSMutableDictionary new];
            [dResult setValue:@"message" forKey:@"type"];
            [dResult setObject:decodedResult forKey:@"data"];
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dResult];
            [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        }
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (self.callbackId != nil) {
        NSString* url = [webView.URL absoluteString];
        if(url == nil){
            if(self.themeableBrowserViewController.currentURL != nil){
                url = [self.themeableBrowserViewController.currentURL absoluteString];
            }else{
                url = @"";
            }
        }

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstop", @"url":url}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];

        // once a web view finished loading a frame, reset the stored original
        // URL of the frame so that it can be used to detect next redirection
        originalUrl = nil;

        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}


- (void)webView:(WKWebView*)theWebView didFailLoadWithError:(NSError*)error
{
    if (self.callbackId != nil) {
        NSString* url = [self.themeableBrowserViewController.currentURL absoluteString];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsDictionary:@{@"type":@"loaderror", @"url":url, @"code": [NSNumber numberWithInteger:error.code], @"message": error.localizedDescription}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)browserExit
{
    if (self.callbackId != nil) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"exit"}];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
    }
    // Set navigationDelegate to nil to ensure no callbacks are received from it.
    self.themeableBrowserViewController.navigationDelegate = nil;
    // Don't recycle the ViewController since it may be consuming a lot of memory.
    // Also - this is required for the PDF/User-Agent bug work-around.
    self.themeableBrowserViewController = nil;
    self.callbackId = nil;
    self.callbackIdPattern = nil;

    _framesOpened = 0;
    _isShown = NO;
}

- (void)emitEvent:(NSDictionary*)event
{
    if (self.callbackId != nil) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:event];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)emitError:(NSString*)code withMessage:(NSString*)message
{
    NSDictionary *event = @{
        @"type": kThemeableBrowserEmitError,
        @"code": code,
        @"message": message
    };

    [self emitEvent:event];
}

- (void)emitWarning:(NSString*)code withMessage:(NSString*)message
{
    NSDictionary *event = @{
       @"type": kThemeableBrowserEmitWarning,
       @"code": code,
       @"message": message
    };

    [self emitEvent:event];
}

@end

#pragma mark CDVThemeableBrowserViewController

@implementation CDVThemeableBrowserViewController

@synthesize currentURL;

- (id)initWithBrowserOptions:(CDVThemeableBrowserOptions*) browserOptions navigationDelete:(CDVThemeableBrowser*) navigationDelegate statusBarStyle:(UIStatusBarStyle) statusBarStyle settings:(NSDictionary*) settings
{
    self = [super init];
    if (self != nil) {
        _browserOptions = browserOptions;
        _settings = settings;
        //_webViewDelegate = [[CDVWKWebViewUIDelegate alloc] init];
        


//#ifdef __CORDOVA_9_0_0
////        _webViewDelegate = [[kCDVWebViewEngineWKUIDelegate alloc] initWithDelegate:self];
////        _webNavigationDelegate = [[kCDVWebViewEngineWKNavigationDelegate alloc] initwithDelegate:self];
//
////#else
////        _webViewDelegate = [[kCDVWebViewEngineWKUIDelegate alloc] initWithDelegate:self];
////        _webNavigationDelegate = [[kCDVWebViewEngineWKNavigationDelegate alloc] initwithDelegate:self];
//#endif
        _navigationDelegate = navigationDelegate;
        _statusBarStyle = statusBarStyle;
        [self createViews];
    }

    return self;
}

- (void)createViews
{
    // We create the views in code for primarily for ease of upgrades and not requiring an external .xib to be included

    CGRect webViewBounds = self.view.bounds;
    BOOL toolbarIsAtBottom = ![_browserOptions.toolbarposition isEqualToString:kThemeableBrowserToolbarBarPositionTop];
    NSDictionary* toolbarProps = _browserOptions.toolbar;
    CGFloat toolbarHeight = [self getFloatFromDict:toolbarProps withKey:kThemeableBrowserPropHeight withDefault:TOOLBAR_DEF_HEIGHT];
    if (!_browserOptions.fullscreen) {
        webViewBounds.size.height -= toolbarHeight;
    }
    WKUserContentController* userContentController = [[WKUserContentController alloc] init];
    
    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];

    NSString *userAgent = configuration.applicationNameForUserAgent;
    if (
        [self settingForKey:@"OverrideUserAgent"] == nil &&
        _browserOptions.customUserAgent == nil &&
        [self settingForKey:@"AppendUserAgent"] != nil
        ) {
        userAgent = [NSString stringWithFormat:@"%@ %@", userAgent, [self settingForKey:@"AppendUserAgent"]];
    }
    configuration.applicationNameForUserAgent = userAgent;
    configuration.userContentController = userContentController;
#if __has_include("CDVWKProcessPoolFactory.h")
    configuration.processPool = [[CDVWKProcessPoolFactory sharedFactory] sharedProcessPool];
#endif
    [configuration.userContentController addScriptMessageHandler:self name:IAB_BRIDGE_NAME];
    
    //WKWebView options
    configuration.allowsInlineMediaPlayback = _browserOptions.allowinlinemediaplayback;
    if (IsAtLeastiOSVersion(@"10.0")) {
        configuration.ignoresViewportScaleLimits = _browserOptions.enableviewportscale;
        if(_browserOptions.mediaplaybackrequiresuseraction == YES){
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        }else{
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        }
    }else{ // iOS 9
        configuration.mediaPlaybackRequiresUserAction = _browserOptions.mediaplaybackrequiresuseraction;
    }

    self.webView = [[WKWebView alloc] initWithFrame:webViewBounds configuration:configuration];

    self.webView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

    [self.view addSubview:self.webView];
    [self.view sendSubviewToBack:self.webView];

    self.webView.navigationDelegate = self;

    self.webView.backgroundColor = [UIColor whiteColor];
    NSString* overrideUserAgent = [self settingForKey:@"OverrideUserAgent"];
    if (_browserOptions.customUserAgent) {
        self.webView.customUserAgent = _browserOptions.customUserAgent;
    } else if (overrideUserAgent) {
        self.webView.customUserAgent = overrideUserAgent;
    }

    self.webView.clearsContextBeforeDrawing = YES;
    self.webView.clipsToBounds = YES;
    self.webView.contentMode = UIViewContentModeScaleToFill;
    self.webView.multipleTouchEnabled = YES;
    self.webView.opaque = YES;
    self.webView.userInteractionEnabled = YES;
    self.webView.allowsBackForwardNavigationGestures = _browserOptions.allowsBackForwardNavigationGestures;
    if (_browserOptions.allowsBackForwardNavigationGestures) {
        UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        [swipeRight setDirection:UISwipeGestureRecognizerDirectionRight];
        [self.view addGestureRecognizer:swipeRight];
    }
    self.webView.UIDelegate = self;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.alpha = 1.000;
    self.spinner.autoresizesSubviews = YES;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    self.spinner.clearsContextBeforeDrawing = NO;
    self.spinner.clipsToBounds = NO;
    self.spinner.contentMode = UIViewContentModeScaleToFill;
    self.spinner.frame = CGRectMake(454.0, 231.0, 20.0, 20.0);
    self.spinner.hidden = YES;
    self.spinner.hidesWhenStopped = YES;
    self.spinner.multipleTouchEnabled = NO;
    self.spinner.opaque = NO;
    self.spinner.userInteractionEnabled = NO;
    [self.spinner stopAnimating];

    CGFloat toolbarY = toolbarIsAtBottom ? self.view.bounds.size.height - toolbarHeight : 0.0;
    CGRect toolbarFrame = CGRectMake(0.0, toolbarY, self.view.bounds.size.width, toolbarHeight);

    self.toolbar = [[UIView alloc] initWithFrame:toolbarFrame];
    self.toolbar.alpha = 1.000;
    self.toolbar.autoresizesSubviews = YES;
    self.toolbar.autoresizingMask = toolbarIsAtBottom ? (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin) : UIViewAutoresizingFlexibleWidth;
    self.toolbar.clearsContextBeforeDrawing = NO;
    self.toolbar.clipsToBounds = YES;
    self.toolbar.contentMode = UIViewContentModeScaleToFill;
    self.toolbar.hidden = NO;
    self.toolbar.multipleTouchEnabled = NO;
    self.toolbar.opaque = NO;
    self.toolbar.userInteractionEnabled = YES;
    self.toolbar.backgroundColor = [CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:toolbarProps withKey:kThemeableBrowserPropColor withDefault:@"#ffffffff"]];

    if (toolbarProps[kThemeableBrowserPropImage] || toolbarProps[kThemeableBrowserPropWwwImage]) {
        UIImage *image = [self getImage:toolbarProps[kThemeableBrowserPropImage]
                               altPath:toolbarProps[kThemeableBrowserPropWwwImage]
                               altDensity:[toolbarProps[kThemeableBrowserPropWwwImageDensity] doubleValue]];

        if (image) {
            self.toolbar.backgroundColor = [UIColor colorWithPatternImage:image];
        } else {
            [self.navigationDelegate emitError:kThemeableBrowserEmitCodeLoadFail
                                   withMessage:[NSString stringWithFormat:@"Image for toolbar, %@, failed to load.",
                                                toolbarProps[kThemeableBrowserPropImage]
                                                ? toolbarProps[kThemeableBrowserPropImage] : toolbarProps[kThemeableBrowserPropWwwImage]]];
        }
    }

    CGFloat labelInset = 5.0;
    float locationBarY = self.view.bounds.size.height - LOCATIONBAR_HEIGHT;

    self.addressLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelInset, locationBarY, self.view.bounds.size.width - labelInset, LOCATIONBAR_HEIGHT)];
    self.addressLabel.adjustsFontSizeToFitWidth = NO;
    self.addressLabel.alpha = 1.000;
    self.addressLabel.autoresizesSubviews = YES;
    self.addressLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.addressLabel.backgroundColor = [UIColor clearColor];
    self.addressLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    self.addressLabel.clearsContextBeforeDrawing = YES;
    self.addressLabel.clipsToBounds = YES;
    self.addressLabel.contentMode = UIViewContentModeScaleToFill;
    self.addressLabel.enabled = YES;
    self.addressLabel.hidden = NO;
    self.addressLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumScaleFactor:")]) {
        [self.addressLabel setValue:@(10.0/[UIFont labelFontSize]) forKey:@"minimumScaleFactor"];
    } else if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumFontSize:")]) {
        [self.addressLabel setValue:@(10.0) forKey:@"minimumFontSize"];
    }

    self.addressLabel.multipleTouchEnabled = NO;
    self.addressLabel.numberOfLines = 1;
    self.addressLabel.opaque = NO;
    self.addressLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    self.addressLabel.text = NSLocalizedString(@"Loading...", nil);
    self.addressLabel.textAlignment = NSTextAlignmentLeft;
    self.addressLabel.textColor = [UIColor colorWithWhite:1.000 alpha:1.000];
    self.addressLabel.userInteractionEnabled = NO;

    UIEdgeInsets insets = [self safeAreaInsetsWithView];
    NSDictionary *csCloseBtnOptions = @{kThemeableBrowserPropImage:@"close",kThemeableBrowserPropImagePressed:@"close_pressed"};
    self.csCloseButtonImg =[self getImage:csCloseBtnOptions[kThemeableBrowserPropImage] altPath:nil altDensity:0];
    self.csCloseButtonImg_Pressed =[self getImage:csCloseBtnOptions[kThemeableBrowserPropImagePressed] altPath:nil altDensity:0];
    self.csCloseButton =[self createButton:csCloseBtnOptions action:nil withDescription:@"自定义关闭按钮"];
    [self.view addSubview:self.csCloseButton];
    CGRect csCloseBtnBounds = self.csCloseButton.bounds;
    csCloseBtnBounds.origin.x = insets.left;
    csCloseBtnBounds.origin.y = insets.top;
    self.csCloseButton.frame = csCloseBtnBounds;
    
    // 单击事件
    [self.csCloseButton addTarget:self action:@selector(cusCloseBtnClick) forControlEvents:UIControlEventTouchUpInside];
    //添加手势 拖动
    UIPanGestureRecognizer *panRcognize=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.csCloseButton addGestureRecognizer:panRcognize];

    self.closeButton = [self createButton:_browserOptions.closeButton action:@selector(close) withDescription:@"close button"];
    self.backButton = [self createButton:_browserOptions.backButton action:@selector(goBack:) withDescription:@"back button"];
    self.forwardButton = [self createButton:_browserOptions.forwardButton action:@selector(goForward:) withDescription:@"forward button"];
    self.reloadButton = [self createButton:_browserOptions.reloadButton action:@selector(doReload:) withDescription:@"reload button"];
    self.menuButton = [self createButton:_browserOptions.menu action:@selector(goMenu:) withDescription:@"menu button"];

    // Arramge toolbar buttons with respect to user configuration.
    CGFloat leftWidth = 0;
    CGFloat rightWidth = 0;

    // Both left and right side buttons will be ordered from outside to inside.
    NSMutableArray* leftButtons = [NSMutableArray new];
    NSMutableArray* rightButtons = [NSMutableArray new];

    if (self.closeButton) {
        CGFloat width = [self getWidthFromButton:self.closeButton];

        if ([kThemeableBrowserAlignRight isEqualToString:_browserOptions.closeButton[kThemeableBrowserPropAlign]]) {
            [rightButtons addObject:self.closeButton];
            rightWidth += width;
        } else {
            [leftButtons addObject:self.closeButton];
            leftWidth += width;
        }
    }

    if (self.menuButton) {
        CGFloat width = [self getWidthFromButton:self.menuButton];

        if ([kThemeableBrowserAlignRight isEqualToString:_browserOptions.menu[kThemeableBrowserPropAlign]]) {
            [rightButtons addObject:self.menuButton];
            rightWidth += width;
        } else {
            [leftButtons addObject:self.menuButton];
            leftWidth += width;
        }
    }

    BOOL showFirstTime = [self getBoolFromDict:_browserOptions.backButton withKey:kThemeableBrowserPropShowFirstTime];
    if (showFirstTime == false) {
        self.backButton.hidden = YES;
    }

    // Back and forward buttons must be added with special ordering logic such
    // that back button is always on the left of forward button if both buttons
    // are on the same side.
    if (self.backButton && ![kThemeableBrowserAlignRight isEqualToString:_browserOptions.backButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.backButton];
        [leftButtons addObject:self.backButton];
        leftWidth += width;
    }

    if (self.forwardButton && [kThemeableBrowserAlignRight isEqualToString:_browserOptions.forwardButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.forwardButton];
        [rightButtons addObject:self.forwardButton];
        rightWidth += width;
    }

    if (self.forwardButton && ![kThemeableBrowserAlignRight isEqualToString:_browserOptions.forwardButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.forwardButton];
        [leftButtons addObject:self.forwardButton];
        leftWidth += width;
    }

    if (self.reloadButton && [kThemeableBrowserAlignRight isEqualToString:_browserOptions.reloadButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.reloadButton];
        [rightButtons addObject:self.reloadButton];
        rightWidth += width;
    }
    
    if (self.reloadButton && ![kThemeableBrowserAlignRight isEqualToString:_browserOptions.reloadButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.reloadButton];
        [leftButtons addObject:self.reloadButton];
        leftWidth += width;
    }

    if (self.backButton && [kThemeableBrowserAlignRight isEqualToString:_browserOptions.backButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.backButton];
        [rightButtons addObject:self.backButton];
        rightWidth += width;
    }

    NSArray* customButtons = _browserOptions.customButtons;
    if (customButtons) {
        NSInteger cnt = [customButtons count]-1;

        // Reverse loop because we are laying out from outer to inner.
        for (NSDictionary* customButton in [customButtons reverseObjectEnumerator]) {
            UIButton* button = [self createButton:customButton action:@selector(goCustomButton:) withDescription:[NSString stringWithFormat:@"custom button at %ld", (long)cnt]];
            if (button) {
                button.tag = cnt+TAG_SALT;

                CGFloat width = [self getWidthFromButton:button];
                if ([kThemeableBrowserAlignRight isEqualToString:customButton[kThemeableBrowserPropAlign]]) {
                    [rightButtons addObject:button];
                    rightWidth += width;
                } else {
                    [leftButtons addObject:button];
                    leftWidth += width;
                }
            }

            cnt -= 1;
        }
    }

    self.rightButtons = rightButtons;
    self.leftButtons = leftButtons;

    for (UIButton* button in self.leftButtons) {
        [self.toolbar addSubview:button];
    }

    for (UIButton* button in self.rightButtons) {
        [self.toolbar addSubview:button];
    }

    [self layoutButtons];

    self.titleOffset = fmaxf(leftWidth, rightWidth);
    // The correct positioning of title is not that important right now, since
    // rePositionViews will take care of it a bit later.
    self.titleLabel = nil;
    if (_browserOptions.title) {
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 10, toolbarHeight)];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.titleLabel.textColor = [CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:_browserOptions.title withKey:kThemeableBrowserPropColor withDefault:@"#000000ff"]];

        if (_browserOptions.title[kThemeableBrowserPropStaticText]) {
            self.titleLabel.text = _browserOptions.title[kThemeableBrowserPropStaticText];
        }

        if (_browserOptions.title[kThemeableBrowserPropSize]) {
            CGFloat textSize = [self getFloatFromDict:_browserOptions.title withKey:kThemeableBrowserPropSize withDefault:13.0];
            self.titleLabel.font = [UIFont boldSystemFontOfSize:textSize];
        }

        [self.toolbar addSubview:self.titleLabel];
    }

    self.view.backgroundColor = [CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:_browserOptions.statusbar withKey:kThemeableBrowserPropColor withDefault:@"#ffffffff"]];
    [self.view addSubview:self.toolbar];
//    self.progressView=[[UIProgressView   alloc] initWithFrame:CGRectMake(0.0, toolbarY+toolbarHeight+[self getStatusBarOffset], self.view.bounds.size.width, 20.0)];
    
    self.progressView=[[UIProgressView   alloc] initWithFrame:CGRectMake(insets.left,insets.top,SCREEN_WIDTH-insets.left-insets.right,SCREEN_HEIGHT-insets.top-insets.bottom)];
    self.progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.progressView.progressViewStyle=UIProgressViewStyleDefault;
    self.progressView.progressTintColor=[CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:_browserOptions.browserProgress withKey: kThemeableBrowserPropProgressColor withDefault:@"#0000FF"]];
    self.progressView.trackTintColor=[CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:_browserOptions.browserProgress withKey:kThemeableBrowserPropProgressBgColor withDefault:@"#808080"]];
    if ([self getBoolFromDict:_browserOptions.browserProgress withKey:kThemeableBrowserPropShowProgress]) {
        UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        [swipeRight setDirection:UISwipeGestureRecognizerDirectionRight];
        [self.view addGestureRecognizer:swipeRight];
        [self.view addSubview:self.progressView];
        [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    }
}

/**
 *  处理拖动手势
 *
 *  @param recognizer 拖动手势识别器对象实例
 */
- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    
//    recognizer.view.ba
    //视图前置操作
    [recognizer.view.superview bringSubviewToFront:recognizer.view];
    
    // view 中心点坐标
    CGPoint center = recognizer.view.center;
//    NSLog(@"%@", NSStringFromCGPoint(center));
    CGSize viewSize = recognizer.view.bounds.size;
    // 移动的坐标
    CGPoint translation = [recognizer translationInView:self.view];
//    NSLog(@"%@", NSStringFromCGPoint(translation));
    UIEdgeInsets insets = [self safeAreaInsetsWithView]; //安全区域
    CGFloat leftMargin = viewSize.width / 2 + insets.left;
    CGFloat topMargin = viewSize.height / 2 + insets.top;
    CGFloat availableWidth  = SCREEN_WIDTH - viewSize.width / 2 ;
    CGFloat availableHeight  = SCREEN_HEIGHT - viewSize.height / 2;
    if(center.x < SCREEN_WIDTH /2) //按钮在左半屏
    {
        availableWidth -= insets.left;
    }else { //按钮在右半屏
        availableWidth -= insets.right;
    }
    
    if(center.y < SCREEN_HEIGHT / 2){ //按钮在上半屏
        availableHeight -= insets.top;
    }else { // 按钮在下半屏
        availableHeight -= insets.bottom;
    }
    
    CGFloat nextPointX =MAX(center.x + translation.x, leftMargin); //最左
    CGFloat nextPointY =MAX(center.y + translation.y, topMargin); //最上
    nextPointX =MIN(nextPointX, availableWidth); //最右
    nextPointY =MIN(nextPointY, availableHeight); //最下
    recognizer.view.center = CGPointMake(nextPointX,nextPointY);
    [recognizer setTranslation:CGPointZero inView:self.view];
    
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        [self.csCloseButton setImage:self.csCloseButtonImg_Pressed forState:UIControlStateNormal];
//        [recognizer.view setBackgroundColor:[UIColor colorWithPatternImage:self.csCloseButtonImg_Pressed]];
    }
    if (recognizer.state == UIGestureRecognizerStateEnded
        || recognizer.state == UIGestureRecognizerStateCancelled
        ||recognizer.state == UIGestureRecognizerStateFailed)
    {
        [self.csCloseButton setImage:self.csCloseButtonImg forState:UIControlStateNormal];
//        [recognizer.view setBackgroundColor:[UIColor colorWithPatternImage:self.csCloseButtonImg]];
    }
//    if (recognizer.state == UIGestureRecognizerStateEnded) {
//        //计算速度向量的长度，当他小于200时，滑行会很短
//        CGPoint velocity = [recognizer velocityInView:self.view];
//        CGFloat magnitude = sqrtf((velocity.x * velocity.x) + (velocity.y * velocity.y));
//        CGFloat slideMult = magnitude / 200;
//        //NSLog(@"magnitude: %f, slideMult: %f", magnitude, slideMult); //e.g. 397.973175, slideMult: 1.989866
//
//        //基于速度和速度因素计算一个终点
//        float slideFactor = 0.1 * slideMult;
//        CGPoint finalPoint = CGPointMake(center.x + (velocity.x * slideFactor),
//                                         center.y + (velocity.y * slideFactor));
//        //限制最小［cornerRadius］和最大边界值［self.view.bounds.size.width - cornerRadius］，以免拖动出屏幕界限
//        finalPoint.x = MIN(MAX(finalPoint.x, cornerRadius),
//                           self.view.bounds.size.width - cornerRadius);
//        finalPoint.y = MIN(MAX(finalPoint.y, cornerRadius),
//                           self.view.bounds.size.height - cornerRadius);
//
//        //使用 UIView 动画使 view 滑行到终点
//        [UIView animateWithDuration:slideFactor*2
//                              delay:0
//                            options:UIViewAnimationOptionCurveEaseOut
//                         animations:^{
//                             recognizer.view.center = finalPoint;
//                         }
//                         completion:nil];
//    }
}

- (id)settingForKey:(NSString*)key
{
    return [_settings objectForKey:[key lowercaseString]];
}

- (nullable WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    if (!navigationAction.targetFrame) {
        [webView loadRequest:navigationAction.request];
    }

    return nil;
}


- (void)handleSwipe:(UISwipeGestureRecognizer *)swipe {
    // If there is no back history and backButtonCanClose is enabled, close the browser.
    if (swipe.direction == UISwipeGestureRecognizerDirectionRight && !self.webView.canGoBack && _browserOptions.backButtonCanClose) {
        [self close];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        // Update progress bar when estimatedProgress changes
         self.progressView.alpha = 1.0;
        [self.progressView setProgress:self.webView.estimatedProgress animated:YES];
        if(self.webView.estimatedProgress >= 1.0f) {
            [UIView animateWithDuration:0.3 delay:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
              [self.progressView setAlpha:0.0f];
            } completion:^(BOOL finished) {
              [self.progressView setProgress:0.0f animated:NO];
            }];
         }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }

}

/**
 * This is a rather unintuitive helper method to load images. The reason why this method exists
 * is because due to some service limitations, one may not be able to add images to native
 * resource bundle. So this method offers a way to load image from www contents instead.
 * However loading from native resource bundle is already preferred over loading from www. So
 * if name is given, then it simply loads from resource bundle and the other two parameters are
 * ignored. If name is not given, then altPath is assumed to be a file path _under_ www and
 * altDensity is the desired density of the given image file, because without native resource
 * bundle, we can't tell what densitiy the image is supposed to be so it needs to be given
 * explicitly.
 */
- (UIImage*) getImage:(NSString*) name altPath:(NSString*) altPath altDensity:(CGFloat) altDensity
{
    UIImage* result = nil;
    if (name) {
        result = [UIImage imageNamed:name];
//        NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
//        NSData *image = [NSData dataWithContentsOfFile:path];
//        result = [UIImage imageWithData:image scale:2];
    } else if (altPath) {
        NSString* path = [[[NSBundle mainBundle] bundlePath]
                          stringByAppendingPathComponent:[NSString pathWithComponents:@[@"www", altPath]]];
        if (!altDensity) {
            altDensity = 1.0;
        }
        NSData* data = [NSData dataWithContentsOfFile:path];
        result = [UIImage imageWithData:data scale:altDensity];
    }

    return result;
}

- (UIButton*) createButton:(NSDictionary*) buttonProps action:(SEL)action withDescription:(NSString*)description
{
    UIButton* result = nil;
    if (buttonProps) {
        UIImage *buttonImage = nil;
        if (buttonProps[kThemeableBrowserPropImage] || buttonProps[kThemeableBrowserPropWwwImage]) {
            buttonImage = [self getImage:buttonProps[kThemeableBrowserPropImage]
                                altPath:buttonProps[kThemeableBrowserPropWwwImage]
                                altDensity:[buttonProps[kThemeableBrowserPropWwwImageDensity] doubleValue]];

            if (!buttonImage) {
                [self.navigationDelegate emitError:kThemeableBrowserEmitCodeLoadFail
                                       withMessage:[NSString stringWithFormat:@"Image for %@, %@, failed to load.",
                                                    description,
                                                    buttonProps[kThemeableBrowserPropImage]
                                                    ? buttonProps[kThemeableBrowserPropImage] : buttonProps[kThemeableBrowserPropWwwImage]]];
            }
        } else {
            [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                                 withMessage:[NSString stringWithFormat:@"Image for %@ is not defined. Button will not be shown.", description]];
        }

        UIImage *buttonImagePressed = nil;
        if (buttonProps[kThemeableBrowserPropImagePressed] || buttonProps[kThemeableBrowserPropWwwImagePressed]) {
            buttonImagePressed = [self getImage:buttonProps[kThemeableBrowserPropImagePressed]
                                       altPath:buttonProps[kThemeableBrowserPropWwwImagePressed]
                                       altDensity:[buttonProps[kThemeableBrowserPropWwwImageDensity] doubleValue]];;

            if (!buttonImagePressed) {
                [self.navigationDelegate emitError:kThemeableBrowserEmitCodeLoadFail
                                       withMessage:[NSString stringWithFormat:@"Pressed image for %@, %@, failed to load.",
                                                    description,
                                                    buttonProps[kThemeableBrowserPropImagePressed]
                                                    ? buttonProps[kThemeableBrowserPropImagePressed] : buttonProps[kThemeableBrowserPropWwwImagePressed]]];
            }
        } else {
            [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                             withMessage:[NSString stringWithFormat:@"Pressed image for %@ is not defined.", description]];
        }

        if (buttonImage) {
            result = [UIButton buttonWithType:UIButtonTypeCustom];
            result.bounds = CGRectMake(0, 0, buttonImage.size.width, buttonImage.size.height);

            if (buttonImagePressed) {
                [result setImage:buttonImagePressed forState:UIControlStateHighlighted];
//                result.adjustsImageWhenHighlighted = NO;
            }

            [result setImage:buttonImage forState:UIControlStateNormal];
            if(action != nil){
                [result addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
            }
            
        }
    } else if (!buttonProps) {
        [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                                 withMessage:[NSString stringWithFormat:@"%@ is not defined. Button will not be shown.", description]];
    } else if (!buttonProps[kThemeableBrowserPropImage]) {
    }

    return result;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];

    // Reposition views.
    [self rePositionViews];
}

- (void) setWebViewFrame : (CGRect) frame {
    [self.webView setFrame:frame];
}

- (void)layoutButtons
{
    CGFloat screenWidth = CGRectGetWidth(self.view.frame);
    CGFloat toolbarHeight = self.toolbar.frame.size.height;

    // Layout leftButtons and rightButtons from outer to inner.
    CGFloat left = 0;
    for (UIButton* button in self.leftButtons) {
        CGSize size = button.frame.size;
        button.frame = CGRectMake(left, floorf((toolbarHeight - size.height) / 2), size.width, size.height);
        left += size.width;
    }

    CGFloat right = 0;
    for (UIButton* button in self.rightButtons) {
        CGSize size = button.frame.size;
        button.frame = CGRectMake(screenWidth - right - size.width, floorf((toolbarHeight - size.height) / 2), size.width, size.height);
        right += size.width;
    }
}

- (void)setCloseButtonTitle:(NSString*)title
{
    // This method is not used by ThemeableBrowser. It is inherited from
    // InAppBrowser and is kept for merge purposes.

    // the advantage of using UIBarButtonSystemItemDone is the system will localize it for you automatically
    // but, if you want to set this yourself, knock yourself out (we can't set the title for a system Done button, so we have to create a new one)
    // self.closeButton = nil;
    // self.closeButton = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:@selector(close)];
    // self.closeButton.enabled = YES;
    // self.closeButton.tintColor = [UIColor colorWithRed:60.0 / 255.0 green:136.0 / 255.0 blue:230.0 / 255.0 alpha:1];

    // NSMutableArray* items = [self.toolbar.items mutableCopy];
    // [items replaceObjectAtIndex:0 withObject:self.closeButton];
    // [self.toolbar setItems:items];
}

- (void)showLocationBar:(BOOL)show
{
    CGRect locationbarFrame = self.addressLabel.frame;
    CGFloat toolbarHeight = [self getFloatFromDict:_browserOptions.toolbar withKey:kThemeableBrowserPropHeight withDefault:TOOLBAR_DEF_HEIGHT];

    BOOL toolbarVisible = !self.toolbar.hidden;

    // prevent double show/hide
    if (show == !(self.addressLabel.hidden)) {
        return;
    }

    if (show) {
        self.addressLabel.hidden = NO;

        if (toolbarVisible) {
            // toolBar at the bottom, leave as is
            // put locationBar on top of the toolBar

            CGRect webViewBounds = self.view.bounds;
            if (!_browserOptions.fullscreen) {
                webViewBounds.size.height -= toolbarHeight;
            }
            [self setWebViewFrame:webViewBounds];

            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
        } else {
            // no toolBar, so put locationBar at the bottom

            CGRect webViewBounds = self.view.bounds;
            webViewBounds.size.height -= LOCATIONBAR_HEIGHT;
            [self setWebViewFrame:webViewBounds];

            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
        }
    } else {
        self.addressLabel.hidden = YES;

        if (toolbarVisible) {
            // locationBar is on top of toolBar, hide locationBar

            // webView take up whole height less toolBar height
            CGRect webViewBounds = self.view.bounds;
            if (!_browserOptions.fullscreen) {
                webViewBounds.size.height -= toolbarHeight;
            }
            [self setWebViewFrame:webViewBounds];
        } else {
            // no toolBar, expand webView to screen dimensions
            [self setWebViewFrame:self.view.bounds];
        }
    }
}

- (void)showToolBar:(BOOL)show : (NSString *) toolbarPosition
{
    CGRect toolbarFrame = self.toolbar.frame;
    CGRect locationbarFrame = self.addressLabel.frame;
    CGFloat toolbarHeight = [self getFloatFromDict:_browserOptions.toolbar withKey:kThemeableBrowserPropHeight withDefault:TOOLBAR_DEF_HEIGHT];

    BOOL locationbarVisible = !self.addressLabel.hidden;

    // prevent double show/hide
    if (show == !(self.toolbar.hidden)) {
        return;
    }

    if (show) {
        self.toolbar.hidden = NO;
        CGRect webViewBounds = self.view.bounds;

        if (locationbarVisible) {
            // locationBar at the bottom, move locationBar up
            // put toolBar at the bottom
            if (!_browserOptions.fullscreen) {
                webViewBounds.size.height -= toolbarHeight;
            }
            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
            self.toolbar.frame = toolbarFrame;
        } else {
            // no locationBar, so put toolBar at the bottom
            self.toolbar.frame = toolbarFrame;
        }

        if ([toolbarPosition isEqualToString:kThemeableBrowserToolbarBarPositionTop]) {
            toolbarFrame.origin.y = 0;
            if (!_browserOptions.fullscreen) {
                webViewBounds.origin.y += toolbarFrame.size.height;
            }
            [self setWebViewFrame:webViewBounds];
        } else {
            toolbarFrame.origin.y = (webViewBounds.size.height + LOCATIONBAR_HEIGHT);
        }
        [self setWebViewFrame:webViewBounds];

    } else {
        self.toolbar.hidden = YES;

        if (locationbarVisible) {
            // locationBar is on top of toolBar, hide toolBar
            // put locationBar at the bottom

            // webView take up whole height less locationBar height
            CGRect webViewBounds = self.view.bounds;
            webViewBounds.size.height -= LOCATIONBAR_HEIGHT;
            [self setWebViewFrame:webViewBounds];

            // move locationBar down
            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
        } else {
            // no locationBar, expand webView to screen dimensions
            [self setWebViewFrame:self.view.bounds];
        }
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewDidUnload
{
    [self.webView loadHTMLString:nil baseURL:nil];
    [super viewDidUnload];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return _statusBarStyle;
}

- (void)cusCloseBtnClick
{
    NSDictionary *cusCloseBtnOptions = @{kThemeableBrowserPropEvent:@"cusClosePressed"};
    [self emitEventForButton:cusCloseBtnOptions];

    self.currentURL = nil;

    if ([self getBoolFromDict:_browserOptions.browserProgress withKey:kThemeableBrowserPropShowProgress]) {
        [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    }

    if ((self.navigationDelegate != nil) && [self.navigationDelegate respondsToSelector:@selector(browserExit)]) {
        [self.navigationDelegate browserExit];
    }

    //设置屏幕的转向为竖屏
    [[UIDevice currentDevice] setValue:@(UIDeviceOrientationPortrait) forKey:@"orientation"];
    //刷新
    [UIViewController attemptRotationToDeviceOrientation];
    [UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleDefault;
    
    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:@selector(presentingViewController)]) {
            [[self presentingViewController] dismissViewControllerAnimated:!_browserOptions.disableAnimation completion:nil];
        } else {
            [[self parentViewController] dismissViewControllerAnimated:!_browserOptions.disableAnimation completion:nil];
        }
    });


}

- (void)close
{
    [self emitEventForButton:_browserOptions.closeButton];

    self.currentURL = nil;

    if ([self getBoolFromDict:_browserOptions.browserProgress withKey:kThemeableBrowserPropShowProgress]) {
        [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    }

    if ((self.navigationDelegate != nil) && [self.navigationDelegate respondsToSelector:@selector(browserExit)]) {
        [self.navigationDelegate browserExit];
    }

    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:@selector(presentingViewController)]) {
            [[self presentingViewController] dismissViewControllerAnimated:!_browserOptions.disableAnimation completion:nil];
        } else {
            [[self parentViewController] dismissViewControllerAnimated:!_browserOptions.disableAnimation completion:nil];
        }
    });

}

- (void)reload
{
    [self.webView reload];
}

- (void)changeButtonImage:(NSInteger) buttonIndex buttonProps:(NSDictionary *)buttonProps {
    
    UIButton* button = (UIButton *)[self.toolbar viewWithTag:buttonIndex+TAG_SALT];
    UIImage *image = [self getImage:buttonProps[kThemeableBrowserPropImage]
                            altPath:buttonProps[kThemeableBrowserPropWwwImage]
                         altDensity:[buttonProps[kThemeableBrowserPropWwwImageDensity] doubleValue]];
    if(button && image){
        [button setImage:image forState:UIControlStateNormal];
    }
}

- (void)navigateTo:(NSURL*)url
{
    NSURLRequest* request = [NSURLRequest requestWithURL:url];

    [self.webView loadRequest:request];
}

- (void)goBack:(id)sender
{
    [self emitEventForButton:_browserOptions.backButton];

    if (self.webView.canGoBack) {
        [self.webView goBack];
        [self updateButtonDelayed:self.webView];
    } else if (_browserOptions.backButtonCanClose) {
        [self close];
    }
}

- (void)goForward:(id)sender
{
    [self emitEventForButton:_browserOptions.forwardButton];

    [self.webView goForward];
    [self updateButtonDelayed:self.webView];
}

- (void)doReload:(id)sender
{
    [self emitEventForButton:_browserOptions.reloadButton];
    
    [self.webView reload];
    [self updateButtonDelayed:self.webView];
}

- (void)goCustomButton:(id)sender
{
    UIButton* button = sender;
    NSInteger index = button.tag-TAG_SALT;
    [self emitEventForButton:_browserOptions.customButtons[index] withIndex:[NSNumber numberWithLong:index]];
}

- (void)goMenu:(id)sender
{
    [self emitEventForButton:_browserOptions.menu];

    if (_browserOptions.menu && _browserOptions.menu[kThemeableBrowserPropItems]) {
        NSArray* menuItems = _browserOptions.menu[kThemeableBrowserPropItems];
        if (IsAtLeastiOSVersion(@"8.0")) {
            // iOS > 8 implementation using UIAlertController, which is the new way
            // to do this going forward.
            UIAlertController *alertController = [UIAlertController
                                                  alertControllerWithTitle:_browserOptions.menu[kThemeableBrowserPropTitle]
                                                  message:nil
                                                  preferredStyle:UIAlertControllerStyleActionSheet];
            alertController.popoverPresentationController.sourceView
                    = self.menuButton;
            alertController.popoverPresentationController.sourceRect
                    = self.menuButton.bounds;

            for (NSInteger i = 0; i < menuItems.count; i++) {
                NSInteger index = i;
                NSDictionary *item = menuItems[index];

                UIAlertAction *a = [UIAlertAction
                                     actionWithTitle:item[@"label"]
                                     style:UIAlertActionStyleDefault
                                     handler:^(UIAlertAction *action) {
                                         [self menuSelected:index];
                                     }];
                [alertController addAction:a];
            }

            if (_browserOptions.menu[kThemeableBrowserPropCancel]) {
                UIAlertAction *cancelAction = [UIAlertAction
                                               actionWithTitle:_browserOptions.menu[kThemeableBrowserPropCancel]
                                               style:UIAlertActionStyleCancel
                                               handler:nil];
                [alertController addAction:cancelAction];
            }

            [self presentViewController:alertController animated:YES completion:nil];
        } else {
            // iOS < 8 implementation using UIActionSheet, which is deprecated.
            UIActionSheet *popup = [[UIActionSheet alloc]
                                    initWithTitle:_browserOptions.menu[kThemeableBrowserPropTitle]
                                    delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];

            for (NSDictionary *item in menuItems) {
                [popup addButtonWithTitle:item[@"label"]];
            }
            if (_browserOptions.menu[kThemeableBrowserPropCancel]) {
                [popup addButtonWithTitle:_browserOptions.menu[kThemeableBrowserPropCancel]];
                popup.cancelButtonIndex = menuItems.count;
            }

            [popup showFromRect:self.menuButton.frame inView:self.view animated:YES];
        }
    } else {
        [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                                 withMessage:@"Menu items undefined. No menu will be shown."];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [self menuSelected:buttonIndex];
}

- (void) menuSelected:(NSInteger)index
{
    NSArray* menuItems = _browserOptions.menu[kThemeableBrowserPropItems];
    if (index < menuItems.count) {
        [self emitEventForButton:menuItems[index] withIndex:[NSNumber numberWithLong:index]];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    if (IsAtLeastiOSVersion(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarStyle:[self preferredStatusBarStyle]];
    }
    [self rePositionViews];

    [super viewWillAppear:animated];
}

//
// On iOS 7 the status bar is part of the view's dimensions, therefore it's height has to be taken into account.
// The height of it could be hardcoded as 20 pixels, but that would assume that the upcoming releases of iOS won't
// change that value.
//
- (float) getStatusBarOffset {
    CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
    float statusBarOffset = IsAtLeastiOSVersion(@"7.0") ? MIN(statusBarFrame.size.width, statusBarFrame.size.height) : 0.0;
    return statusBarOffset;
}

- (void) rePositionViews {

    UIEdgeInsets insets = [self safeAreaInsetsWithView]; //安全区域
    [self.webView setFrame:CGRectMake(insets.left, insets.top, SCREEN_WIDTH - insets.left - insets.right,SCREEN_HEIGHT - insets.top - insets.bottom)];
    
    //自定义关闭按钮重置到左上角
    CGRect csCloseBtnBounds = self.csCloseButton.bounds;
    csCloseBtnBounds.origin.x = insets.left;
    csCloseBtnBounds.origin.y = insets.top+30;
    self.csCloseButton.frame = csCloseBtnBounds;
    
    //进度条位置调整
    [self.progressView setFrame:CGRectMake(insets.left,insets.top,SCREEN_WIDTH-insets.left-insets.right,SCREEN_HEIGHT-insets.top-insets.bottom)];
    
    [self layoutButtons];
    
    // Webview height is a bug that appear in the plugin for ios >= 11 so we need to keep the previous code that work great for previous versions
//    if (@available(iOS 11, *)) {
//
//        CGFloat toolbarHeight = [self getFloatFromDict:_browserOptions.toolbar withKey:kThemeableBrowserPropHeight withDefault:TOOLBAR_DEF_HEIGHT];
//        CGFloat statusBarOffset = [self getStatusBarOffset];
//        CGFloat webviewOffset = _browserOptions.fullscreen ? 0.0 : toolbarHeight + statusBarOffset;
//
//        if ([_browserOptions.toolbarposition isEqualToString:kThemeableBrowserToolbarBarPositionTop]) {
//            // The webview height calculated did not take the status bar into account. Thus we need to remove status bar height to the webview height.
//            [self.webView setFrame:CGRectMake(self.webView.frame.origin.x, webviewOffset, self.webView.frame.size.width, (self.webView.frame.size.height-statusBarOffset))];
//            [self.toolbar setFrame:CGRectMake(self.toolbar.frame.origin.x, [self getStatusBarOffset], self.toolbar.frame.size.width, self.toolbar.frame.size.height)];
//        }
//        // When positionning the iphone to landscape mode, status bar is hidden. The problem is that we set the webview height just before with removing the status bar height. We need to adjust the phenomen by adding the preview status bar height. We had to add manually 20 (pixel) because in landscape mode, the status bar height is equal to 0.
//        if (statusBarOffset == 0) {
//            [self.webView setFrame:CGRectMake(self.webView.frame.origin.x, webviewOffset, self.webView.frame.size.width, (self.webView.frame.size.height+20))];
//        }
//
//        CGFloat screenWidth = CGRectGetWidth(self.view.frame);
//        NSInteger width = floorf(screenWidth - self.titleOffset * 2.0f);
//        if (self.titleLabel) {
//            self.titleLabel.frame = CGRectMake(floorf((screenWidth - width) / 2.0f), 0, width, toolbarHeight);
//        }
//
//        [self layoutButtons];
//
//    } else {
//
//        CGFloat toolbarHeight = [self getFloatFromDict:_browserOptions.toolbar withKey:kThemeableBrowserPropHeight withDefault:TOOLBAR_DEF_HEIGHT];
//        CGFloat webviewOffset = _browserOptions.fullscreen ? 0.0 : toolbarHeight;
//
//        if ([_browserOptions.toolbarposition isEqualToString:kThemeableBrowserToolbarBarPositionTop]) {
//            [self.webView setFrame:CGRectMake(self.webView.frame.origin.x, webviewOffset, self.webView.frame.size.width, self.webView.frame.size.height)];
//            [self.toolbar setFrame:CGRectMake(self.toolbar.frame.origin.x, [self getStatusBarOffset], self.toolbar.frame.size.width, self.toolbar.frame.size.height)];
//        }
//
//        CGFloat screenWidth = CGRectGetWidth(self.view.frame);
//        NSInteger width = floorf(screenWidth - self.titleOffset * 2.0f);
//        if (self.titleLabel) {
//            self.titleLabel.frame = CGRectMake(floorf((screenWidth - width) / 2.0f), 0, width, toolbarHeight);
//        }
//
//        [self layoutButtons];
//    }
}

- (UIEdgeInsets)safeAreaInsetsWithView // 获取安全区域
{
#ifdef __IPHONE_11_0
    if (@available(iOS 11.0, *))
    {
        return [UIApplication sharedApplication].delegate.window.safeAreaInsets;
    }
#endif

    return UIEdgeInsetsZero;
}

- (CGFloat) getFloatFromDict:(NSDictionary*)dict withKey:(NSString*)key withDefault:(CGFloat)def
{
    CGFloat result = def;
    if (dict && dict[key]) {
        result = [(NSNumber*) dict[key] floatValue];
    }
    return result;
}

- (NSString*) getStringFromDict:(NSDictionary*)dict withKey:(NSString*)key withDefault:(NSString*)def
{
    NSString* result = def;
    if (dict && dict[key]) {
        result = dict[key];
    }
    return result;
}

- (BOOL) getBoolFromDict:(NSDictionary*)dict withKey:(NSString*)key
{
    BOOL result = NO;
    if (dict && dict[key]) {
        result = [(NSNumber*) dict[key] boolValue];
    }
    return result;
}

- (CGFloat) getWidthFromButton:(UIButton*)button
{
    return button.frame.size.width;
}

- (void)emitEventForButton:(NSDictionary*)buttonProps
{
    [self emitEventForButton:buttonProps withIndex:nil];
}

- (void)emitEventForButton:(NSDictionary*)buttonProps withIndex:(NSNumber*)index
{
    if (buttonProps) {
        NSString* event = buttonProps[kThemeableBrowserPropEvent];
        if (event) {
            NSMutableDictionary* dict = [NSMutableDictionary new];
            [dict setObject:event forKey:@"type"];
            [dict setObject:[self.navigationDelegate.themeableBrowserViewController.currentURL absoluteString] forKey:@"url"];

            if (index) {
                [dict setObject:index forKey:@"index"];
            }
            [self.navigationDelegate emitEvent:dict];
        } else {
            [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                                     withMessage:@"Button clicked, but event property undefined. No event will be raised."];
        }
    }
}


#pragma mark UIWebViewDelegate

// These UIWebView delegates won't fire due to the switch to WKWebView.

//- (void)webViewDidStartLoad:(UIWebView*)theWebView
//{
//    // loading url, start spinner
//
//    self.addressLabel.text = NSLocalizedString(@"Loading...", nil);
//
//    [self.spinner startAnimating];
//
//    return [self.navigationDelegate webViewDidStartLoad:theWebView];
//}

//- (BOOL)webView:(WKWebView*)theWebView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType
//{
//    BOOL isTopLevelNavigation = [request.URL isEqual:[request mainDocumentURL]];
//
//    if (isTopLevelNavigation) {
//        self.currentURL = request.URL;
//    }
//
//    [self updateButtonDelayed:theWebView];
//
//    return [self.navigationDelegate webView:theWebView shouldStartLoadWithRequest:request navigationType:navigationType];
//}

//- (void)webViewDidFinishLoad:(UIWebView*)theWebView
//{
//    // update url, stop spinner, update back/forward
//
//    self.addressLabel.text = [self.currentURL absoluteString];
//    [self updateButton:theWebView];
//
//    if (self.titleLabel && _browserOptions.title
//            && !_browserOptions.title[kThemeableBrowserPropStaticText]
//            && [self getBoolFromDict:_browserOptions.title withKey:kThemeableBrowserPropShowPageTitle]) {
//        // Update title text to page title when title is shown and we are not
//        // required to show a static text.
//
//        [self.webView evaluateJavaScript:@"document.title" completionHandler:^(NSString *result, NSError *error) {
//            self.titleLabel.text = result;
//        }];
//        //self.titleLabel.text = [self.webView stringByEvaluatingJavaScriptFromString:@"document.title"];
//    }
//
//    [self.spinner stopAnimating];
//
//    // Work around a bug where the first time a PDF is opened, all UIWebViews
//    // reload their User-Agent from NSUserDefaults.
//    // This work-around makes the following assumptions:
//    // 1. The app has only a single Cordova Webview. If not, then the app should
//    //    take it upon themselves to load a PDF in the background as a part of
//    //    their start-up flow.
//    // 2. That the PDF does not require any additional network requests. We change
//    //    the user-agent here back to that of the CDVViewController, so requests
//    //    from it must pass through its white-list. This *does* break PDFs that
//    //    contain links to other remote PDF/websites.
//    // More info at https://issues.apache.org/jira/browse/CB-2225
//    __block BOOL isPDF;
//    [theWebView evaluateJavaScript:@"document.body==null" completionHandler:^(NSString *result, NSError *error) {
//        if([result isEqualToString:@"true"]) {
//            isPDF = true;
//        } else {
//            isPDF = false;
//        }
//    }];
//
//    //BOOL isPDF = [@"true" isEqualToString :[theWebView stringByEvaluatingJavaScriptFromString:@"document.body==null"]];
//    if (isPDF) {
//        [CDVUserAgentUtil setUserAgent:_prevUserAgent lockToken:_userAgentLockToken];
//    }
//
//    //[self.navigationDelegate webViewDidFinishLoad:theWebView];
//}
//
//- (void)webView:(UIWebView*)theWebView didFailLoadWithError:(NSError*)error
//{
//    [self updateButton:theWebView];
//
//    [self.spinner stopAnimating];
//
//    self.addressLabel.text = NSLocalizedString(@"Load Error", nil);
//
//    [self.navigationDelegate webView:theWebView didFailLoadWithError:error];
//}

- (void)updateButton:(WKWebView*)theWebView
{
    if (self.backButton) {
        self.backButton.enabled = _browserOptions.backButtonCanClose || theWebView.canGoBack;

        BOOL showFirstTime = [self getBoolFromDict:_browserOptions.backButton withKey:kThemeableBrowserPropShowFirstTime];
        if (showFirstTime == false) {
            if(theWebView.canGoBack) {
               self.backButton.hidden = NO;
            }else {
               self.backButton.hidden = YES;
            }
        }
    }

    if (self.forwardButton) {
        self.forwardButton.enabled = theWebView.canGoForward;
    }
}

static void extracted(CDVThemeableBrowserViewController *object, WKWebView *theWebView) {
    [object updateButton:theWebView];
}

/**
 * The reason why this method exists at all is because UIWebView is quite
 * terrible with dealing this hash change, which IS a history change. However
 * when moving to a new hash, only shouldStartLoadWithRequest will be called.
 * Even then it's being called too early such that canGoback and canGoForward
 * hasn't been updated yet. What makes it worse is that when navigating history
 * involving hash by goBack and goForward, no callback is called at all, so we
 * will have to depend on the back and forward button to give us hints when to
 * change button states.
 */
- (void)updateButtonDelayed:(WKWebView*)theWebView
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        extracted(self, theWebView);
    });
}

#pragma mark WKScriptMessageHandler delegate
- (void)userContentController:(nonnull WKUserContentController *)userContentController didReceiveScriptMessage:(nonnull WKScriptMessage *)message {
    if (![message.name isEqualToString:IAB_BRIDGE_NAME]) {
        return;
    }
    //NSLog(@"Received script message %@", message.body);
    [self.navigationDelegate userContentController:userContentController didReceiveScriptMessage:message];
}

#pragma mark CDVScreenOrientationDelegate

- (BOOL)shouldAutorotate
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.orientationDelegate shouldAutorotate];
    }
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
//        return [self.orientationDelegate supportedInterfaceOrientations];
        if([_browserOptions.orientation isEqualToString:@"LANDSCAPE"]){
            return UIInterfaceOrientationMaskLandscapeRight | UIInterfaceOrientationMaskLandscapeLeft;
        }else if([_browserOptions.orientation isEqualToString:@"PORTRAIT"]){
            return UIInterfaceOrientationMaskPortrait;
        }
        return UIInterfaceOrientationMaskLandscapeLeft | UIInterfaceOrientationMaskLandscapeRight | UIInterfaceOrientationMaskPortrait;
    }

    return 1 << UIInterfaceOrientationPortrait;
}

+ (UIColor *)colorFromRGBA:(NSString *)rgba {
    unsigned rgbaVal = 0;

    if ([[rgba substringWithRange:NSMakeRange(0, 1)] isEqualToString:@"#"]) {
        // First char is #, get rid of that.
        rgba = [rgba substringFromIndex:1];
    }

    if (rgba.length < 8) {
        // If alpha is not given, just append ff.
        rgba = [NSString stringWithFormat:@"%@ff", rgba];
    }

    NSScanner *scanner = [NSScanner scannerWithString:rgba];
    [scanner setScanLocation:0];
    [scanner scanHexInt:&rgbaVal];

    return [UIColor colorWithRed:(rgbaVal >> 24 & 0xFF) / 255.0f
        green:(rgbaVal >> 16 & 0xFF) / 255.0f
        blue:(rgbaVal >> 8 & 0xFF) / 255.0f
        alpha:(rgbaVal & 0xFF) / 255.0f];
}

@end

@implementation CDVThemeableBrowserOptions

- (id)init
{
    if (self = [super init]) {
        // default values
        self.orientation=@"AUTO";
        self.location = YES;
        self.closebuttoncaption = nil;
        self.toolbarposition = kThemeableBrowserToolbarBarPositionBottom;
        self.clearcache = NO;
        self.clearsessioncache = NO;

        self.zoom = YES;
        self.enableviewportscale = NO;
        self.mediaplaybackrequiresuseraction = YES;
        self.allowinlinemediaplayback = NO;
        self.keyboarddisplayrequiresuseraction = YES;
        self.suppressesincrementalrendering = NO;
        self.hidden = NO;
        self.disallowoverscroll = NO;

        self.statusbar = nil;
        self.toolbar = nil;
        self.title = nil;
        self.backButton = nil;
        self.forwardButton = nil;
        self.reloadButton = nil;
        self.closeButton = nil;
        self.menu = nil;
        self.backButtonCanClose = NO;
        self.disableAnimation = NO;
        self.fullscreen = NO;
        self.allowsBackForwardNavigationGestures = NO;
    }

    return self;
}

@end

#pragma mark CDVScreenOrientationDelegate

@implementation CDVThemeableBrowserNavigationController : UINavigationController

- (BOOL)shouldAutorotate
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.orientationDelegate shouldAutorotate];
    }
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        return [self.orientationDelegate supportedInterfaceOrientations];
    }

    return 1 << UIInterfaceOrientationPortrait;
}


@end
