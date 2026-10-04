import XCTest

final class LaneNavigationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--lane-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["Recommended album"].waitForExistence(timeout: 20))
    }

    private func screenshot(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<7 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Element did not become tappable: \(element)")
    }

    func testEarnedBadgeSelectionFailureRemovalAndFreshClientRestore() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-community-fixture"]
        app.launch()
        app.buttons["Your badges"].tap()
        let choose = app.buttons["badge.select.legend"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["badge.current"].label, "Not selected")
        choose.tap()
        app.buttons["badge.save"].tap()
        XCTAssertTrue(app.staticTexts["badge.error"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["badge.current"].label, "Not selected", "Rejected writes must not look equipped")
        XCTAssertFalse(app.staticTexts["badge.saved"].exists)
        screenshot("iPhone13-badge-write-error")
        app.buttons["badge.save"].tap()
        XCTAssertTrue(app.staticTexts["badge.saved"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["badge.current"].label, "Legend")
        app.buttons["badge.none"].tap()
        app.buttons["badge.save"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Not selected"), object: app.staticTexts["badge.current"])], timeout: 10), .completed)
        choose.tap()
        app.buttons["badge.save"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Legend"), object: app.staticTexts["badge.current"])], timeout: 10), .completed)
        screenshot("iPhone13-server-badge-equipped")
        app.buttons["badge.back"].tap()
        app.buttons["Check badge on fresh client"].tap()
        XCTAssertTrue(app.staticTexts["Server badge restored on fresh client"].waitForExistence(timeout: 10))
        app.buttons["Public profile"].tap()
        let detail = app.buttons["badge.details.legend"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        scrollTo(detail); detail.tap()
        XCTAssertTrue(app.staticTexts["Date earned:"].waitForExistence(timeout: 5))
        screenshot("iPhone13-earned-badge-details")
        app.buttons["Close"].tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Edit profile"].tap()
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let initial = name.value as? String ?? ""
        name.tap(); name.typeText(" draft")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.swipeUp()
        let badgeEditor = app.buttons["profile.badges"]
        scrollTo(badgeEditor); badgeEditor.tap()
        XCTAssertTrue(app.buttons["badge.back"].waitForExistence(timeout: 10))
        app.buttons["badge.back"].tap()
        for _ in 0..<4 where !name.isHittable { app.swipeDown() }
        XCTAssertEqual(name.value as? String, initial + " draft", "Navigating to badges must retain unsaved profile edits")
    }

    func testMemorialRetryPaginationConfirmedCandleAndBack() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-community-fixture"]
        app.launch()
        app.buttons["Memorial artist"].tap()
        let memorial = app.buttons["artist.memorial"]
        XCTAssertTrue(memorial.waitForExistence(timeout: 10))
        scrollTo(memorial); memorial.tap()
        XCTAssertTrue(app.staticTexts["memorial.error"].waitForExistence(timeout: 10))
        let retry = app.buttons["memorial.retry"]
        scrollTo(retry); retry.tap()
        XCTAssertTrue(app.staticTexts["First memory"].waitForExistence(timeout: 10))
        let more = app.buttons["memorial.more"]
        scrollTo(more); more.tap()
        let pager = app.descendants(matching: .any).matching(identifier: "memorial.pager").firstMatch
        scrollTo(pager)
        let visible = pager.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 20, dy: 30)
        XCTAssertGreaterThan(visible.height, 100)
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.maxY))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.minY)))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2 / 2"), object: app.staticTexts["memorial.page"])], timeout: 10), .completed)
        let previousMemory = app.buttons["Previous memory"]
        scrollTo(previousMemory); previousMemory.tap()
        let nextMemory = app.buttons["Next memory"]
        scrollTo(nextMemory); nextMemory.tap()
        XCTAssertTrue(app.staticTexts["Second memory"].waitForExistence(timeout: 10))
        XCTAssertFalse(more.exists, "No page 3 after the final page")
        screenshot("iPhone13-memorial-pagination")
        let compose = app.buttons["memorial.compose"]
        XCTAssertTrue(compose.isHittable); compose.tap()
        let submit = app.buttons["memorial.submit"]
        XCTAssertFalse(submit.isEnabled, "An empty message must not be sent")
        let message = app.descendants(matching: .any).matching(identifier: "memorial.message").firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.tap(); message.typeText("Music stays with us")
        app.buttons["Done"].tap()
        submit.tap()
        XCTAssertTrue(app.staticTexts["memorial.error"].waitForExistence(timeout: 10))
        XCTAssertTrue(message.exists)
        XCTAssertEqual(message.value as? String, "Music stays with us", "Failure must retain the draft")
        XCTAssertFalse(app.staticTexts["memorial.confirmed"].exists)
        submit.tap()
        XCTAssertTrue(app.staticTexts["memorial.confirmed"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["memorial.count"].label, "3 candles")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "#3"), object: app.staticTexts["memorial.confirmationNumber"])], timeout: 5), .completed)
        XCTAssertTrue(app.images["memorial.candle.candle-own"].exists, "Original candle must render, not a blank spacer")
        screenshot("iPhone13-memorial-confirmed-candle")
        let author = app.buttons["memorial.author.candle-own"]
        scrollTo(author); author.tap()
        XCTAssertTrue(app.staticTexts["user.name"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["memorial.confirmed"].waitForExistence(timeout: 5))
        app.buttons["memorial.back"].tap()
        XCTAssertTrue(memorial.waitForExistence(timeout: 5))
        memorial.tap()
        XCTAssertTrue(app.staticTexts["Music stays with us"].waitForExistence(timeout: 10), "Server candle must remain after reopening")
        screenshot("iPhone13-memorial-server-restored")
        app.buttons["memorial.back"].tap()
        XCTAssertTrue(memorial.waitForExistence(timeout: 5))
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

    func testEqualizerProcessesRealAudioAndRestoresNeutralWithoutStopping() {
        app.terminate(); app.launchArguments = ["--lane-ui-test", "--lane-equalizer-fixture"]; app.launch()
        app.buttons["Run equalizer checks"].tap()
        XCTAssertTrue(app.staticTexts["Equalizer checks passed"].waitForExistence(timeout: 30), app.staticTexts["session.result"].label)
        app.buttons["Equalizer"].tap()
        XCTAssertTrue(app.switches["equalizer.enabled"].waitForExistence(timeout: 10))
        app.buttons["equalizer.preset.Bass Boost"].tap()
        XCTAssertTrue(app.buttons["equalizer.preset.Bass Boost"].isSelected)
        let curve = app.otherElements["equalizer.curve"]
        XCTAssertTrue(curve.exists)
        curve.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: curve.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.2)))
        XCTAssertTrue(app.buttons["equalizer.preset.Custom"].waitForExistence(timeout: 5))
        app.buttons["equalizer.fineAdjustment"].tap()
        XCTAssertTrue(app.sliders["equalizer.band.0"].waitForExistence(timeout: 5))
        screenshot("iPhone13-six-band-equalizer")
    }

    func testAdaptiveDownloadIsRestoredAndPlaysWithHTTPServerStopped() {
        app.terminate(); app.launchArguments = ["--lane-ui-test", "--lane-hls-fixture"]; app.launch()
        app.buttons["Run adaptive offline checks"].tap()
        let result = app.staticTexts["session.result"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "Adaptive offline checks"), object: result)], timeout: 60), .completed)
        XCTAssertEqual(result.label, "Adaptive offline checks passed")
        screenshot("iPhone13-adaptive-offline-server-stopped")
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
        for index in 0..<4 {
            app.buttons["Recommended album"].tap()
            let back = app.buttons["album.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            XCTAssertTrue(back.isHittable)
            XCTAssertTrue(app.staticTexts["Fixture track 1"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Fixture track 2"].exists)
            if index == 0 { screenshot("iPhone13-album-two-canonical-tracks") }
            back.tap()
            XCTAssertTrue(app.buttons["Recommended album"].waitForExistence(timeout: 5), "Album back failed on opening \(index + 1)")
        }
        app.buttons["Recommended album"].tap()
        XCTAssertTrue(app.buttons["album.back"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
        edge.press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)))
        XCTAssertTrue(app.buttons["Recommended album"].waitForExistence(timeout: 5))
    }

    func testSessionImportAndLikesAfterLocalStateRemoval() {
        app.buttons["Run session checks"].tap()
        XCTAssertTrue(app.staticTexts["Session checks passed"].waitForExistence(timeout: 45), app.staticTexts["session.result"].label)
        screenshot("iPhone13-session-import-and-likes")
    }

    func testImportSourceOrderFinishesAfterLeavingPreviewAndSurvivesFreshClient() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-import-fixture"]
        app.launch()
        app.buttons["Open import fixture"].tap()
        XCTAssertTrue(app.staticTexts["import.count"].waitForExistence(timeout: 10))
        app.swipeUp()
        let start = app.buttons["import.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        // A delayed membership read keeps the task before its final reorder.
        // Navigating away used to cancel it and leave all saved tracks reversed.
        let waiting = app.staticTexts["import.stage"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Confirming saved tracks on Lane…"), object: waiting)], timeout: 10), .completed)
        app.buttons["Leave import fixture"].tap()
        XCTAssertTrue(app.buttons["Check imported order"].waitForExistence(timeout: 5))
        app.buttons["Check imported order"].tap()
        XCTAssertTrue(app.staticTexts["Background import order passed"].waitForExistence(timeout: 20), app.staticTexts["session.result"].label)
        app.buttons["Open full app"].tap()
        app.buttons["Library"].firstMatch.tap()
        let liked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorite tracks")).firstMatch
        XCTAssertTrue(liked.waitForExistence(timeout: 15))
        liked.tap()
        let first = app.buttons["track.row.lane-4"]
        let last = app.buttons["track.row.lane-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(last.waitForExistence(timeout: 15))
        XCTAssertLessThan(first.frame.minY, last.frame.minY)
        screenshot("iPhone13-source-order-after-leaving-import")
    }

    func testImportOldestMenuOrderSurvivesReversedLibraryReadAndFreshClient() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-import-fixture"]
        app.launch()
        app.buttons["Open import fixture"].tap()
        XCTAssertTrue(app.staticTexts["import.count"].waitForExistence(timeout: 10))
        app.buttons["import.order"].tap()
        app.buttons["Oldest first"].tap()
        let start = app.buttons["import.start"]
        scrollTo(start); start.tap()
        let waiting = app.staticTexts["import.stage"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Confirming saved tracks on Lane…"), object: waiting)], timeout: 10), .completed)
        app.buttons["Leave import fixture"].tap()
        app.buttons["Check imported oldest order"].tap()
        XCTAssertTrue(app.staticTexts["Background import order passed"].waitForExistence(timeout: 20), app.staticTexts["session.result"].label)
        app.buttons["Open full app"].tap()
        app.buttons["Library"].firstMatch.tap()
        let liked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorite tracks")).firstMatch
        XCTAssertTrue(liked.waitForExistence(timeout: 15)); liked.tap()
        let first = app.buttons["track.row.lane-1"]
        let last = app.buttons["track.row.lane-4"]
        XCTAssertTrue(first.waitForExistence(timeout: 15)); XCTAssertTrue(last.waitForExistence(timeout: 15))
        XCTAssertLessThan(first.frame.minY, last.frame.minY)
        screenshot("iPhone13-oldest-order-after-stale-server-read")
    }

    func testImportOrderSurvivesIgnoredServerReorderAndRelaunchWithoutClaimingSync() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-import-fixture", "--lane-ignore-import-reorder-fixture"]
        app.launch()
        app.buttons["Open import fixture"].tap()
        XCTAssertTrue(app.staticTexts["import.count"].waitForExistence(timeout: 10))
        let start = app.buttons["import.start"]
        scrollTo(start); start.tap()
        let waiting = app.staticTexts["import.stage"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Confirming saved tracks on Lane…"), object: waiting)], timeout: 10), .completed)
        app.buttons["Leave import fixture"].tap()
        let checkOrder = app.buttons["Check unconfirmed order"]
        scrollTo(checkOrder); checkOrder.tap()
        XCTAssertTrue(app.staticTexts["Local order kept; server synchronization pending"].waitForExistence(timeout: 50), app.staticTexts["session.result"].label)
        app.terminate()
        app.launchArguments.append("--lane-preserve-import-order-fixture")
        app.launch()
        app.buttons["Open full app"].tap()
        app.buttons["Library"].firstMatch.tap()
        let liked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorite tracks")).firstMatch
        XCTAssertTrue(liked.waitForExistence(timeout: 15)); liked.tap()
        let first = app.buttons["track.row.lane-4"]
        let last = app.buttons["track.row.lane-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 15)); XCTAssertTrue(last.waitForExistence(timeout: 15))
        XCTAssertLessThan(first.frame.minY, last.frame.minY)
        app.buttons["playlist.actions"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this iPhone · server synchronization pending"].waitForExistence(timeout: 5))
        screenshot("iPhone13-local-source-order-after-ignored-server-reorder-and-relaunch")
    }

    func testYandexAccountLoginFindsDelayedFavoriteAnchorWithoutManualLink() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-yandex-account-fixture"]
        app.launch()
        app.buttons["Import music"].tap()
        let yandex = app.buttons["import.platform.yandex"]
        scrollTo(yandex); yandex.tap()
        app.buttons["import.kind.liked"].tap()
        let login = app.buttons["import.yandex.login"]
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count, 0, "Account import must not ask for a playlist link")
        login.tap()
        let continueButton = app.buttons["yandex.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        waitForYandexPageToFinish()
        let signIn = app.webViews.buttons["Sign in fixture"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertFalse(continueButton.isEnabled, "A foreign anchor/subframe must not identify the account playlist")
        tapWebElementAtItsFrameCenter(signIn)
        XCTAssertTrue(app.webViews.buttons["Signed in fixture"].waitForExistence(timeout: 5), "The actual page must receive the sign-in tap before testing discovery")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: continueButton)], timeout: 10), .completed)
        screenshot("iPhone13-yandex-account-automatic-favorite-discovery")
        app.buttons["yandex.close"].tap()
        XCTAssertTrue(login.waitForExistence(timeout: 5), "Yandex sign-in must always have a working exit")
        login.tap()
        waitForYandexPageToFinish()
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertFalse(continueButton.isEnabled, "A closed browser must not retain the previous account selection")
        tapWebElementAtItsFrameCenter(signIn)
        XCTAssertTrue(app.webViews.buttons["Signed in fixture"].waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: continueButton)], timeout: 10), .completed)
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["import.count"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Account favorites"].exists)
        XCTAssertFalse(app.buttons["yandex.close"].exists)
        screenshot("iPhone13-yandex-account-preview-without-manual-link")
    }

    private func waitForYandexPageToFinish() {
        let loading = app.descendants(matching: .any).matching(identifier: "yandex.loading").firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: loading)], timeout: 10), .completed)
    }

    private func tapWebElementAtItsFrameCenter(_ element: XCUIElement) {
        // On iOS 18.5 XCTest's remote WebKit hit-point occasionally targets
        // the heading instead of this button (recorded x57/y185 vs its actual
        // x56/y265/w175/h41). Use the current AX rectangle, not guessed pixels
        // or JS invocation; the page must still acknowledge a real touch.
        let window = app.windows.firstMatch
        let frame = element.frame
        XCTAssertFalse(frame.isEmpty)
        XCTAssertTrue(window.frame.contains(frame), "The web button must be fully on screen")
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: frame.midX - window.frame.minX, dy: frame.midY - window.frame.minY)).tap()
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

    func testDelayedAudioStartsAndAdvancesInBackgroundWithPreparedNextStream() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-background-fixture"]
        app.launch()
        app.buttons["Run background checks"].tap()
        XCTAssertTrue(app.staticTexts["Background check ready"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        // No foreground activation during the slow resolution, real WAV
        // buffering, end notification, or the following in-flight resolution.
        Thread.sleep(forTimeInterval: 40)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 2), "App terminated during background audio")
        Thread.sleep(forTimeInterval: 40)
        app.activate()
        XCTAssertTrue(app.staticTexts["Background checks passed"].waitForExistence(timeout: 10), app.staticTexts["session.result"].label)
        screenshot("iPhone13-background-real-audio-next")
    }

    func testAudioInterruptionPauseMediaResetAndHeadphoneRemoval() {
        app.terminate()
        app.launchArguments = ["--lane-ui-test", "--lane-background-fixture"]
        app.launch()
        app.buttons["Run audio lifecycle checks"].tap()
        XCTAssertTrue(app.staticTexts["Audio lifecycle checks passed"].waitForExistence(timeout: 50), app.staticTexts["session.result"].label)
        screenshot("iPhone13-audio-interruptions-reset")
    }

    func testFriendActivityRetryProfileAndPlayback() {
        app.terminate(); app.launchArguments = ["--lane-ui-test", "--lane-activity-fixture"]; app.launch()
        app.buttons["Friend activity"].tap()
        XCTAssertTrue(app.staticTexts["activity.error"].waitForExistence(timeout: 10))
        app.buttons["activity.retry"].tap()
        let profile = app.buttons["activity.profile.friend"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        XCTAssertTrue(app.staticTexts["user.name"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Listening now"].exists)
        app.buttons["activity.track.friend"].tap()
        screenshot("iPhone13-friend-activity")
    }

    func testPremiumPricingRetryAndConfirmedCancellation() {
        app.terminate(); app.launchArguments = ["--lane-ui-test", "--lane-activity-fixture"]; app.launch()
        app.buttons["Lane Premium"].tap()
        XCTAssertTrue(app.staticTexts["premium.error"].waitForExistence(timeout: 10))
        app.buttons["premium.retry"].tap()
        XCTAssertTrue(app.staticTexts["1 month"].waitForExistence(timeout: 10))
        let monthly = app.buttons["premium.plan.Monthly"]
        monthly.tap(); XCTAssertTrue(monthly.isSelected)
        let checkout = app.buttons["premium.checkout"]
        scrollTo(checkout); checkout.tap()
        XCTAssertTrue(app.buttons["premium.confirmCheckout"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["premium.confirmCheckout"].exists)
        checkout.tap(); app.buttons["premium.confirmCheckout"].tap()
        XCTAssertTrue(app.staticTexts["premium.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["premium.error"].label.contains("Automated tests do not open payment pages"))
        let cancel = app.buttons["premium.cancel"]
        scrollTo(cancel); cancel.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(cancel.exists, "Dismissing confirmation must not cancel the subscription")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: cancel)], timeout: 10), .completed)
        cancel.tap()
        let action = app.buttons["premium.confirmCancellation"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: action)], timeout: 10), .completed)
        action.tap()
        XCTAssertTrue(app.staticTexts["premium.cancelled"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["premium.renewal"].label, "Auto-renewal is off")
        XCTAssertFalse(cancel.exists)
        screenshot("iPhone13-premium-server-confirmed-cancellation")
    }

    func testImageCropCancelAndConfirmedJPEGUploadAndAnimatedGIF() {
        app.terminate(); app.launchArguments = ["--lane-ui-test", "--lane-image-fixture"]; app.launch()
        app.buttons["Run GIF checks"].tap()
        XCTAssertTrue(app.staticTexts["GIF checks passed"].waitForExistence(timeout: 40), app.staticTexts["session.result"].label)
        app.buttons["Edit profile"].tap()
        app.buttons["Crop fixture avatar"].tap()
        XCTAssertTrue(app.buttons["crop.cancel"].waitForExistence(timeout: 5))
        app.buttons["crop.cancel"].tap()
        XCTAssertFalse(app.staticTexts["https://lane-ui.test/cropped-avatar.jpg"].exists)
        app.buttons["Crop fixture avatar"].tap()
        XCTAssertTrue(app.buttons["crop.save"].waitForExistence(timeout: 5))
        screenshot("iPhone13-image-cropper")
        app.buttons["crop.save"].tap()
        XCTAssertTrue(app.staticTexts["https://lane-ui.test/cropped-avatar.jpg"].waitForExistence(timeout: 10))
        screenshot("iPhone13-cropped-image-uploaded")
    }

    func testCommentAndReplyAuthorsOpenProfilesAndReturn() {
        app.buttons["Track comments"].tap()
        let author = app.buttons["comment.author.comment-1"]
        XCTAssertTrue(author.waitForExistence(timeout: 10))
        author.tap()
        XCTAssertTrue(app.staticTexts["Friend profile"].firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        app.buttons["Show 1 replies"].tap()
        let reply = app.buttons["comment.author.reply-1"]
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        reply.tap()
        XCTAssertTrue(app.staticTexts["Second friend"].firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        app.buttons["comment.target.reply-1"].tap()
        XCTAssertTrue(app.staticTexts["Friend profile"].firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.buttons["comment.author.anonymous"].exists)
        XCTAssertTrue(app.staticTexts["Deleted user"].exists)
        screenshot("iPhone13-comment-reply-profile-links")
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
        for identifier in ["library.favorite.title", "library.favorite.count"] {
            let text = app.staticTexts[identifier]
            XCTAssertTrue(text.waitForExistence(timeout: 5), "Favorite title/count must remain independently accessible")
            XCTAssertGreaterThanOrEqual(text.frame.minX, window.minX + 16, "Favorite text is cropped at the left edge")
            XCTAssertLessThanOrEqual(text.frame.maxX, window.maxX - 16, "Favorite text exceeds the card width")
        }
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
