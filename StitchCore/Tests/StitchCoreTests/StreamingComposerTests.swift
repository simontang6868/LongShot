import CoreGraphics
import CoreFoundation
import ImageIO
import XCTest
@testable import StitchCore

final class StreamingComposerTests: XCTestCase {

    // =======================================================================
    // A 组：零重叠 + 关检测，验「尺寸算术」是否正确（保留既有意图）
    // =======================================================================

    /// A-1：零重叠 + 关边/状态栏检测 → 单张长图，总高=各图高之和，宽不变
    func testA_dimensionArithmetic_zeroOverlap_noDetection_singleOutput() throws {
        let images = [
            TestImages.solid(width: 120, height: 200, (255, 0, 0)),
            TestImages.solid(width: 120, height: 200, (0, 255, 0)),
            TestImages.solid(width: 120, height: 200, (0, 0, 255)),
            TestImages.solid(width: 120, height: 200, (255, 255, 0))
        ]
        var opts = StreamingComposer.Options.default
        opts.enableEdgeCrop = false
        opts.enableStatusBarCrop = false
        let out = try StreamingComposer().compose(images: images,
                                                  crop: CropParams(topCropRatio: 0, bottomCropRatio: 0),
                                                  options: opts)
        XCTAssertFalse(out.sliced)
        XCTAssertEqual(out.slices.count, 1)
        XCTAssertEqual(out.totalWidth, 120)
        XCTAssertEqual(out.totalHeight, 800)
        XCTAssertEqual(out.slices[0].width, 120)
        XCTAssertEqual(out.slices[0].height, 800)
    }

    /// A-2：零重叠 + 关检测，超高 → 自动切片，每片 ≤ sliceHeight
    func testA_dimensionArithmetic_zeroOverlap_noDetection_autoSlice() throws {
        var images: [CGImage] = []
        for _ in 0..<30 {
            images.append(TestImages.solid(width: 120, height: 600, (100, 150, 200)))
        }
        var opts = StreamingComposer.Options.default
        opts.enableEdgeCrop = false
        opts.enableStatusBarCrop = false
        opts.maxSingleHeight = 16000
        opts.sliceHeight = 8000
        let out = try StreamingComposer().compose(images: images,
                                                  crop: CropParams(topCropRatio: 0, bottomCropRatio: 0),
                                                  options: opts)
        XCTAssertTrue(out.sliced)
        XCTAssertGreaterThan(out.slices.count, 1)
        for s in out.slices {
            XCTAssertLessThanOrEqual(s.height, 8000, "每片应不超过 8000px")
        }
        let sum = out.slices.reduce(0) { $0 + $1.height }
        XCTAssertEqual(sum, 18000)
        XCTAssertEqual(out.totalWidth, 120)
    }

    /// A-3：零重叠 + 关检测，混宽按第一张缩放对齐
    func testA_dimensionArithmetic_zeroOverlap_noDetection_mixedWidth() throws {
        let images = [
            TestImages.solid(width: 120, height: 300, (10, 20, 30)),
            TestImages.solid(width: 240, height: 300, (40, 50, 60)),
            TestImages.solid(width: 120, height: 300, (70, 80, 90))
        ]
        var opts = StreamingComposer.Options.default
        opts.enableEdgeCrop = false
        opts.enableStatusBarCrop = false
        opts.normalizeWidthToFirst = true
        let out = try StreamingComposer().compose(images: images,
                                                  crop: CropParams(topCropRatio: 0, bottomCropRatio: 0),
                                                  options: opts)
        XCTAssertEqual(out.totalWidth, 120, "输出宽度应等于第一张宽度")
        XCTAssertFalse(out.sliced)
    }

    /// A-4（基线）：编码 PNG 产出非空 Data
    func testA_encode_pngProducesNonEmptyData() throws {
        let img = TestImages.solid(width: 100, height: 100, (120, 30, 200))
        let data = StreamingComposer.encode(img, format: .png)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }

    // =======================================================================
    // B 组：默认 15% + 状态栏/黑边检测全开，断言「检测裁掉量 ∈ [0, 状态栏带高度]」
    //       （刻意不关检测，检测必须真实发生：delta>0）
    // =======================================================================

