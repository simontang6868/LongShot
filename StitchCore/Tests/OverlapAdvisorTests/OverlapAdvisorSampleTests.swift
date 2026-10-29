import CoreGraphics
import XCTest
@testable import StitchCore

/// 第 7 节 5 个样本的「智能推荐」快照测试。推荐值只作建议，断言容差 ±0.06。
final class OverlapAdvisorSampleTests: XCTestCase {

    func testSample1_WeChatChat() throws {
        let (prev, next) = TestImages.overlapPair(width: 200, height: 300, overlap: 0.18)
        let rec = try XCTUnwrap(OverlapAdvisor().recommend(previous: prev, next: next))
        XCTAssertLessThan(abs(rec.inferredOverlap - 0.18), 0.06)
    }

    func testSample2_RedNotePost() throws {
        let (prev, next) = TestImages.overlapPair(width: 200, height: 300, overlap: 0.15)
        let rec = try XCTUnwrap(OverlapAdvisor().recommend(previous: prev, next: next))
        XCTAssertLessThan(abs(rec.inferredOverlap - 0.15), 0.06)
    }

    func testSample3_SettingsPage() throws {
        let (prev, next) = TestImages.overlapPair(width: 200, height: 300, overlap: 0.20)
        let rec = try XCTUnwrap(OverlapAdvisor().recommend(previous: prev, next: next))
        XCTAssertLessThan(abs(rec.inferredOverlap - 0.20), 0.06)
    }

    func testSample4_AlbumMixedWidth() throws {
        // 相册混宽：prev 宽 200，next 宽 100，行均值与宽度无关，仍能推荐
        let prev = TestImages.content(width: 200, height: 300, freq: 0.2)
        let offset = Int((1 - 0.15) * 300)
        let next = TestImages.content(width: 100, height: 300, phase: Double(offset), freq: 0.2)
        let rec = try XCTUnwrap(OverlapAdvisor().recommend(previous: prev, next: next))
        XCTAssertLessThan(abs(rec.inferredOverlap - 0.15), 0.08)
    }

    func testSample5a_TooLittleOverlap() throws {
        // 只留 5% → 推荐值很低，UI 层据此提示「会跳段」
        let (prev, next) = TestImages.overlapPair(width: 200, height: 300, overlap: 0.05)
        let rec = try XCTUnwrap(OverlapAdvisor().recommend(previous: prev, next: next))
        XCTAssertLessThan(rec.inferredOverlap, 0.10)
    }

    func testSample5b_DuplicateDetected() {
        let a = TestImages.content(width: 200, height: 300, freq: 0.2)
        let b = TestImages.content(width: 200, height: 300, freq: 0.2) // 完全相同
        let sim = OverlapAdvisor().similarity(a, b)
        XCTAssertGreaterThan(sim, 0.95, "应判定为重复")
    }

    func testSample5c_AdvisorDisabledReturnsNil() {
        let (prev, next) = TestImages.overlapPair(width: 200, height: 300, overlap: 0.15)
        let advisor = OverlapAdvisor(enabled: false)
        XCTAssertNil(advisor.recommend(previous: prev, next: next), "关闭后应零扫描、直接返回 nil")
    }

    func testWidthRatioFlag() {
        let a = TestImages.solid(width: 100, height: 200, (1, 2, 3))
        let b = TestImages.solid(width: 220, height: 200, (4, 5, 6))
        let ratio = OverlapAdvisor().widthRatio(a, b)
        XCTAssertGreaterThan(ratio, 0.10, "宽度差 > 10% 应被标记")
    }
}
