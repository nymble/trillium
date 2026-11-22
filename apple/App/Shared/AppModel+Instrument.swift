// SPDX-License-Identifier: GPL-3.0-only
//
// Instrument view state (docs/instrument-view.md): saved choices, the app's
// own MIDI source, and a synthetic motion demo for screenshots.

import Foundation
import os
import TrillKit

private let midiLog = Logger(subsystem: "net.nymbus.trillium", category: "app-midi")

/// Instrument view choices, saved on this device.
struct InstrumentPrefs: Codable, Equatable {
    /// Telemetry rate requested while the instrument view or app-generated MIDI is on.
    static let telemetryRateHz = 100
    static let defaultsKey = "instrumentPrefs.v1"

    var settings = ImpulseSettings()
    var scaleID = HandpanScale.all[0].id
    var dingMIDI = HandpanScale.all[0].ding.midi
    var layout = HandpanLayout.clockwise
    /// 0…15
    var channel = 0
    var gate = 0.4

    var scale: HandpanScale { HandpanScale.named(scaleID) ?? HandpanScale.all[0] }
    var handpan: HandpanInstrument { HandpanInstrument(scale: scale, dingMIDI: dingMIDI, layout: layout) }

    static func load() -> InstrumentPrefs {
        guard let d = UserDefaults.standard.data(forKey: defaultsKey),
              let p = try? JSONDecoder().decode(InstrumentPrefs.self, from: d) else { return InstrumentPrefs() }
        return p
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.defaultsKey) }
    }
}

extension AppModel {
    /// App-generated MIDI is on (the app's own "Trillium Instrument" source exists).
    var instrumentMIDIOn: Bool { appMIDISource != nil }

    var instrumentNeedsTelemetry: Bool { instrumentVisible || instrumentMIDIOn }

    func setInstrumentMIDI(_ on: Bool) {
        objectWillChange.send()
        if on, appMIDISource == nil {
            do {
                let src = try AppMIDISource()
                appMIDISource = src
                instrument.send = { [weak src] bytes in _ = src?.send(bytes) }
                instrumentMIDIError = nil
                midiLog.info("app MIDI source created")
            } catch {
                instrumentMIDIError = error.localizedDescription
            }
        } else if !on, appMIDISource != nil {
            instrument.send = nil
            appMIDISource = nil
        }
        AppMIDIPreference().isOn = appMIDISource != nil
        #if os(iOS)
        // Without running audio iOS suspends the app soon after the user
        // switches to a synth or monitor, and no notes are sent.
        keepAlive.setActive(appMIDISource != nil)
        if appMIDISource != nil, !keepAlive.isRunning {
            instrumentMIDIError = "Could not keep running in the background" + (keepAlive.lastError.map { ": \($0)" } ?? "")
                + ". Notes play only while Trillium is on screen."
        }
        #endif
        refreshEndpoints()
    }

    // MARK: Routing and Reconnect MIDI

    /// Destinations that can get direct sends (not the board, online, unique).
    var directCandidates: [AppMIDIRouting.Candidate] {
        AppMIDIRouting.candidates(destinations.map {
            AppMIDIRouting.Candidate(id: $0.id, title: $0.title, isTrill: $0.isTrill, isOffline: $0.isOffline)
        })
    }

    var directSelection: Set<String> { AppMIDIRoutingPreference().direct }

    func setDirect(_ title: String, _ on: Bool) {
        var sel = AppMIDIRoutingPreference().direct
        if on { sel.insert(title) } else { sel.remove(title) }
        AppMIDIRoutingPreference().direct = sel
        objectWillChange.send()
        applyInstrumentRoutes()
    }

    var sendToAppSource: Bool {
        get { AppMIDIRoutingPreference().toSource }
        set { AppMIDIRoutingPreference().toSource = newValue; objectWillChange.send(); applyInstrumentRoutes() }
    }

    /// Point the app's MIDI output at the source and the chosen destinations
    /// that are present now. Called on every MIDI setup change.
    func applyInstrumentRoutes() {
        guard let src = appMIDISource else { return }
        let pref = AppMIDIRoutingPreference()
        let targets = AppMIDIRouting.targets(selected: pref.direct, among: directCandidates)
        src.setRoutes(toSource: pref.toSource, direct: targets.map(\.id))
    }

