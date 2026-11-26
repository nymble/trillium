// Copyright (C) 2026 Paul Lambert
// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial

import XCTest
@testable import TrillKit

final class MIDIStatusTextTests: XCTestCase {
    func testNotPermittedIsNamedWithAHint() {
        let s = MIDIStatusText.failure(call: "MIDISourceCreateWithProtocol", status: -10844)
        XCTAssertTrue(s.hasPrefix("CoreMIDI MIDISourceCreateWithProtocol failed (OSStatus -10844, kMIDINotPermitted)"))
        XCTAssertTrue(s.contains("audio background mode"))
    }

    func testEveryCoreMIDICodeHasAName() {
        for code in Int32(-10845)...Int32(-10830) {
            XCTAssertNotNil(MIDIStatusText.name(code), "\(code)")
        }
        XCTAssertNil(MIDIStatusText.name(0))
        XCTAssertNil(MIDIStatusText.name(-50))
    }

    func testUnknownStatusKeepsTheNumberOnly() {
        XCTAssertEqual(MIDIStatusText.failure(call: "MIDIClientCreateWithBlock", status: -50),
                       "CoreMIDI MIDIClientCreateWithBlock failed (OSStatus -50)")
    }
}
