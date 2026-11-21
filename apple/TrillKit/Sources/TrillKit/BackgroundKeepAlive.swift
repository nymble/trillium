// SPDX-License-Identifier: GPL-3.0-only
//
// Keeps the iOS app running in the background while app-generated MIDI is
// on. iOS suspends an app shortly after the user switches away unless it
// is playing audio, even with the `audio` background mode declared. While
// suspended, nothing reads the board's telemetry or renews its lease, so
// the instrument view plays nothing into the synth or monitor the user
// switched to. The established pattern for virtual MIDI on iOS is a mixable
// playback session with a running engine that renders silence.
//
// KeepAliveController is the platform-independent state machine (tested on
// Linux and macOS); SilentAudioKeepAlive is the iOS implementation.

import Foundation

public final class KeepAliveController {
    public enum Event: Equatable {
        /// The app wants (or no longer wants) to stay alive.
        case want(Bool)
        /// The system stopped audio (call, Siri, another non-mixable app).
        case interruptionBegan
        /// The interruption ended, the route changed or the engine was reconfigured.
        case interruptionEnded
        /// The audio system was reset; engines must be rebuilt.
        case mediaServicesReset
    }

    public private(set) var wanted = false
    public private(set) var running = false
    public private(set) var starts = 0

    private let start: () -> Bool
    private let stop: () -> Void

    /// `start` returns true when audio is running; `stop` releases it.
    public init(start: @escaping () -> Bool, stop: @escaping () -> Void) {
        self.start = start
        self.stop = stop
    }

    public func handle(_ e: Event) {
        switch e {
        case let .want(on):
            wanted = on
            if on, !running { begin() }
            if !on, running { stop(); running = false }
        case .interruptionBegan:
            running = false
        case .interruptionEnded, .mediaServicesReset:
            guard wanted else { return }
            if running { stop(); running = false }
            begin()
        }
    }

    private func begin() {
        starts += 1
        running = start()
    }
}

/// The user's App-generated MIDI switch, kept across launches so the
/// "Trillium Instrument" source exists from launch (music apps opened later
/// list it without a refresh).
public struct AppMIDIPreference {
    public static let key = "instrumentAppMIDI.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var isOn: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}

#if os(iOS) && canImport(AVFAudio)
import AVFAudio

/// Silent, mixable playback that keeps the app scheduled in the background.
/// Renders zeros at volume 0 and mixes with other apps, so a synth keeps
/// its own audio.
public final class SilentAudioKeepAlive {
    private var engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    public private(set) var lastError: String?
    private lazy var controller = KeepAliveController(
        start: { [weak self] in self?.startEngine() ?? false },
        stop: { [weak self] in self?.stopEngine() })

    public init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self?.controller.handle(type == .began ? .interruptionBegan : .interruptionEnded)
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.engine = AVAudioEngine()
            self.node = nil
            self.controller.handle(.mediaServicesReset)
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as? AVAudioEngine) === self.engine, !self.engine.isRunning else { return }
            self.controller.handle(.interruptionEnded)
        })
    }

    deinit { for o in observers { NotificationCenter.default.removeObserver(o) } }

    public var isRunning: Bool { controller.running }

    public func setActive(_ on: Bool) { controller.handle(.want(on)) }

    private func startEngine() -> Bool {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try s.setActive(true)
            if node == nil {
                let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
                guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 48_000, channels: 2) else {
                    lastError = "no audio format"; return false
                }
                let n = AVAudioSourceNode(format: fmt) { silence, _, _, list in
                    for b in UnsafeMutableAudioBufferListPointer(list) {
                        if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) }
                    }
                    silence.pointee = true
                    return noErr
                }
                engine.attach(n)
                engine.connect(n, to: engine.mainMixerNode, format: fmt)
                engine.mainMixerNode.outputVolume = 0
                node = n
            }
            engine.prepare()
            try engine.start()
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func stopEngine() {
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
