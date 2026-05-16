#pragma once

#include <juce_core/juce_core.h>

#include <atomic>
#include <vector>

#include "LuaHost.h"

// ---------------------------------------------------------------------------
// EventQueue — SPSC lock-free handoff of MidiEvent records between the
// worker thread (producer) and processBlock (consumer).
//
// Built around juce::AbstractFifo, which provides the index arithmetic for
// a power-of-two ring buffer with one writer and one reader. Reads and
// writes never touch the same slot at the same time, so no locks are
// required on either side.
//
// On top of the fifo we layer a "generation id": every time the worker
// starts a new generation it bumps the id, and the consumer compares the
// id to its last-seen value so it knows when to discard its cached event
// list and start playback from event 0 again. This is what gives the
// audio thread a clean "swap" point on parameter changes without dropping
// into a lock.
// ---------------------------------------------------------------------------
class EventQueue
{
public:
    // Plenty of room for a 64-bar progression with arp + melody layers;
    // way overkill for the I-IV-V-I chord progression Phase 4 ships with.
    static constexpr int kCapacity = 4096;

    EventQueue();

    // ------ Producer (worker thread) -------------------------------------
    // Discard anything the consumer hasn't drained yet and start a fresh
    // generation. Subsequent pushEvents() calls feed into this generation.
    void beginGeneration();

    // Push `count` events into the queue. Returns the number actually
    // written — short writes only happen if `count` > free space, which
    // shouldn't occur in normal use given kCapacity = 4096.
    int pushEvents (const LuaHost::MidiEvent* events, int count);

    // ------ Consumer (audio thread) --------------------------------------
    // If the worker has started a new generation since the last call,
    // clears `out` and copies every event of the new generation into it.
    // Returns true when a new generation was consumed (caller should
    // reset its playback cursor); false when nothing changed.
    //
    // Allocation-free as long as `out.capacity() >= kCapacity`; the
    // processor pre-reserves in prepareToPlay.
    bool drainTo (std::vector<LuaHost::MidiEvent>& out);

    int generationId() const noexcept
    {
        return generationCounter.load (std::memory_order_acquire);
    }

private:
    juce::AbstractFifo              fifo { kCapacity };
    std::vector<LuaHost::MidiEvent> buffer;

    // Bumped by beginGeneration(). The consumer reads it inside drainTo
    // and compares to lastConsumedGen (consumer-only state) to detect
    // when the producer has published a new event list.
    std::atomic<int> generationCounter { 0 };
    int              lastConsumedGen   { 0 };
};
