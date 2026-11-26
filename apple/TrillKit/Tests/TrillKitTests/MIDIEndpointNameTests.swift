// Copyright (C) 2026 Paul Lambert
// SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial

#if canImport(CoreMIDI)
import XCTest
@testable import TrillKit

/// The firmware's USB product name changed from "Trill XIAO MIDI (dev)" to
/// "Trillium". The app finds the board by looking for "Trill" in the device
/// name, so old and new firmware must both be found.
final class MIDIEndpointNameTests: XCTestCase {
    private func endpoint(device: String?, name: String) -> MIDIEndpointInfo {
        MIDIEndpointInfo(id: 1, name: name, deviceName: device, portIndex: 0, isOffline: false)
    }

    func testOldAndNewProductNamesAreRecognisedAsTheBoard() {
        for device in ["Trillium", "Trill XIAO MIDI (dev)", "Trill XIAO MIDI+PCM (dev)"] {
            XCTAssertTrue(endpoint(device: device, name: "\(device) Port 1").isTrill, device)
        }
    }

    func testOtherDevicesAreNotRecognised() {
        XCTAssertFalse(endpoint(device: "IAC Driver", name: "Bus 1").isTrill)
        XCTAssertFalse(endpoint(device: nil, name: "Logic Pro Virtual In").isTrill)
    }
}
#endif
