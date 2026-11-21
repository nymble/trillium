// SPDX-License-Identifier: GPL-3.0-only
//
// Plain-language text for CoreMIDI OSStatus codes (MIDIServices.h). No
// CoreMIDI import, so it is tested on Linux too.

public enum MIDIStatusText {
    /// CoreMIDI error constant name for a status, or nil if not a CoreMIDI code.
    public static func name(_ status: Int32) -> String? {
        switch status {
        case -10830: return "kMIDIInvalidClient"
        case -10831: return "kMIDIInvalidPort"
        case -10832: return "kMIDIWrongEndpointType"
        case -10833: return "kMIDINoConnection"
        case -10834: return "kMIDIUnknownEndpoint"
        case -10835: return "kMIDIUnknownProperty"
        case -10836: return "kMIDIWrongPropertyType"
        case -10837: return "kMIDINoCurrentSetup"
        case -10838: return "kMIDIMessageSendErr"
        case -10839: return "kMIDIServerStartErr"
        case -10840: return "kMIDISetupFormatErr"
        case -10841: return "kMIDIWrongThread"
        case -10842: return "kMIDIObjectNotFound"
        case -10843: return "kMIDIIDNotUnique"
        case -10844: return "kMIDINotPermitted"
        case -10845: return "kMIDIUnknownError"
        default: return nil
        }
    }

    /// A short hint for codes a user can act on.
    public static func hint(_ status: Int32) -> String? {
        switch status {
        case -10844:
            return "The system did not allow this app to create a MIDI source. On iPhone and iPad this needs a build that declares the audio background mode; update the app."
        case -10839:
            return "The MIDI server did not start. Restart the app, or the device if it persists."
        default: return nil
        }
    }

    /// Text shown when a CoreMIDI call fails.
    public static func failure(call: String, status: Int32) -> String {
        var s = "CoreMIDI \(call) failed (OSStatus \(status)"
        if let n = name(status) { s += ", \(n)" }
        s += ")"
        if let h = hint(status) { s += ". " + h }
        return s
    }
}
