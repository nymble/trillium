// SPDX-License-Identifier: GPL-3.0-only
//
// Routing for app-generated MIDI (instrument view): which destinations get
// direct sends besides the "Trillium Instrument" virtual source, the saved
// choice, and the notes-off messages used by Reconnect MIDI. No CoreMIDI
// import, so it is tested on Linux too.
//
// Why direct sends: a music app lists virtual sources when it starts or
// rescans. If it misses the source (it was created later, or the app did
// not handle the setup change), nothing plays until the app is restarted.
// Sending straight to the app's own input (for example "Logic Pro Virtual
// In") does not depend on that discovery.
//
// Why opt-in: an app that also listens to "Trillium Instrument" would get
// every note twice. So direct sends start empty; picking a destination is
// the user's choice, and the source can be muted for apps that listen to
// every input.

import Foundation

public enum AppMIDIRouting {
    /// A CoreMIDI destination as the routing logic sees it.
    public struct Candidate: Equatable, Hashable, Sendable {
        public let id: Int32
        /// Stable label used to remember the choice (unique IDs of other
        /// apps' virtual inputs can change between launches).
        public let title: String
        public let isTrill: Bool
        public let isOffline: Bool

        public init(id: Int32, title: String, isTrill: Bool, isOffline: Bool) {
            self.id = id
            self.title = title
            self.isTrill = isTrill
            self.isOffline = isOffline
        }
    }

    /// Destinations offered for direct sends: online, not a Trillium board
    /// (its ports take configuration, not notes), one entry per unique ID
    /// and per title, in the order CoreMIDI lists them.
    public static func candidates(_ all: [Candidate]) -> [Candidate] {
        var ids = Set<Int32>(), titles = Set<String>(), out: [Candidate] = []
        for c in all where !c.isTrill && !c.isOffline {
            guard ids.insert(c.id).inserted, titles.insert(c.title).inserted else { continue }
            out.append(c)
        }
        return out
    }

    /// The destinations to send to now: the remembered titles that are
    /// present, each once.
    public static func targets(selected: Set<String>, among all: [Candidate]) -> [Candidate] {
        candidates(all).filter { selected.contains($0.title) }
    }

    /// All Sound Off (CC120) and All Notes Off (CC123) on each channel (0…15).
    public static func allNotesOff(channels: Set<Int>) -> [[UInt8]] {
        channels.filter { (0...15).contains($0) }.sorted().flatMap { ch -> [[UInt8]] in
            let s = 0xB0 | UInt8(ch)
            return [[s, 120, 0], [s, 123, 0]]
        }
    }
}

/// Channels that app-generated MIDI has used since the last reset, so
/// Reconnect MIDI can clear exactly those. Thread-safe (sends happen on the
/// CoreMIDI thread).
public final class MIDIChannelTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var used = Set<Int>()

    public init() {}

    /// Record the channel of a channel voice message (status 0x80…0xEF).
    public func record(_ bytes: [UInt8]) {
        guard let s = bytes.first, s >= 0x80, s < 0xF0 else { return }
        lock.lock(); used.insert(Int(s & 0x0F)); lock.unlock()
    }

    public var channels: Set<Int> { lock.lock(); defer { lock.unlock() }; return used }

    public func reset() { lock.lock(); used.removeAll(); lock.unlock() }
}

/// The saved routing choice for app-generated MIDI.
public struct AppMIDIRoutingPreference {
    public static let directKey = "instrumentDirectDestinations.v1"
    public static let sourceKey = "instrumentSendToSource.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Titles of destinations that get direct sends (empty by default).
    public var direct: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.directKey) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Self.directKey) }
    }

    /// Send through the "Trillium Instrument" source (on by default).
    public var toSource: Bool {
        get { defaults.object(forKey: Self.sourceKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.sourceKey) }
    }
}

/// Counters for app-generated MIDI, shown in the instrument view so a user
/// can tell whether notes leave Trillium at all (if they do and the synth
/// stays silent, the synth is not listening or not running). Thread-safe;
/// kept across Reconnect MIDI.
public final class AppMIDICounters: @unchecked Sendable {
    public struct Snapshot: Equatable, Sendable {
        /// Note-on messages sent (velocity > 0).
        public var notes = 0
        /// Messages the virtual source accepted.
        public var viaSource = 0
        /// Messages delivered to direct destinations (one per destination).
        public var viaDirect = 0
        /// Messages no route accepted, or a route refused.
        public var failed = 0
        /// Host time (seconds) of the last note-on, 0 if none.
        public var lastNoteAt: Double = 0

        public init() {}

        /// One line for the Output section, e.g. "Sent 12 notes · source 24 · direct 0 · last 3 s ago".
        public func summary(now: Double) -> String {
            var s = "Sent \(notes) note\(notes == 1 ? "" : "s") · source \(viaSource) · direct \(viaDirect)"
            if failed > 0 { s += " · failed \(failed)" }
            if notes > 0, lastNoteAt > 0 {
                let ago = max(0, Int((now - lastNoteAt).rounded()))
                s += " · last \(ago < 60 ? "\(ago) s" : "\(ago / 60) min") ago"
            }
            return s
        }
    }

    private let lock = NSLock()
    private var snap = Snapshot()

    public init() {}

    /// Record one message and how it was delivered.
    public func record(_ bytes: [UInt8], at time: Double, sourceOK: Bool?, directOK: Int, directFailed: Int) {
        lock.lock(); defer { lock.unlock() }
        if let s = bytes.first, s & 0xF0 == 0x90, bytes.count > 2, bytes[2] > 0 {
            snap.notes += 1
            snap.lastNoteAt = time
        }
        if sourceOK == true { snap.viaSource += 1 }
        snap.viaDirect += directOK
        let refused = (sourceOK == false ? 1 : 0) + directFailed
        if refused > 0 || (sourceOK == nil && directOK == 0) { snap.failed += max(refused, 1) }
    }

    public var snapshot: Snapshot { lock.lock(); defer { lock.unlock() }; return snap }

    public func reset() { lock.lock(); snap = Snapshot(); lock.unlock() }
}
