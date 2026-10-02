import XCTest

final class LaneNavigationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--lane-ui-test"]
        app.launch()
    }

    private func screenshot(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    func testRecommendedArtistHasBackAndStaysWithinIPhone13Width() {
        app.buttons["Recommended artist"].tap()
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.isHittable)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(back.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(back.frame.maxX, window.maxX)
        let title = app.staticTexts["Автостопом по фазе сна"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(title.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(title.frame.maxX, window.maxX)
        let albumRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "bastards")).firstMatch
        XCTAssertTrue(albumRow.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(albumRow.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(albumRow.frame.maxX, window.maxX)
        screenshot("iPhone13-artist-wide-artwork")
        back.tap()
        XCTAssertTrue(app.buttons["Recommended artist"].waitForExistence(timeout: 5))
    }

    func testRecommendedArtistCanSwipeBackAfterReopening() {
        app.buttons["Recommended artist"].tap()
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(app.buttons["Recommended artist"].waitForExistence(timeout: 5))
        app.buttons["Recommended artist"].tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        print("Swipe geometry: application=\(app.frame), window=\(window.frame)")
        XCTAssertGreaterThan(window.frame.width, 300)
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        screenshot("iPhone13-native-swipe-back")
        XCTAssertTrue(app.buttons["Recommended artist"].waitForExistence(timeout: 5), app.staticTexts["gesture.report"].label)
    }

    func testPlayerArtistCanCloseBackToPlayer() {
        app.buttons["Open player"].tap()
        let artist = app.buttons["player.artist"]
        XCTAssertTrue(artist.waitForExistence(timeout: 10))
        artist.tap()
        let back = app.buttons["artist.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.isHittable)
        screenshot("iPhone13-player-artist-card")
        back.tap()
        XCTAssertTrue(artist.waitForExistence(timeout: 5))
    }

    func testAlbumKeepsCanonicalTracksAndBackButton() {
        app.buttons["Recommended album"].tap()
        XCTAssertTrue(app.buttons["album.back"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fixture track 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fixture track 2"].exists)
        screenshot("iPhone13-album-two-canonical-tracks")
        app.buttons["album.back"].tap()
        XCTAssertTrue(app.buttons["Recommended album"].waitForExistence(timeout: 5))
    }

    func testSessionImportAndLikesAfterLocalStateRemoval() {
        app.buttons["Run session checks"].tap()
        XCTAssertTrue(app.staticTexts["Session checks passed"].waitForExistence(timeout: 30), app.staticTexts["session.result"].label)
        screenshot("iPhone13-session-import-and-likes")
    }

    func testPrivacySettingsPersistOnServerAndReload() {
        app.buttons["Privacy settings"].tap()
        let toggle = app.switches["privacy.playlists"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(waitEnabled(toggle))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        app.buttons["privacy.save"].tap()
        XCTAssertTrue(app.staticTexts["Privacy settings saved to Lane"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Privacy settings"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: toggle)], timeout: 10), .completed,
                       "Reopened settings must finish reloading the server value, not retain a default or an old accessibility snapshot")
        XCTAssertEqual(toggle.value as? String, "0")
        screenshot("iPhone13-server-privacy-settings")
    }

    func testNotificationInvitationCanRetryAndReadAll() {
        app.buttons["Notification center"].tap()
        let invitation = app.buttons["notification.fixture-invite"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 10))
        app.buttons["Read all"].tap()
        let read = app.buttons["Read all"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: read)], timeout: 5), .completed)
        app.buttons["invitation.accept.fixture-invite"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "503")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(invitation.exists, "A failed write must not remove the invitation")
        app.buttons["invitation.accept.fixture-invite"].tap()
        XCTAssertTrue(app.staticTexts["No notifications"].waitForExistence(timeout: 10))
        screenshot("iPhone13-notification-invitation-retry")
    }

    func testProgressiveHTTPAudioAndOfflineDownloadAfterRelaunch() {
        app.buttons["Run playback checks"].tap()
        XCTAssertTrue(app.staticTexts["Playback checks passed"].waitForExistence(timeout: 45), app.staticTexts["session.result"].label)
        screenshot("iPhone13-streaming-and-offline-download")
    }

    private func waitEnabled(_ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)], timeout: 10) == .completed
    }

    func testRangeBridgeStartsBeforeWholeFileAndOfflinePlayback() {
        app.buttons["Run range transport checks"].tap()
        XCTAssertTrue(app.staticTexts["Range transport checks passed"].waitForExistence(timeout: 45), app.staticTexts["session.result"].label)
        screenshot("iPhone13-range-bridge-and-offline-download")
    }

    func testServerEffectsRetryPreservesPositionAndPausedState() {
        app.buttons["Run effects checks"].tap()
        XCTAssertTrue(app.staticTexts["Effects checks passed"].waitForExistence(timeout: 65), app.staticTexts["session.result"].label)
        app.buttons["Open player"].tap()
        XCTAssertTrue(app.buttons["player.effects"].waitForExistence(timeout: 10))
        app.buttons["player.effects"].tap()
        XCTAssertTrue(app.buttons["effect.original"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["effect.speedup"].exists)
        XCTAssertTrue(app.buttons["effect.slowed_reverb"].exists)
        screenshot("iPhone13-effects-original-speedup-slowed")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["player.artist"].waitForExistence(timeout: 5))
    }

    func testRealLibraryCountsTabReselectionAndBottomSafeArea() {
        app.buttons["Open full app"].tap()
        let library = app.buttons["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        let playlist = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture playlist")).firstMatch
        XCTAssertTrue(playlist.waitForExistence(timeout: 15))
        XCTAssertTrue(playlist.label.contains("2 tracks"), playlist.label)
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(window.maxY - library.frame.maxY, 35, "Only the home-indicator safe area belongs below the tab buttons")
        playlist.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        library.tap()
        XCTAssertTrue(playlist.waitForExistence(timeout: 10), "Reselecting Library must pop to its root")
        screenshot("iPhone13-library-counts-tab-reset-safe-area")
    }

    func testProfileFailureKeepsEditorAndSuccessfulWriteReloads() {
        app.buttons["Edit profile"].tap()
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Updated Lane")
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "503")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(name.exists, "A failed save must keep the editor open")
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.buttons["Edit profile"].waitForExistence(timeout: 10))
        app.buttons["Edit profile"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.value as? String, "Updated Lane")
        screenshot("iPhone13-profile-save-retry")
    }
}
