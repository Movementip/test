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
        let likes = app.buttons["player.likes"]
        let comments = app.buttons["player.comments"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Likes 27"), object: likes)], timeout: 10), .completed)
        XCTAssertEqual(comments.label, "Comments 4", "Counters must load without tapping either action")
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
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.isHittable)
        XCTAssertTrue(app.staticTexts["Fixture track 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fixture track 2"].exists)
        screenshot("iPhone13-album-two-canonical-tracks")
        back.tap()
        XCTAssertTrue(app.buttons["Recommended album"].waitForExistence(timeout: 5))
        app.buttons["Recommended album"].tap()
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(app.buttons["Recommended album"].waitForExistence(timeout: 5), "Native album return must still work after reopening")
    }

    func testSessionImportAndLikesAfterLocalStateRemoval() {
        app.buttons["Run session checks"].tap()
        XCTAssertTrue(app.staticTexts["Session checks passed"].waitForExistence(timeout: 45), app.staticTexts["session.result"].label)
        screenshot("iPhone13-session-import-and-likes")
    }

    func testLikedRowReplacesAnotherPlaylistQueueForNextAndPrevious() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-queue-fixture"]
        app.launch()
        app.buttons["Open full app"].tap()
        let library = app.buttons["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        let liked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorite tracks")).firstMatch
        XCTAssertTrue(liked.waitForExistence(timeout: 15))
        liked.tap()
        let row = app.buttons["track.row.lane-3"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap() // Normal tap, not the previously working swipe Play action.
        app.buttons["player.mini.open"].tap()
        XCTAssertTrue(app.staticTexts["Fixture track 3"].waitForExistence(timeout: 10))
        app.buttons["player.next"].tap()
        XCTAssertTrue(app.staticTexts["Fixture track 4"].waitForExistence(timeout: 15), "Next must stay in liked tracks, not return to lane-2")
        app.buttons["player.previous"].tap()
        XCTAssertTrue(app.staticTexts["Fixture track 3"].waitForExistence(timeout: 15))
        screenshot("iPhone13-liked-tracks-replace-old-playback-queue")
    }

    func testRateLimitedClearWaitsFullMinuteAndContinuesAutomatically() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-rate-fixture"]
        app.launch()
        app.buttons["Open full app"].tap()
        let library = app.buttons["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        let liked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorite tracks")).firstMatch
        XCTAssertTrue(liked.waitForExistence(timeout: 15))
        liked.tap()
        let actions = app.buttons["playlist.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Liked playlist controls before clear"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        screenshot("iPhone13-liked-menu-before-clear")
        XCTAssertTrue(actions.isHittable, "Liked playlist menu must not be hidden under the status bar")
        actions.tap()
        app.buttons["playlist.clear"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        let start = Date()
        app.alerts.buttons["Удалить все треки"].tap()
        let waiting = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Лимит сервера")).firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 10), "429 should be a countdown, not a fatal error")
        XCTAssertTrue(app.buttons["playlist.clear.stop"].exists)
        screenshot("iPhone13-clear-minute-cooldown")
        XCTAssertTrue(app.staticTexts["Favorite Tracks"].firstMatch.waitForExistence(timeout: 90), "Deletion should continue automatically once the minute expires")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 60)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "HTTP 429")).firstMatch.exists)
        screenshot("iPhone13-clear-after-minute-cooldown")
    }

    func testPrivacySettingsPersistOnServerAndReload() {
        app.buttons["Privacy settings"].tap()
        let toggle = app.switches["privacy.playlists"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(waitEnabled(toggle))
        XCTAssertEqual(toggle.value as? String, "1")
        // SwiftUI Form exposes the entire 358-point row as a Switch. A tap at
        // its center hits the label, not UISwitch's control at the trailing edge.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: toggle)], timeout: 5), .completed,
                       "The actual control must turn off before submitting the request")
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

    func testStream500RecoversForNextSongSameSongAndCancelledOldRequest() {
        app.buttons["Run recovery checks"].tap()
        XCTAssertTrue(app.staticTexts["Recovery checks passed"].waitForExistence(timeout: 50), app.staticTexts["session.result"].label)
        screenshot("iPhone13-stream-500-next-retry-and-cancellation")
    }

    func testClearPlaylistRequiresConfirmationAndPersistsWithoutDeletingPlaylist() {
        app.buttons["Open full app"].tap()
        let library = app.buttons["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        let playlist = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture playlist")).firstMatch
        XCTAssertTrue(playlist.waitForExistence(timeout: 15))
        playlist.tap()
        let actions = app.buttons["playlist.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.tap()
        let clear = app.buttons["playlist.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Fixture track 1"].firstMatch.exists, "Cancelling must not remove tracks")
        actions.tap(); clear.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Удалить все треки"].tap()
        XCTAssertTrue(app.staticTexts["0 tracks"].firstMatch.waitForExistence(timeout: 15))
        library.tap()
        XCTAssertTrue(playlist.waitForExistence(timeout: 10))
        XCTAssertTrue(playlist.label.contains("0 tracks"), "The playlist must remain, now empty")
        playlist.tap()
        XCTAssertTrue(app.staticTexts["0 tracks"].firstMatch.waitForExistence(timeout: 10), "Reopening must not resurrect cached tracks")
        screenshot("iPhone13-confirmed-server-playlist-clear")
    }

    func testIncomingShareCanRetryOpenAlbumAndCloseBackToApp() {
        app.buttons["Open shared album"].tap()
        let retry = app.buttons["share.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["share.close"].isHittable, "A failed link must still be closable")
        retry.tap()
        XCTAssertTrue(app.staticTexts["Friend profile shared a album"].waitForExistence(timeout: 10))
        app.buttons["share.open"].tap()
        XCTAssertTrue(app.staticTexts["Fixture track 1"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["share.close"].waitForExistence(timeout: 5))
        screenshot("iPhone13-incoming-share-retry-album-return")
        app.buttons["share.close"].tap()
        XCTAssertTrue(app.buttons["Open shared album"].waitForExistence(timeout: 5))
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

    func testUserProfileFollowRetryAndPaginatedFollowersCanNavigateBack() {
        app.buttons["Public profile"].tap()
        XCTAssertTrue(app.staticTexts["Friend profile"].waitForExistence(timeout: 10))
        let follow = app.buttons["user.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 10))
        XCTAssertEqual(follow.label, "Follow")
        follow.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "503")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(follow.label, "Follow", "A rejected follow must not look saved")
        follow.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Following"), object: follow)], timeout: 10), .completed)
        app.buttons["user.followers"].tap()
        XCTAssertTrue(app.buttons["people.friend"].waitForExistence(timeout: 10))
        app.buttons["Load more"].tap()
        XCTAssertTrue(app.buttons["people.second"].waitForExistence(timeout: 10))
        app.buttons["people.second"].tap()
        XCTAssertTrue(app.staticTexts["Second friend"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["user.followers"].exists, "A private follower list must not be exposed")
        XCTAssertFalse(app.buttons["user.following"].exists, "A private following list must not be exposed")
        XCTAssertFalse(app.staticTexts["Public playlists"].exists, "Hidden playlists must not be rendered")
        screenshot("iPhone13-user-profile-paginated-followers")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["people.second"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["user.follow"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Public profile"].waitForExistence(timeout: 5))
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
