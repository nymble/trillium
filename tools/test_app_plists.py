#!/usr/bin/env python3
# Copyright (C) 2026 Paul Lambert
# SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial
"""App Info.plist requirements that CoreMIDI and App Store Connect rely on."""

import os
import plistlib
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return plistlib.load(f)


class AppPlistTests(unittest.TestCase):
    def test_ios_declares_audio_background_mode_for_the_virtual_midi_source(self):
        # iOS refuses MIDISourceCreate* with kMIDINotPermitted (-10844) unless
        # UIBackgroundModes contains "audio". The instrument view's
        # "Trillium Instrument" source depends on it.
        self.assertIn("audio", load("apple/App/iOS/Info.plist").get("UIBackgroundModes", []))

    def test_both_apps_declare_no_non_exempt_encryption(self):
        for p in ("apple/App/iOS/Info.plist", "apple/App/macOS/Info.plist"):
            self.assertIs(load(p).get("ITSAppUsesNonExemptEncryption"), False, p)


if __name__ == "__main__":
    unittest.main()
