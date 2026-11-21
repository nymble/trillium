// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import TrillKit

final class BackgroundKeepAliveTests: XCTestCase {
    private final class Fake {
        var startOK = true
        var starts = 0
        var stops = 0
        lazy var controller = KeepAliveController(start: { [unowned self] in self.starts += 1; return self.startOK },
                                                  stop: { [unowned self] in self.stops += 1 })
    }

    func testStartsOnceAndStopsWhenNoLongerWanted() {
        let f = Fake()
        f.controller.handle(.want(true))
        f.controller.handle(.want(true))
        XCTAssertEqual(f.starts, 1)
        XCTAssertTrue(f.controller.running)
        f.controller.handle(.want(false))
        XCTAssertEqual(f.stops, 1)
        XCTAssertFalse(f.controller.running)
        f.controller.handle(.want(false))
        XCTAssertEqual(f.stops, 1)
    }

    func testRestartsAfterAnInterruptionOnlyWhenWanted() {
        let f = Fake()
        f.controller.handle(.want(true))
        f.controller.handle(.interruptionBegan)
        XCTAssertFalse(f.controller.running)
        f.controller.handle(.interruptionEnded)
        XCTAssertTrue(f.controller.running)
        XCTAssertEqual(f.starts, 2)
        XCTAssertEqual(f.stops, 0, "the system already stopped audio")

        f.controller.handle(.want(false))
        f.controller.handle(.interruptionEnded)
        XCTAssertFalse(f.controller.running)
        XCTAssertEqual(f.starts, 2)
    }

    func testMediaServicesResetRebuildsARunningEngine() {
        let f = Fake()
        f.controller.handle(.want(true))
        f.controller.handle(.mediaServicesReset)
        XCTAssertEqual(f.stops, 1)
        XCTAssertEqual(f.starts, 2)
        XCTAssertTrue(f.controller.running)
    }

    func testFailedStartIsRetriedOnTheNextRequest() {
        let f = Fake()
        f.startOK = false
        f.controller.handle(.want(true))
        XCTAssertFalse(f.controller.running)
        f.startOK = true
        f.controller.handle(.want(true))
        XCTAssertTrue(f.controller.running)
        XCTAssertEqual(f.starts, 2)
    }

    func testAppMIDIPreferenceIsKeptAcrossLaunches() {
        let suite = "BackgroundKeepAliveTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertFalse(AppMIDIPreference(defaults: d).isOn)
        AppMIDIPreference(defaults: d).isOn = true
        XCTAssertTrue(AppMIDIPreference(defaults: d).isOn)
        AppMIDIPreference(defaults: d).isOn = false
        XCTAssertFalse(AppMIDIPreference(defaults: d).isOn)
    }
}
