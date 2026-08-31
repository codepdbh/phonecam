#include "phonecam_shared_memory.h"

#include <iostream>

int main() {
    PhoneCamSharedMemory broker;
    if (!broker.Initialize(false)) {
        std::cerr << "PhoneCam broker is unavailable.\n";
        return 1;
    }
    const PhoneCamBrokerStats stats = broker.GetStats();
    std::cout << "requests=" << stats.sampleRequests
              << " produced=" << stats.samplesProduced
              << " starts=" << stats.streamStarts
              << " states=" << stats.streamStateChanges
              << " constructed=" << stats.streamConstructed
              << " sourceAttrs=" << stats.sourceGetAttributes
              << " streamAttrs=" << stats.streamGetAttributes
              << " descriptors=" << stats.presentationDescriptors
              << " allocatorQueries=" << stats.allocatorUsageQueries
              << " allocatorsSet=" << stats.allocatorsSet
              << " sourceStarts=" << stats.sourceStarts
              << " published=" << stats.publishedFrames
              << " producer=" << stats.producerPid << "\n";
    return 0;
}
