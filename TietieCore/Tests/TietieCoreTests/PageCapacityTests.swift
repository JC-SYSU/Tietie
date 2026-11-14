import XCTest
@testable import TietieCore

final class PageCapacityTests: XCTestCase {
    // 标准档位: 卡片 184、间距 12、内边距 20。
    private func count(_ width: CGFloat, card: CGFloat = 184, gap: CGFloat = 12,
                       pad: CGFloat = 20, divider: CGFloat = 0) -> Int {
        PageCapacity.count(viewportWidth: width, cardWidth: card, gap: gap,
                           padding: pad, dividerReserve: divider)
    }

    func testFitsExactCount() {
        // 2*20 内边距之后可用 6*184 + 5*12 = 1164 → 宽 1204。
        XCTAssertEqual(count(1204), 6)
    }

    func testOnePointLessDropsACard() {
        XCTAssertEqual(count(1203), 5)
    }

    func testDividerReserveCostsACard() {
        XCTAssertEqual(count(1204, divider: 5.5 + 12), 5)
    }

    func testNarrowWidthStillOneCard() {
        XCTAssertEqual(count(100), 1)
        XCTAssertEqual(count(0), 1)
        XCTAssertEqual(count(-50), 1)
    }

    func testCompactMetrics() {
        // 紧凑档位: 卡片 132、间距 8、内边距 14。可用 3*132 + 2*8 = 412 → 宽 440。
        XCTAssertEqual(count(440, card: 132, gap: 8, pad: 14), 3)
    }

    func testPageCountAndMaxIndex() {
        XCTAssertEqual(PageCapacity.pageCount(itemCount: 0, capacity: 6), 1)
        XCTAssertEqual(PageCapacity.pageCount(itemCount: 6, capacity: 6), 1)
        XCTAssertEqual(PageCapacity.pageCount(itemCount: 7, capacity: 6), 2)
        XCTAssertEqual(PageCapacity.pageCount(itemCount: 13, capacity: 6), 3)
        XCTAssertEqual(PageCapacity.maxPageIndex(itemCount: 13, capacity: 6), 2)
        XCTAssertEqual(PageCapacity.maxPageIndex(itemCount: 5, capacity: 6), 0)
    }

    func testPageCountToleratesZeroCapacity() {
        XCTAssertEqual(PageCapacity.pageCount(itemCount: 5, capacity: 0), 5)
    }
}
