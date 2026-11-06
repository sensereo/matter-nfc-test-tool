#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@class MTRDeviceController;

/// Implemented by the App. Every method is invoked on the main queue.
/// Completion blocks may be called on any queue, exactly once.
__attribute__((visibility("default")))
@protocol MNTNFCTransport <NSObject>
- (void)discoverTagWithDiscriminator:(uint16_t)discriminator
                        completion:(void (^)(NSNumber * _Nullable discriminator, NSError * _Nullable error))completion;
- (void)exchangeMessage:(NSData *)message
            completion:(void (^)(NSData * _Nullable response, NSError * _Nullable error))completion;
- (void)invalidate;
/// Fixed stage names only; no payload, discriminator, device address, or credentials.
- (void)recordBridgeEvent:(NSString *)event;
/// The commissioner stopped discovery before a tag was handed to it.
- (void)discoveryStopped;
@end

/// Compiled INSIDE the pinned custom Matter.framework, never against Apple's system framework.
__attribute__((visibility("default")))
@interface MNTNFCReaderBridge : NSObject
/// Call on the main queue after starting MTRDeviceControllerFactory.
/// Keep the factory running until removeTransportWithCompletion finishes.
+ (void)installTransport:(id<MNTNFCTransport>)transport completion:(void (^)(NSError * _Nullable error))completion;
/// Cancel commissioning first. Completion is delivered on the main queue after invalidation.
+ (void)removeTransportWithCompletion:(void (^)(void))completion;
/// Check the actual secure session's peer, since upstream may also discover on-network peers.
+ (void)verifyNFCSessionForController:(MTRDeviceController *)controller
                              nodeID:(NSNumber *)nodeID
                          completion:(void (^)(BOOL isNFC))completion;
@end

NS_ASSUME_NONNULL_END
