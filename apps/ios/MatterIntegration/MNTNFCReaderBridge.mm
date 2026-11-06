#import "MNTNFCReaderBridge.h"
#import <Matter/MTRDeviceControllerFactory.h>
#import "MTRDeviceController_Concrete.h"

#include <nfc/NFCReaderTransport.h>
#include <platform/CHIPDeviceLayer.h>
#include <platform/internal/NFCCommissioningManager.h>
#include <memory>
#include <optional>
#include "NFCDiscoveryGate.h"

#if !CHIP_DEVICE_CONFIG_ENABLE_NFC_BASED_COMMISSIONING || TARGET_OS_OSX
#error This bridge requires the iOS Darwin NFC commissioning implementation.
#endif

using namespace chip;
using namespace chip::DeviceLayer;

namespace {
class Reader;
Reader * installedReader = nullptr; // Matter work queue only; constant initialization.
// All State fields are confined to Matter's work queue. Main-queue blocks receive
// copied Objective-C objects and dispatch results back before examining State.
struct State {
    explicit State(id<MNTNFCTransport> value) : transport(value) {}
    __strong id<MNTNFCTransport> transport;
    Nfc::NFCReaderTransportDelegate * delegate = nullptr;
    std::optional<uint16_t> selected;
    NFCDiscoveryGate discovery;
    uint64_t message = 0;
    bool alive = true;
    bool busy = false;
};

void Record(const std::shared_ptr<State> & state, NSString * event) {
    id<MNTNFCTransport> transport = state->transport;
    dispatch_async(dispatch_get_main_queue(), ^{ [transport recordBridgeEvent:event]; });
}

class Reader final : public Nfc::NFCReaderTransport {
public:
    explicit Reader(id<MNTNFCTransport> transport) : state(std::make_shared<State>(transport)) {}
    ~Reader() override {
        if (installedReader == this) { installedReader = nullptr; }
        state->alive = false;
        state->delegate = nullptr;
        id<MNTNFCTransport> transport = state->transport;
        dispatch_async(dispatch_get_main_queue(), ^{ [transport invalidate]; });
    }

    void SetDelegate(Nfc::NFCReaderTransportDelegate * delegate) override {
        Record(state, delegate ? @"delegate.attached" : @"delegate.cleared");
        const bool stoppedWhilePending = state->discovery.delegateChanged(delegate != nullptr);
        state->delegate = delegate;
        if (stoppedWhilePending) {
            id<MNTNFCTransport> transport = state->transport;
            // Do not keep showing an NFC scan after the commissioner's discovery window ends.
            // A selected tag keeps its session when the discovery delegate is cleared.
            dispatch_async(dispatch_get_main_queue(), ^{ [transport discoveryStopped]; });
        }
    }

    CHIP_ERROR StartDiscoveringTagMatchingAddress(const Nfc::NFCTag::Identifier & identifier) override {
        if (!state->delegate || state->busy || identifier.discriminator > 0x0fff) {
            return CHIP_ERROR_INCORRECT_STATE;
        }
        state->selected.reset();
        Record(state, @"discovery.started");
        const uint16_t expected = identifier.discriminator;
        const uint64_t generation = state->discovery.start();
        auto shared = state;
        id<MNTNFCTransport> transport = state->transport;
        dispatch_queue_t queue = PlatformMgrImpl().GetWorkQueue();
        dispatch_async(dispatch_get_main_queue(), ^{
            [transport discoverTagWithDiscriminator:expected completion:^(NSNumber * found, NSError * error) {
                dispatch_async(queue, ^{
                    Record(shared, @"discovery.completion.received");
                    if (!shared->alive || !shared->delegate || !shared->discovery.complete(generation)) {
                        Record(shared, @"discovery.completion.ignored");
                        return;
                    }
                    if (error || !found || found.unsignedIntegerValue != expected) {
                        shared->delegate->OnTagDiscoveryFailed(CHIP_ERROR_NOT_FOUND);
                        return;
                    }
                    shared->selected = expected;
                    Record(shared, @"tag.discovered.delivered");
                    shared->delegate->OnTagDiscovered(Nfc::NFCTag::Identifier{ expected });
                    Record(shared, @"tag.discovered.returned");
                });
            }];
        });
        return CHIP_NO_ERROR;
    }

    CHIP_ERROR StopDiscoveringTags() override {
        state->discovery.stop();
        Record(state, @"discovery.stop_requested");
        state->selected.reset();
        id<MNTNFCTransport> transport = state->transport;
        dispatch_async(dispatch_get_main_queue(), ^{ [transport invalidate]; });
        return CHIP_NO_ERROR;
    }

