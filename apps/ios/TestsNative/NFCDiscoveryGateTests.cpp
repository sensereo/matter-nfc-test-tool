#include "../MatterIntegration/NFCDiscoveryGate.h"
#include <cassert>

int main() {
    NFCDiscoveryGate gate;
    // Initial/reset delegate clears do not spuriously close NFC.
    assert(!gate.delegateChanged(false));
    assert(!gate.delegateChanged(true));
    const auto expired = gate.start();
    assert(gate.delegateChanged(false));
    assert(!gate.complete(expired));
    assert(!gate.delegateChanged(false));

    // A selected tag survives StopDiscoveryOverNFC after successful PASE.
    gate.delegateChanged(true);
    const auto selected = gate.start();
    assert(gate.complete(selected));
    assert(!gate.complete(selected));
    assert(!gate.delegateChanged(false));

    // Old completion cannot clear a newer pending discovery.
    gate.delegateChanged(true);
    const auto old = gate.start();
    gate.stop();
    const auto current = gate.start();
    assert(!gate.complete(old));
    assert(gate.pending);
    assert(gate.complete(current));

    gate.start();
    gate.stop();
    assert(!gate.delegateChanged(false));
}
