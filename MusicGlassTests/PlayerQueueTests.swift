import XCTest
@testable import MusicGlass

final class PlayerQueueTests: XCTestCase {
    func testQueueAdvancesAndRepeatsAll() {
        let one = Track(id: "1", videoId: "1", title: "One")
        let two = Track(id: "2", videoId: "2", title: "Two")
        var queue = PlayerQueue()
        queue.replace(with: [one, two], startingAt: one)

        XCTAssertEqual(queue.nextTrack(), two)
        XCTAssertNil(queue.nextTrack())

        queue.repeatMode = .all
        XCTAssertEqual(queue.nextTrack(), one)
    }

    func testRepeatOneReturnsCurrentTrack() {
        let one = Track(id: "1", videoId: "1", title: "One")
        let two = Track(id: "2", videoId: "2", title: "Two")
        var queue = PlayerQueue()
        queue.replace(with: [one, two], startingAt: one)
        queue.repeatMode = .one

        XCTAssertEqual(queue.nextTrack(), one)
        XCTAssertEqual(queue.currentTrack, one)
    }
}