    bool FindTagMatchingIdentifier(const Nfc::NFCTag::Identifier & identifier) override {
        const bool found = state->alive && state->selected && *state->selected == identifier.discriminator;
        Record(state, found ? @"tag.lookup.match" : @"tag.lookup.miss");
        return found;
    }

    CHIP_ERROR SendMessage(System::PacketBufferHandle && message, const Nfc::NFCTag::Identifier & identifier,
                          std::function<void(System::PacketBufferHandle &&, CHIP_ERROR)> callback) override {
        Record(state, @"message.send.requested");
        if (!FindTagMatchingIdentifier(identifier) || state->busy) {
            Record(state, @"message.send.rejected_state");
            return CHIP_ERROR_INCORRECT_STATE;
        }
        if (message.IsNull() || message->DataLength() == 0 || message->DataLength() > 1280 ||
            message->TotalLength() != message->DataLength()) {
            Record(state, @"message.send.rejected_length");
            return CHIP_ERROR_INVALID_MESSAGE_LENGTH;
        }
        NSData * bytes = [NSData dataWithBytes:message->Start() length:message->DataLength()];
        state->busy = true;
        const uint64_t generation = ++state->message;
        auto shared = state;
        id<MNTNFCTransport> transport = state->transport;
        dispatch_queue_t queue = PlatformMgrImpl().GetWorkQueue();
        dispatch_async(dispatch_get_main_queue(), ^{
            [transport exchangeMessage:bytes completion:^(NSData * response, NSError * error) {
                // Own the bytes before crossing queues; never expose a PacketBuffer pointer to Swift.
                NSData * owned = [response copy];
                dispatch_async(queue, ^{
                    if (!shared->alive || shared->message != generation || !shared->busy) { return; }
                    shared->busy = false;
                    if (error || !shared->selected || owned.length == 0 || owned.length > 1280) {
                        shared->selected.reset();
                        callback(System::PacketBufferHandle(), CHIP_ERROR_INTERNAL);
                        return;
                    }
                    auto buffer = System::PacketBufferHandle::NewWithData(owned.bytes, owned.length);
                    if (buffer.IsNull()) {
                        callback(System::PacketBufferHandle(), CHIP_ERROR_NO_MEMORY);
                    } else {
                        callback(std::move(buffer), CHIP_NO_ERROR);
                    }
                });
            }];
        });
        return CHIP_NO_ERROR;
    }

private:
    std::shared_ptr<State> state;
};

NSError * BridgeError(NSString * message) {
    return [NSError errorWithDomain:@"MatterNFCTest.ReaderBridge" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}
} // namespace

@implementation MNTNFCReaderBridge
+ (void)verifyNFCSessionForController:(MTRDeviceController *)controller
                              nodeID:(NSNumber *)nodeID
                          completion:(void (^)(BOOL))completion {
    if (![controller isKindOfClass:MTRDeviceController_Concrete.class]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        return;
    }
    [(MTRDeviceController_Concrete *)controller asyncGetCommissionerOnMatterQueue:^(Controller::DeviceCommissioner * commissioner) {
        CommissioneeDeviceProxy * device = nullptr;
        bool isNFC = false;
        if (commissioner->GetDeviceBeingCommissioned(nodeID.unsignedLongLongValue, &device) == CHIP_NO_ERROR && device) {
            auto session = device->GetSecureSession();
            isNFC = session.HasValue() && session.Value()->AsSecureSession() &&
                session.Value()->AsSecureSession()->GetPeerAddress().GetTransportType() == Transport::Type::kNfc;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(isNFC); });
    } errorHandler:^(NSError *) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
    }];
}

+ (void)installTransport:(id<MNTNFCTransport>)transport completion:(void (^)(NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Call from main queue");
    if (!MTRDeviceControllerFactory.sharedInstance.isRunning) {
        completion(BridgeError(@"Start the Matter controller factory before installing NFC transport."));
        return;
    }
    dispatch_async(PlatformMgrImpl().GetWorkQueue(), ^{
        auto & manager = Internal::NFCCommissioningMgr();
        NSError * error = nil;
        if (manager.GetNFCReaderTransport() != nullptr) {
            error = BridgeError(@"An NFC reader transport is already installed.");
        } else {
            installedReader = new Reader(transport);
            manager.SetNFCReaderTransport(installedReader);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

+ (void)removeTransportWithCompletion:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread, @"Call from main queue");
    if (!MTRDeviceControllerFactory.sharedInstance.isRunning) {
        completion();
        return;
    }
    dispatch_async(PlatformMgrImpl().GetWorkQueue(), ^{
        auto & manager = Internal::NFCCommissioningMgr();
        if (installedReader && manager.GetNFCReaderTransport() == installedReader) {
            manager.SetNFCReaderTransport(nullptr);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(); });
    });
}
@end
