#pragma once
#include <cstdint>

// Matter-queue confined. A cleared discovery delegate must not close a selected tag.
struct NFCDiscoveryGate {
    uint64_t generation = 0;
    bool pending = false;

    bool delegateChanged(bool present) {
        ++generation;
        const bool stopped = !present && pending;
        if (stopped) { pending = false; }
        return stopped;
    }
    uint64_t start() { pending = true; return ++generation; }
    bool complete(uint64_t token) {
        if (!pending || token != generation) { return false; }
        pending = false;
        ++generation;
        return true;
    }
    void stop() { pending = false; ++generation; }
};
