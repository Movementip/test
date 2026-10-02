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
        let back = app.buttons["artist.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.isHittable)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(back.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(back.frame.maxX, window.maxX)
        screenshot("iPhone13-artist-wide-artwork")
        back.tap()
        XCTAssertTrue(app.buttons["Recommended artist"].waitForExistence(timeout: 5))
        app.buttons["Recommended artist"].tap()
        XCTAssertTrue(app.buttons["artist.back"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.buttons["Recommended artist"].waitForExistence(timeout: 5))
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
}
