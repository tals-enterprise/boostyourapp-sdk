#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

// Expose le module Swift BoostNetworkModule à JavaScript sous le nom BoostNetwork
@interface RCT_EXTERN_REMAP_MODULE(BoostNetwork, BoostNetworkModule, RCTEventEmitter)

RCT_EXTERN_METHOD(start:(NSString *)appKey
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(showBanner:(NSString *)position
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setStyle:(NSString *)style
                  palette:(NSString *)palette
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(loadInterstitial:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(isInterstitialReady:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(showInterstitial:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(hideBanner:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setEndpoint:(NSString *)apiUrl
                  apiKey:(NSString *)apiKey
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end
