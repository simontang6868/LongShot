import CoreGraphics
import XCTest
@testable import StitchCore

final class CropSeamTests: XCTestCase {

    // MARK: - CropParams

    func testClamp() {
        XCTAssertEqual(CropParams.clamp(ratio: -0.1), 0.0)
        XCTAssertEqual(CropParams.clamp(ratio: 0.5), 0.40)
        XCTAssertEqual(CropParams.clamp(ratio: 0.15), 0.15)
    }

    func testDefault() {
        let d = CropParams.default
        XCTAssertEqual(d.topCropRatio, 0.15)
        XCTAssertEqual(d.bottomCropRatio, 0.15)
    }

    func testFirstLastSingleSideCrop() {
        let p = CropParams.default
        let first = p.spec(forIndex: 0, count: 5)
        XCTAssertEqual(first.cropTop, 0)          // 首张留顶
        XCTAssertEqual(first.cropBottom, 0.15)

        let last = p.spec(forIndex: 4, count: 5)
        XCTAssertEqual(last.cropTop, 0.15)
        XCTAssertEqual(last.cropBottom, 0)        // 末张留底

        let mid = p.spec(forIndex: 2, count: 5)
        XCTAssertEqual(mid.cropTop, 0.15)
        XCTAssertEqual(mid.cropBottom, 0.15)
    }

    func testRetainedRect() {
        let spec = CropSpec(cropTop: 0.1, cropBottom: 0.2)
        let r = spec.retainedRect(forSize: CGSize(width: 100, height: 1000))
        XCTAssertEqual(Int(r.origin.y), 100)
        XCTAssertEqual(Int(r.height), 700) // 1000 - 100 - 200
    }

    func testValidatedAdjustsWhenTooMuch() {
        // 高度 120，裁 0.4+0.4=0.8 → 剩余 24 < 100 → 应收缩
        let p = CropParams(topCropRatio: 0.4, bottomCropRatio: 0.4)
        let (adj, changed) = p.validated(forImageHeight: 120)
        XCTAssertTrue(changed)
        let remaining = 120 * (1 - adj.topCropRatio - adj.bottomCropRatio)
        XCTAssertGreaterThanOrEqual(remaining, 100 - 1) // 约等
    }

    // MARK: - SeamRenderer

    func testFeatherProducesSameSize() {
        let img = TestImages.solid(width: 120, height: 300, (200, 100, 50))
        let f = SeamRenderer().featheredTop(img, featherHeight: 25)
        XCTAssertEqual(f.width, 120)
        XCTAssertEqual(f.height, 300)
    }

    func testStatusBarCropDetectsSolidTop() {
        // 顶部 40 行纯白，下面正弦内容
        let img = TestImages.make(width: 200, height: 400) { ctx, w, h in
            ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1, 1, 1, 1])!)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: 40))
            for y in 40..<h {
                let v = 0.5 + 0.5 * sin(Double(y) * 0.2)
                let c = UInt8(v * 255)
                ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [CGFloat(c)/255, CGFloat(c)/255, CGFloat(c)/255, 1])!)
                ctx.fill(CGRect(x: 0, y: y, width: w, height: 1))
            }
        }
        let insets = SeamRenderer().statusBarCropInsets(for: img)
        XCTAssertGreaterThan(insets.top, 0, "应检测到顶部纯色带")
    }

    func testStatusBarCropNoFalsePositiveOnNoisy() {
        let img = TestImages.content(width: 200, height: 400, freq: 0.8)
        let insets = SeamRenderer().statusBarCropInsets(for: img)
        XCTAssertEqual(insets.top, 0, "纯正弦无明显纯色带，不应误裁")
    }

    // MARK: - B 组：检测层单元测试（默认 15% 场景下的「检测裁掉量」边界）

    /// B-2：带高 50px 的纯色顶带 → 状态栏检测上报的裁掉量必 ∈ (0, 50]，且 ≤ 上限。
    ///      （这是「检测裁掉量 ∈ [0, 状态栏带高度]」在检测层的直接证明，未关检测。）
    func testB_statusBarDetection_reportsCropWithinBandHeight() {
        let bandHeight = 50
        let img = TestImages.make(width: 200, height: 400) { ctx, w, h in
            ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1, 1, 1, 1])!)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: bandHeight))
            for y in bandHeight..<h {
                let v = 0.5 + 0.5 * sin(Double(y) * 0.8)
                let c = UInt8(max(0, min(1, v)) * 255)
                ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                         components: [CGFloat(c)/255, CGFloat(c)/255, CGFloat(c)/255, 1])!)
                ctx.fill(CGRect(x: 0, y: y, width: w, height: 1))
            }
        }
        let insets = SeamRenderer().statusBarCropInsets(for: img)
        XCTAssertGreaterThan(insets.top, 0, "应检测到顶部纯色带")
        XCTAssertLessThanOrEqual(insets.top, CGFloat(bandHeight), "检测裁掉量 ≤ 状态栏带高度")
        XCTAssertLessThanOrEqual(insets.top, SeamRenderer.maxStatusBarCrop, "且不超过检测上限")
        XCTAssertEqual(insets.bottom, 0, "底部无纯色带，不应误裁")
    }

    /// B-3：左右各 20px 黑边 → 横向边缘检测内缩 ∈ (0, 20]，且 ≤ 上限。
    func testB_edgeDetection_reportsInsetWithinMax() {
        let edge = 20
        let img = TestImages.make(width: 200, height: 400) { ctx, w, h in
            ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0, 0, 0, 1])!)
            ctx.fill(CGRect(x: 0, y: 0, width: edge, height: h))
            ctx.fill(CGRect(x: w - edge, y: 0, width: edge, height: h))
            ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.6, 0.6, 0.6, 1])!)
            ctx.fill(CGRect(x: edge, y: 0, width: w - 2 * edge, height: h))
        }
        let insets = SeamRenderer().horizontalEdgeInsets(for: img)
        XCTAssertGreaterThan(insets.left, 0, "应检测到左黑边")
        XCTAssertGreaterThan(insets.right, 0, "应检测到右黑边")
        XCTAssertLessThanOrEqual(insets.left, CGFloat(edge), "左内缩 ≤ 黑边宽")
        XCTAssertLessThanOrEqual(insets.right, CGFloat(edge), "右内缩 ≤ 黑边宽")
        XCTAssertLessThanOrEqual(insets.left, SeamRenderer.maxEdgeInset, "且不超过检测上限")
    }
}
