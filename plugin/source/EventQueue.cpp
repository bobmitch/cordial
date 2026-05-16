#include "EventQueue.h"

EventQueue::EventQueue()
{
    buffer.resize (static_cast<std::size_t> (kCapacity));
}

void EventQueue::beginGeneration()
{
    // Drop anything the consumer hasn't read yet — the next generation
    // supersedes it. Producer-only, so resetting the indices is safe.
    fifo.reset();
    generationCounter.fetch_add (1, std::memory_order_release);
}

int EventQueue::pushEvents (const LuaHost::MidiEvent* events, int count)
{
    int start1, size1, start2, size2;
    fifo.prepareToWrite (count, start1, size1, start2, size2);

    for (int i = 0; i < size1; ++i)
        buffer[static_cast<std::size_t> (start1 + i)] = events[i];
    for (int i = 0; i < size2; ++i)
        buffer[static_cast<std::size_t> (start2 + i)] = events[size1 + i];

    const int written = size1 + size2;
    fifo.finishedWrite (written);
    return written;
}

bool EventQueue::drainTo (std::vector<LuaHost::MidiEvent>& out)
{
    const int gen = generationCounter.load (std::memory_order_acquire);
    const int ready = fifo.getNumReady();

    if (gen == lastConsumedGen && ready == 0)
        return false;

    int start1, size1, start2, size2;
    fifo.prepareToRead (ready, start1, size1, start2, size2);

    // Clear and refill. push_back into a pre-reserved vector doesn't
    // allocate, so processBlock stays heap-clean as long as the worker
    // never publishes more than capacity events.
    out.clear();
    for (int i = 0; i < size1; ++i)
        out.push_back (buffer[static_cast<std::size_t> (start1 + i)]);
    for (int i = 0; i < size2; ++i)
        out.push_back (buffer[static_cast<std::size_t> (start2 + i)]);

    fifo.finishedRead (size1 + size2);
    lastConsumedGen = gen;
    return true;
}