    /// B-1：默认 15% 重叠 + 检测全开；有状态栏带时，检测额外裁掉量 ∈ (0, 带高]，且不超过上限
    func testB_compose_defaultCrop_allDetectionsOn_cropsStatusbarBoundedByBand() throws {
        let bandHeight = 50
        let totalH = 400

        func makeImage(withBand: Bool) -> CGImage {
            TestImages.make(width: 200, height: totalH) { ctx, w, h in
                // 高频正弦内容（相邻行差异 > 容差，杜绝伪纯色前缀）
                for y in 0..<h {
                    let v = 0.5 + 0.5 * sin(Double(y) * 0.8)
                    let c = UInt8(max(0, min(1, v)) * 255)
                    ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                             components: [CGFloat(c)/255, CGFloat(c)/255, CGFloat(c)/255, 1])!)
                    ctx.fill(CGRect(x: 0, y: y, width: w, height: 1))
                }
                if withBand {
                    ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                             components: [1, 1, 1, 1])!)
                    ctx.fill(CGRect(x: 0, y: 0, width: w, height: bandHeight))
                }
            }
        }

        var opts = StreamingComposer.Options.default   // 默认 enableStatusBarCrop=true, enableEdgeCrop=true
        opts.maxSingleHeight = Int.max
        opts.sliceHeight = Int.max
        opts.outputFormat = .png

        let outWithout = try StreamingComposer().compose(images: [makeImage(withBand: false)],
                                                         crop: .default, options: opts)
        let outWith = try StreamingComposer().compose(images: [makeImage(withBand: true)],
                                                      crop: .default, options: opts)

        let hWithout = outWithout.slices[0].height
        let hWith = outWith.slices[0].height
        let delta = hWithout - hWith   // 检测额外裁掉的量（带图比无带图矮的部分）
        // 检测确实发生（不是靠关检测凑答案）
        XCTAssertGreaterThan(delta, 0, "检测开启时应比关检测多裁掉状态栏带")
        // 检测裁掉量必须在 [0, 状态栏带高度] 内
        XCTAssertLessThanOrEqual(delta, bandHeight, "检测裁掉量 ≤ 状态栏带高度")
        // 且不超过检测上限
        XCTAssertLessThanOrEqual(delta, Int(SeamRenderer.maxStatusBarCrop))
    }

    // =======================================================================
    // 分片写出架构验证：边画边编码、立即释放，绝不累积分片 CGImage
    // =======================================================================

    /// 30 张 → 30 个分片；composer 必须边画边编码、立即释放，
    /// 输出不持有任何 CGImage（只看 Data），且输入图不被 Output 长期持有。
    func test_sliceWriting_streamsThirtySlicesWithoutAccumulatingCGImages() throws {
        let input = TestImages.solid(width: 120, height: 600, (100, 150, 200))
        var opts = StreamingComposer.Options.default
        opts.enableEdgeCrop = false
        opts.enableStatusBarCrop = false
        opts.maxSingleHeight = Int.max     // 不靠总高触发，靠 sliceHeight 触发
        opts.sliceHeight = 600             // 每张独占一片 → 恰好 30 片
        opts.outputFormat = .png

        let images = Array(repeating: input, count: 30)   // 先建数组，使 input 被其持有
        let rcBefore = CFGetRetainCount(input)
        let out = try StreamingComposer().compose(images: images,
                                                  crop: CropParams(topCropRatio: 0, bottomCropRatio: 0),
                                                  options: opts)
        let rcAfter = CFGetRetainCount(input)
        // Output 不长期持有输入图 —— 无累积持有
        XCTAssertEqual(rcAfter, rcBefore, "composer 不应让 Output 长期持有输入图（无累积持有）")

        XCTAssertEqual(out.slices.count, 30, "应写出 30 个独立分片")
        XCTAssertTrue(out.sliced)

        // 每片独立编码、可解码、尺寸正确（证明不是攒成一张大图）
        var sumH = 0
        for s in out.slices {
            XCTAssertGreaterThan(s.data.count, 0, "每片都应有编码数据")
            guard let cg = CGImageSourceCreateWithData(s.data as CFData, nil)
                    .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else {
                XCTFail("分片数据应可解码为 CGImage"); continue
            }
            XCTAssertEqual(cg.width, 120)
            XCTAssertEqual(cg.height, 600)
            sumH += cg.height
        }
        XCTAssertEqual(sumH, 30 * 600, "切片总高应等于原始累加高")
    }

    // =======================================================================
    // CGBackend 协议隔离验证：编排层把「建画布 / 编码」委托给注入的后端，
    // 自己不直接调 CG。SpyBackend 包裹 CGBackend 并计数。
    // =======================================================================

    /// 隔离验证：composer 必须经由后端建画布与编码（而非自己调 CGContext/CGImageDestination）
    func testCGBackendIsolation_composeDelegatesCanvasAndEncodeToInjectedBackend() throws {
        let spy = SpyBackend()
        let images = (0..<4).map { _ in TestImages.solid(width: 120, height: 200, (100, 150, 200)) }
        let out = try StreamingComposer(backend: spy).compose(
            images: images,
            crop: CropParams(topCropRatio: 0, bottomCropRatio: 0)
        )
        // 必须真的向后端要了画布（单张 → 至少 1 次）
        XCTAssertGreaterThan(spy.makeCanvasCalls, 0, "composer 必须把建画布委托给后端")
        // 每个分片都经由后端编码
        XCTAssertEqual(spy.encodeCalls, out.slices.count, "分片数应与后端编码调用数一致")
        XCTAssertFalse(out.slices.isEmpty)
    }
}

/// 隔离探针：包裹 CGBackend，记录 StreamingComposer 是否真的把 CG 绘制/编码委托出来。
/// 它的存在本身就是「CGBackend 协议隔离」的可测试证据 —— 编排层接收的是协议，不是 CG。
private struct SpyBackend: StitchBackend {
    let inner = CGBackend()
    var makeCanvasCalls = 0
    var encodeCalls = 0

    func makeCanvas(width: Int, height: Int, fill: CGColor) -> BackendCanvas? {
        makeCanvasCalls += 1
        return inner.makeCanvas(width: width, height: height, fill: fill)
    }
    func scaled(_ image: CGImage, toWidth width: Int, height: Int) -> CGImage {
        inner.scaled(image, toWidth: width, height: height)
    }
    func encode(_ image: CGImage, format: StreamingComposer.OutputFormat) -> Data? {
        encodeCalls += 1
        return inner.encode(image, format: format)
    }
}
