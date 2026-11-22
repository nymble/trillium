// SPDX-License-Identifier: GPL-3.0-only
//
// The app's own MIDI output for app-generated MIDI (instrument view). A
// separate CoreMIDI client so MIDIClient keeps its rule of never creating
// virtual endpoints. Music apps see the virtual source "Trillium
// Instrument". The app never connects its own inputs to it (AppModel
// filters it out of the source lists), so it cannot form a loop.
//
// Besides the source, the same messages can go straight to chosen
// destinations through an output port (AppMIDIRouting explains why and
// why it is opt-in).

#if canImport(CoreMIDI)
import CoreMIDI
import Foundation

public final class AppMIDISource: @unchecked Sendable {
    public static let defaultName = "Trillium Instrument"

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var outPort = MIDIPortRef()
    public let name: String
    /// Channels used since creation (for notes off on reconnect).
    public let channels = MIDIChannelTracker()

    private let lock = NSLock()
    private var direct: [MIDIEndpointRef] = []
    private var toSource = true

    public init(name: String = AppMIDISource.defaultName) throws {
        self.name = name
        var status = MIDIClientCreateWithBlock("\(name) Client" as CFString, &client) { _ in }
        guard status == noErr else { throw MIDIClient.Failure(call: "MIDIClientCreateWithBlock", status: status) }
        status = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source)
        guard status == noErr else {
            MIDIClientDispose(client)
            throw MIDIClient.Failure(call: "MIDISourceCreateWithProtocol", status: status)
        }
        status = MIDIOutputPortCreate(client, "\(name) Direct" as CFString, &outPort)
        guard status == noErr else {
            MIDIEndpointDispose(source)
            MIDIClientDispose(client)
            throw MIDIClient.Failure(call: "MIDIOutputPortCreate", status: status)
        }
    }

    deinit {
        MIDIPortDispose(outPort)
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
    }

    /// CoreMIDI unique ID of the source (to keep it out of the app's own inputs).
    public var uniqueID: MIDIUniqueID {
        var id: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id)
        return id
    }

    /// Where messages go: the virtual source (or not) and destinations by
    /// unique ID. Returns how many destinations were found.
    @discardableResult
    public func setRoutes(toSource: Bool, direct ids: [MIDIUniqueID]) -> Int {
        let eps: [MIDIEndpointRef] = ids.compactMap { id in
            var obj = MIDIObjectRef(), type = MIDIObjectType.other
            guard MIDIObjectFindByUniqueID(id, &obj, &type) == noErr, type == .destination || type == .externalDestination
            else { return nil }
            return MIDIEndpointRef(obj)
        }
        lock.lock(); self.toSource = toSource; direct = eps; lock.unlock()
        return eps.count
    }

    /// Send one MIDI 1.0 channel voice message (2 or 3 bytes) now, to the
    /// source and the direct destinations. True if at least one took it.
    @discardableResult
    public func send(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2, bytes[0] & 0x80 != 0, bytes[0] < 0xF0 else { return false }
        channels.record(bytes)
        let word: UInt32 = 0x2000_0000 | UInt32(bytes[0]) << 16 | UInt32(bytes[1] & 0x7F) << 8
            | UInt32(bytes.count > 2 ? bytes[2] & 0x7F : 0)
        let size = 256
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        let packet = MIDIEventListInit(list, ._1_0)
        var w = word
        guard MIDIEventListAdd(list, size, packet, 0, 1, &w) != nil else { return false }
        lock.lock(); let src = toSource, eps = direct; lock.unlock()
        var ok = false
        if src { ok = MIDIReceivedEventList(source, list) == noErr || ok }
        for ep in eps { ok = MIDISendEventList(outPort, ep, list) == noErr || ok }
        return ok
    }

    /// All Sound Off and All Notes Off on the given channels plus every
    /// channel used so far, through the current routes.
    public func allNotesOff(channels extra: Set<Int>) {
        for m in AppMIDIRouting.allNotesOff(channels: channels.channels.union(extra)) { send(m) }
    }
}
#endif
