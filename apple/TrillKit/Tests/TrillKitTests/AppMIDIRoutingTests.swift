// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import TrillKit

final class AppMIDIRoutingTests: XCTestCase {
    typealias C = AppMIDIRouting.Candidate

    let logic = C(id: 11, title: "Logic Pro Virtual In", isTrill: false, isOffline: false)
    let synth = C(id: 12, title: "Synth One", isTrill: false, isOffline: false)
    let board = C(id: 13, title: "Trillium – Port 1", isTrill: true, isOffline: false)
    let gone = C(id: 14, title: "Old Synth", isTrill: false, isOffline: true)

    func testCandidatesSkipTheBoardOfflineAndDuplicates() {
        let dupID = C(id: 11, title: "Logic Pro Virtual In (copy)", isTrill: false, isOffline: false)
        let dupTitle = C(id: 21, title: "Synth One", isTrill: false, isOffline: false)
        XCTAssertEqual(AppMIDIRouting.candidates([logic, board, gone, synth, dupID, dupTitle]), [logic, synth])
    }

    func testDirectSendsAreOptInAndFollowTheTitle() {
        XCTAssertEqual(AppMIDIRouting.targets(selected: [], among: [logic, synth]), [])
        XCTAssertEqual(AppMIDIRouting.targets(selected: ["Synth One"], among: [logic, synth]), [synth])
        // The app relaunched with a new unique ID: the remembered title still matches.
        let relaunched = C(id: 99, title: "Synth One", isTrill: false, isOffline: false)
        XCTAssertEqual(AppMIDIRouting.targets(selected: ["Synth One"], among: [logic, relaunched]), [relaunched])
        // Not running: nothing to send to, the choice stays.
        XCTAssertEqual(AppMIDIRouting.targets(selected: ["Synth One"], among: [logic]), [])
        // The board can never be a direct target, even if named.
        XCTAssertEqual(AppMIDIRouting.targets(selected: [board.title], among: [board]), [])
    }

    func testAllNotesOffPerChannel() {
        XCTAssertEqual(AppMIDIRouting.allNotesOff(channels: [9, 0, 16, -1]),
                       [[0xB0, 120, 0], [0xB0, 123, 0], [0xB9, 120, 0], [0xB9, 123, 0]])
        XCTAssertEqual(AppMIDIRouting.allNotesOff(channels: []), [])
    }

    func testChannelTrackerRecordsChannelVoiceOnly() {
        let t = MIDIChannelTracker()
        t.record([0x93, 60, 100])
        t.record([0x83, 60, 0])
        t.record([0xBA, 1, 2])
        t.record([0xF8])
        t.record([0x40, 1])
        XCTAssertEqual(t.channels, [3, 10])
        t.reset()
        XCTAssertEqual(t.channels, [])
    }

    func testRoutingPreferenceDefaults() {
        let suite = "AppMIDIRoutingTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let p = AppMIDIRoutingPreference(defaults: d)
        XCTAssertEqual(p.direct, [])
        XCTAssertTrue(p.toSource)
        p.direct = ["Synth One", "Logic Pro Virtual In"]
        p.toSource = false
        XCTAssertEqual(AppMIDIRoutingPreference(defaults: d).direct, ["Synth One", "Logic Pro Virtual In"])
        XCTAssertFalse(AppMIDIRoutingPreference(defaults: d).toSource)
    }
}

#if canImport(CoreMIDI)
import CoreMIDI

/// Real CoreMIDI: direct sends reach a virtual destination; muting the
/// source does not stop them; notes off covers every channel used.
final class AppMIDIDirectSendTests: XCTestCase {
    func testDirectSendAndNotesOffReachADestination() throws {
        var client = MIDIClientRef(), dest = MIDIEndpointRef()
        guard MIDIClientCreateWithBlock("TrillKitTests Synth" as CFString, &client, nil) == noErr else {
            throw XCTSkip("CoreMIDI server unavailable on this host")
        }
        defer { MIDIClientDispose(client) }
        let lock = NSLock()
        var words: [UInt32] = []
        let status = MIDIDestinationCreateWithProtocol(client, "Fake Synth In" as CFString, ._1_0, &dest) { list, _ in
            MIDIClient.forEachPacket(list) { _, w in lock.lock(); words += w; lock.unlock() }
        }
        guard status == noErr else { throw XCTSkip("virtual destination not permitted here (OSStatus \(status))") }
        defer { MIDIEndpointDispose(dest) }
        var id: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(dest, kMIDIPropertyUniqueID, &id)

        let out = try AppMIDISource(name: "TrillKitTests Instrument")
        XCTAssertEqual(out.setRoutes(toSource: false, direct: [id, 0x7FFF_FFF0]), 1, "unknown IDs are dropped")
        XCTAssertTrue(out.send([0x92, 62, 90]))
        out.allNotesOff(channels: [0])
        let expected: [UInt32] = [0x2092_3E5A, 0x20B0_7800, 0x20B0_7B00, 0x20B2_7800, 0x20B2_7B00]
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            lock.lock(); let n = words.count; lock.unlock()
            if n >= expected.count { break }
        }
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(words, expected)
    }
}
#endif
