import XCTest

/// End-to-end flows on the simulator: real touches, real storage, real lifecycle.
final class FlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launch(reset: Bool, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-resetProfile", "YES"] : []) + ["-uitestAimHint", "YES"] + extra
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SC_SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func tap(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(identifier: label).firstMatch
        if !button.waitForExistence(timeout: timeout) {
            shot("FAIL_missing_\(label)")
            print(app.debugDescription)
        }
        XCTAssertTrue(button.exists, "Missing button \(label)", file: file, line: line)
        let count = app.buttons.matching(identifier: label).count
        if count > 1 { print("DUPLICATE \(label)\n" + app.debugDescription) }
        button.tap()
    }

    private func exists(_ app: XCUIApplication, text: String, timeout: TimeInterval = 4) -> Bool {
        let found = app.staticTexts[text].waitForExistence(timeout: timeout)
        if !found && timeout >= 1 { shot("FAIL_text_" + String(text.prefix(20)).replacingOccurrences(of: "/", with: "-")) }
        return found
    }

    private func skipOnboarding(_ app: XCUIApplication) {
        XCTAssertTrue(exists(app, text: "Build a little higher", timeout: 8))
        tap(app, "Skip introduction")
        XCTAssertTrue(exists(app, text: "Your city starts here"))
    }

    /// Waits for the hanging floor to line up (DEBUG accessibility value), then drops.
    /// Uses non-failing snapshots and coordinate taps: the game screen may disappear at any moment.
    private func dropAligned(_ app: XCUIApplication, maxWait: TimeInterval = 12) {
        let drop = app.buttons["dropFloor"]
        guard drop.waitForExistence(timeout: 6) else { return }
        let deadline = Date().addingTimeInterval(maxWait)
        while Date() < deadline {
            guard let snap = try? drop.snapshot() else { return }
            if (snap.value as? String) == "aligned" { tapAt(app, snap.frame); return }
            usleep(15_000)
        }
        if let snap = try? drop.snapshot() { tapAt(app, snap.frame) }
    }

    private func tapAt(_ app: XCUIApplication, _ frame: CGRect) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    private func resultTitle(_ app: XCUIApplication) -> String? {
        for t in ["A new rooftop!", "The city keeps growing", "Almost there"] where app.staticTexts[t].exists { return t }
        return nil
    }

    // MARK: Tests

    func testFirstRunOnboardingPracticeAndLevelOne() {
        let app = launch(reset: true)
        XCTAssertTrue(exists(app, text: "Build a little higher", timeout: 8))
        shot("01_welcome")
        tap(app, "Next")
        XCTAssertTrue(exists(app, text: "Find the perfect moment"))
        tap(app, "Next")
        XCTAssertTrue(exists(app, text: "Make the city yours"))
        tap(app, "Let’s Build")

        // Hands-on practice: three safe drops and a brace.
        XCTAssertTrue(exists(app, text: "PRACTICE", timeout: 6))
        shot("08_practice")
        var sawBrace = false
        for _ in 0..<30 {
            if exists(app, text: "The plan", timeout: 0.1) { break }
            if let brace = try? app.buttons["Use Brace"].snapshot() {
                sawBrace = true
                shot("08_practice_brace")
                tapAt(app, brace.frame)
                usleep(300_000)
                if let drop = try? app.buttons["dropFloor"].snapshot() { tapAt(app, drop.frame) } // braced drop lands in place
                break
            }
            if app.buttons["dropFloor"].exists { dropAligned(app, maxWait: 10) }
            usleep(1_100_000)
        }
        XCTAssertTrue(sawBrace, "Practice must offer the brace")
        XCTAssertTrue(exists(app, text: "The plan", timeout: 8), "Practice ends on the Level 1 brief")
        XCTAssertTrue(exists(app, text: "Level 1"))
        shot("07_brief_level1")
        tap(app, "Start Building")

        var title: String?
        for _ in 0..<20 {
            dropAligned(app)
            usleep(1_300_000)
            if let t = resultTitle(app) { title = t; break }
            if app.staticTexts["Build to the rooftop beacon"].exists == false { sleep(1); title = resultTitle(app); if title != nil { break } }
        }
        if title == nil { sleep(2); title = resultTitle(app) }
        XCTAssertNotNil(title, "A run always ends on a result screen")
        shot("17_result_level1")
        if title != "Almost there" {
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Bolts'")).firstMatch.exists)
        }
    }

    func testPauseRestartHomeAndResumeAfterRelaunch() {
        var app = launch(reset: true)
        skipOnboarding(app)
        tap(app, "Build Level 1")
        tap(app, "Start Building")
        XCTAssertTrue(exists(app, text: "LEVEL 1", timeout: 6))
        dropAligned(app)
        sleep(1)
        tap(app, "Pause")
        XCTAssertTrue(exists(app, text: "Take a breather"))
        shot("15_paused")
        tap(app, "Restart")
        XCTAssertTrue(exists(app, text: "Start this tower again?"))
        shot("16_restart")
        tap(app, "Keep Building")
        XCTAssertTrue(exists(app, text: "Take a breather"))
        tap(app, "Resume")
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 2), "3-2-1 before the run continues")
        shot("40_countdown")
        sleep(4)
        dropAligned(app)
        sleep(1)
        tap(app, "Pause")
        tap(app, "Home")
        XCTAssertTrue(app.buttons["Resume · Level 1"].waitForExistence(timeout: 5), "Home offers Resume for the snapshot")
        shot("04_home_resume")

        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.buttons["Resume · Level 1"].waitForExistence(timeout: 8), "Snapshot survives relaunch")
        tap(app, "Resume · Level 1")
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 3), "Resume always counts down")
        sleep(4)
        XCTAssertTrue(app.buttons["dropFloor"].exists)
        XCTAssertTrue(app.staticTexts["LEVEL 1"].exists)
    }

    func testBackgroundPausesTheRun() {
        let app = launch(reset: true)
        skipOnboarding(app)
        tap(app, "Build Level 1")
        tap(app, "Start Building")
        XCTAssertTrue(exists(app, text: "LEVEL 1", timeout: 6))
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(exists(app, text: "Take a breather", timeout: 5), "Returning to foreground never continues by itself")
    }

    func testDailySupplyAndWorkshopLockedTheme() {
        let app = launch(reset: true)
        skipOnboarding(app)
        tap(app, "Daily Supply")
        XCTAssertTrue(exists(app, text: "One free delivery every 24 hours"))
        shot("21_daily_ready")
        tap(app, "Collect Supply")
        XCTAssertTrue(app.buttons["Skip Animation"].waitForExistence(timeout: 3))
        shot("22_daily_spinning")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 6))
        shot("23_daily_received")
        tap(app, "Workshop")
        XCTAssertTrue(exists(app, text: "Workshop"))
        shot("25_workshop")
        tap(app, "Sunshine Row")
        XCTAssertTrue(exists(app, text: "A few more Bolts"), "80 Bolts theme is locked after one delivery")
        shot("25b_locked")
        tap(app, "Back")
        tap(app, "Back")
        tap(app, "Daily Supply")
        XCTAssertTrue(app.buttons["Come Back Tomorrow"].waitForExistence(timeout: 4), "One claim per 24 hours")
        shot("24_daily_cooldown")
    }

    func testSettingsPersistAcrossLaunches() {
        var app = launch(reset: true)
        skipOnboarding(app)
        tap(app, "Settings")
        let music = app.buttons["Music"]
        XCTAssertTrue(music.waitForExistence(timeout: 4))
        XCTAssertEqual(music.value as? String, "On")
        music.tap()
        XCTAssertEqual(music.value as? String, "Off")
        shot("29_settings")
        app.terminate()
        app = launch(reset: false)
        tap(app, "Settings")
        XCTAssertEqual(app.buttons["Music"].value as? String, "Off")
        app.buttons["Music"].tap()
    }

    func testDamagedSaveOpensRecoveryAndRestoresBackup() {
        var app = launch(reset: true)
        skipOnboarding(app)
        tap(app, "Settings") // creates more than one save, so a backup exists
        app.buttons["Haptics"].tap()
        app.terminate()
        app = launch(reset: false, extra: ["-corruptProfile", "YES"])
        XCTAssertTrue(exists(app, text: "Let’s restore your skyline", timeout: 8))
        shot("36_recovery")
        tap(app, "Restore Backup")
        XCTAssertTrue(app.buttons["Daily Supply"].waitForExistence(timeout: 6), "Backup restored to Home")
    }

    func testResetProgressRequiresHold() {
        let app = launch(reset: true)
        skipOnboarding(app)
        tap(app, "Daily Supply")
        tap(app, "Collect Supply")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 6))
        tap(app, "Done")
        tap(app, "Settings")
        tap(app, "Progress & Data")
        tap(app, "Reset Progress")
        XCTAssertTrue(exists(app, text: "Clear your city?"))
        shot("33_reset")
        let hold = app.buttons["Hold to Clear"]
        hold.tap() // a short tap must not clear
        XCTAssertTrue(exists(app, text: "Clear your city?", timeout: 1))
        hold.press(forDuration: 1.8)
        XCTAssertTrue(exists(app, text: "Your city starts here", timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["0 Bolts"].exists, "Wallet cleared")
    }

    func testSeededProgressThemeWindLevelAndFreeBuild() {
        let app = launch(reset: true, extra: ["-seedProfile", "20"])
        XCTAssertTrue(app.buttons["Continue · Level 21"].waitForExistence(timeout: 8), "District 2 opens after Level 20")

        // Workshop: unlock and equip a theme with earned Bolts.
        tap(app, "Workshop")
        tap(app, "Sunshine Row")
        XCTAssertTrue(exists(app, text: "Unlock Sunshine Row?"))
        shot("25_unlock_confirm")
        tap(app, "Unlock · 80 Bolts")
        XCTAssertTrue(exists(app, text: "Equipped"))
        XCTAssertTrue(app.descendants(matching: .any)["220 Bolts"].waitForExistence(timeout: 3), "80 Bolts spent once")
        shot("25_workshop_equipped")
        tap(app, "Back")

        // Districts → Harbor Heights → windy Level 21.
        tap(app, "Districts")
        tap(app, "Harbor Heights")
        XCTAssertTrue(exists(app, text: "0 / 20 towers complete"))
        tap(app, "Build Level 21")
        XCTAssertTrue(exists(app, text: "Wind: Steady breeze"))
        tap(app, "Start Building")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Wind pushing'")).firstMatch.waitForExistence(timeout: 4))
        dropAligned(app)
        sleep(1)
        shot("11_wind_live")
        tap(app, "Pause")
        tap(app, "Home")

        // Free Build with an unfinished campaign tower asks before replacing it.
        tap(app, "Collection")
        tap(app, "Free Build")
        XCTAssertTrue(exists(app, text: "How high can you go?"))
        tap(app, "Start Run")
        XCTAssertTrue(exists(app, text: "Start a new tower?"))
        shot("free_replace_confirm")
        tap(app, "Start Free Build")
        XCTAssertTrue(exists(app, text: "FREE BUILD", timeout: 6))
        var finished = false
        for _ in 0..<40 {
            if let drop = try? app.buttons["dropFloor"].snapshot() { tapAt(app, drop.frame) }
            usleep(1_200_000)
            if app.staticTexts["New record!"].exists || app.staticTexts["Nice tower!"].exists { finished = true; break }
        }
        XCTAssertTrue(finished, "Free Build ends with its own result")
        shot("free_result")
    }
}