    /// Reconnect MIDI: notes off through the current routes, then a new
    /// source and client, routes applied again and notes off once more so
    /// a synth that kept a note hanging is cleared.
    func reconnectInstrumentMIDI() {
        let channels = (appMIDISource?.channels.channels ?? []).union([instrumentPrefs.channel])
        appMIDISource?.allNotesOff(channels: channels)
        instrument.send = nil
        appMIDISource = nil
        setInstrumentMIDI(true)
        guard let src = appMIDISource else {
            instrumentMIDIStatus = "Reconnect failed" + (instrumentMIDIError.map { ": \($0)" } ?? "")
            midiLog.error("reconnect failed")
            return
        }
        src.allNotesOff(channels: channels)
        let pref = AppMIDIRoutingPreference()
        let n = AppMIDIRouting.targets(selected: pref.direct, among: directCandidates).count
        let time = Date().formatted(date: .omitted, time: .standard)
        var parts = [pref.toSource ? "\(AppMIDISource.defaultName) recreated" : "\(AppMIDISource.defaultName) recreated (muted)"]
        if n > 0 { parts.append("direct to \(n) destination\(n == 1 ? "" : "s")") }
        parts.append("notes off on channel \(channels.sorted().map { String($0 + 1) }.joined(separator: ", "))")
        instrumentMIDIStatus = "Reconnected \(time): " + parts.joined(separator: ", ")
        midiLog.info("reconnected: \(parts.joined(separator: ", "), privacy: .public)")
    }

    func instrumentPrefsChanged(from old: InstrumentPrefs) {
        guard instrumentPrefs != old else { return }
        instrument.settings = instrumentPrefs.settings
        instrument.instrument = instrumentPrefs.handpan
        instrument.channel = instrumentPrefs.channel
        instrument.gate = instrumentPrefs.gate
        instrumentPrefs.save()
    }

    /// "Set current pose as up".
    func setCurrentPoseAsUp() {
        guard let up = instrument.currentPoseAsUp() else { return }
        instrumentPrefs.settings.up = up
        instrumentPrefs.settings.northOffset = 0
    }

    /// Rotate the labels so the last strike's direction becomes N.
    func makeLastStrikeNorth() {
        guard let s = instrumentSnapshot.lastStrike?.sector else { return }
        instrumentPrefs.settings.northOffset = (instrumentPrefs.settings.northOffset + s) % 8
    }

    func resetInstrumentRoll() {
        instrument.resetRoll()
        instrumentSnapshot = instrument.snapshot()
    }

    /// Called from the UI timer.
    func instrumentTick() {
        if let d = instrumentDemo { d.step(until: MIDIClient.now(), runner: instrument) }
        guard instrumentVisible else { return }
        let s = instrument.snapshot()
        if s != instrumentSnapshot { instrumentSnapshot = s }
    }

    /// Synthetic motion for the Simulator screenshots (`--instrument-demo`).
    func startInstrumentDemo() {
        instrumentDemo = InstrumentDemo(start: MIDIClient.now())
    }
}

/// A scripted performance: tilted 12°, turning slowly, a strike every 0.6 s
/// going round the compass. Feeds the same engine as the board does; sends
/// MIDI only if app-generated MIDI is switched on.
final class InstrumentDemo {
    private var t: Double
    private let start: Double
    private let rate = 100.0
    private var taps = 0

    init(start: Double) { self.start = start; t = start - 1.5 }

    func step(until now: Double, runner: InstrumentRunner) {
        while t < now {
            let rel = t - start
            // Tilt 12° toward E (about the N axis, device X), turning about up at 40°/s.
            let tilt = 12.0 * .pi / 180
            let up = Vec3(0, sin(tilt), cos(tilt))
            var accel = up
            let k = Int((rel / 0.6).rounded(.down))
            let phase = rel - Double(k) * 0.6
            if rel > 0, phase < 0.02 {
                // Strike: N, NE, E … with rising strength.
                let ang = Double((k % 8 + 8) % 8) * 45 * .pi / 180
                let g = 1.0 + Double((k % 4 + 4) % 4) * 0.6
                let n = Vec3(1, 0, 0), e = Vec3(0, -cos(tilt), sin(tilt))
                accel = accel + n * (cos(ang) * g) + e * (sin(ang) * g)
            } else if rel > 0, phase < 0.3 {
                // Ring-down after the strike, below threshold.
                let decay = exp(-phase * 12) * 0.35
                accel = accel + Vec3(cos(rel * 40) * decay, sin(rel * 40) * decay, 0)
            }
            let gyro = up * 40
            runner.process(time: t, accel: accel, gyro: gyro, taps: taps, hostTime: t)
            t += 1 / rate
        }
    }
}
