# HANDOFF.md · LongShot 交接报告

> 给下一个会话读的。读完能从断点继续，不用重跑已验证的东西。
> 仓库：`simontang6868/LongShot`（公开）· 最后更新：2026-10-29（Asia/Shanghai）

---

## 0. 一句话现状

**ipa 已经出来了，并且已拆包验证**：arm64 真机版、1058KB 二进制、bundle id `com.simontang.longshot`、
MinimumOSVersion 16.0、未签名（无 `_CodeSignature`，正是爱思现场签要的形态）。
StitchCore 25 tests 绿；App 层已具备可编译条件并**在云 macOS runner 上真的编译通过**。

**剩下的只有一件事：把它装进国区 iPhone，然后真机验收。**

---

## 1. 钉死、不许动

| 项 | 值 |
|---|---|
| 远端 `main` | `158435c639833ed90e4276dc688d4c9fea8c65ae`（快进而来，未 force、未改写历史） |
| 分支 `app-target`（本地） | `158435c`，与远端 main 同点 |
| 绿的 IPA run | `41012759537` success（2026-10-30T06:12:59Z → 06:14:19Z） |
| 绿的 CI run | `41012759481` success（StitchCore swift test 重跑仍绿） |
| ipa artifact | id `12957954086` · `longshot-unsigned-ipa` · 0.29 MB |
| 备份分支 | `refs/heads/backup/fb8cca2` → `fb8cca2b25928915104889b11cfebde408bd5ac0` |
| 备份标签 | `refs/tags/backup/fb8cca2-tag` → 同上（加 `-tag` 后缀是故意的，避免同分支名歧义） |
| 上一绿提交 | `d8da3ea`（API 写入，树与本地 `659f97b` 逐字节等价；`git diff 659f97b origin/main` 为空） |

铁律：不 `reset --hard`、不 `rebase -i`、不删两个备份 ref、不用裸 `git push -f`。
必须改写历史时用 `--force-with-lease`，且只在树对账通过之后。

---

## 2. 已经验证过、别重做

### 2.1 StitchCore 测试全绿
GitHub Actions run `40840090642`（macOS runner）：**Executed 25 tests, with 0 failures**
（CropSeam 10 / OverlapAdvisorSample 8 / StreamingComposer 7）。

### 2.2 CGBackend 协议隔离
所有 `CGContext` / `CGImageDestination` 真身只在 `CGBackend.swift`。验证方式：

```bash
grep -n 'CGContext(\|CGImageDestination\|ctx\.draw\|ctx\.fill\|ctx\.makeImage' \
  StitchCore/Sources/StitchCore/StreamingComposer.swift
# 命中全在注释里，零代码调用
```

有隔离测试 `testCGBackendIsolation_composeDelegatesCanvasAndEncodeToInjectedBackend`（SpyBackend 计数断言委托）。

### 2.3 浏览器 Demo
`stitch-demo.html`（约 31KB，单文件，双击即开，0 网络请求）。三栏：参数 / 原始截图（红=裁 绿=保留）/ 拼后长图。

**修过一个真 bug，务必继承**：推荐重叠率曾算成 37.2%（应 ≈15%）。
根因：全局搜索 + 内容里 50px 等距网格 → 1D 行均值周期混叠。
修法：±8% 搜索窗口 + 行纹理加权（大片留白的行几乎不投票）+ 网格间距 44~56px 抖动。

**认知模型（写代码前先读）**：手滚多少是物理事实，不随滑块变。基准 543px = 15% 单侧重叠（127×2）+ 47px 状态栏带。
滑块只决定"裁多少"：拖到 20% → 长图缺内容；拖到 10% → 长图重复。这是硬拼的真相，不是 bug。

已验三组数字：15%/12张/543 → 6770px·1片·误差0；15%/12张/563 → 缺失220行·推荐13.9%；15%/30张/543 → 16544px·3片。

### 2.4 一个已知视觉项（不是 bug）
关掉"状态栏带检测"时，长图顶部留 47px 灰带，每条接缝多 47 行重复。UI 如实呈现即可。

---

## 3. 2026-10-29 本次会话做了什么

### 3.1 关键发现：App 层从未被编译过
CI 只跑 `StitchCore` 的 `swift test`。`LongShotApp/` 下 13 个 `.swift`（1179 行）**一次都没被编译**，
里面躺着 8 类确定的编译错误。只要 CI 一 `archive`，必然全红。

修复原则：**只动 App 层，StitchCore 一个字节不碰**（保住 §6 的 11 个指纹，也保住"测试已绿"这个前提不被污染）。

| # | 文件 | 错误 | 修法 |
|---|---|---|---|
| 1 | `UI/Components.swift` | `EmptyStateView` 用合成 memberwise init，强制 `title:` 标签，4 个调用点全错 | 补 `init(_ title:systemImage:description:)` |
| 2 | `Models/Models.swift` | 用 `UIImage` 未 import UIKit；`CGImageSourceCreateWithURL` 未 import ImageIO | 补两个 import |
| 3 | `Models/CacheManager.swift` | 用 `CGImage` 未 import CoreGraphics | 补 import |
| 4 | `UI/HistoryView.swift` | 用 `CropParams` 却没 `import StitchCore`；用 `UIImage` 缺 UIKit | 补两个 import |
| 5 | `Pickers/AlbumPicker.swift` | 用 `UIImage` 缺 UIKit | 补 import |
| 6 | `UI/EditorView.swift` | `[UIImage]` 缺 UIKit；`init` 是 nonisolated 却构造 `@MainActor` 的 `StitchViewModel` | 补 import + `init` 标 `@MainActor` |
| 7 | `UI/ResultView.swift` | `CIImage(cgImage:)` 是非可选构造器却被 `guard let`；`OutputFormat` 未声明 `Equatable` 却用于 `== .pdf` 和 `onChange(of:)` | 去掉 `guard let`；改 `if case .pdf`；`onChange` 改用 Hashable 桥接 `formatSel` |
| 8 | `EditorView` / `ResultView` / `ScreenshotImport` | `.topBarTrailing` 是 **iOS 17+**，部署目标 16.0 会直接编译失败 | 改 `.navigationBarTrailing` |

### 3.2 补上工程描述（不用 Mac）
- `project.yml` —— XcodeGen 描述文件（纯文本，Windows 可改）。`*.xcodeproj` 本就在 `.gitignore` 里，所以工程文件由 CI 现场 `xcodegen generate` 生成，不提交。
- `LongShotApp/Info.plist` —— bundle id `com.simontang.longshot`、显示名"长图拼接"、`UILaunchScreen`、仅竖屏、相册读写用途说明。
- `LongShotApp/Assets.xcassets/` —— 含手工用纯 Python（zlib）生成的 1024×1024 图标（深底 + 白色长页 + 两道红接缝）。

### 3.3 新增 `ipa.yml`（不动已绿的 `ci.yml`）
`xcodegen generate` → `xcodebuild -sdk iphoneos ... CODE_SIGNING_ALLOWED=NO build` → `Payload/*.ipa` → artifact。

**为什么是未签名**：runner 上没有你的开发者证书，ad-hoc/development 导出必然失败；
而爱思助手的"签名安装"本来就要用你的 Apple ID 现场签一次。我们只负责把 arm64 设备版 `.app` 打成结构合法的 ipa。

---

## 4. 出 ipa（已完成）与装进国区 iPhone（待做）

### 4.1 已完成：出包
`app-target` → `main` 快进推送 → `IPA` run `41012759537` 全绿 → artifact `longshot-unsigned-ipa`（id `12957954086`）。

拆包实测（不是靠"绿"推断）：

```
Payload/LongShotApp.app/LongShotApp   1,083,208 B   Mach-O cputype=16777228 (arm64)
Payload/LongShotApp.app/Info.plist           1,575 B   CFBundleIdentifier=com.simontang.longshot
                                                       CFBundleDisplayName=长图拼接
                                                       MinimumOSVersion=16.0
                                                       UIDeviceFamily=[1]
Payload/LongShotApp.app/Assets.car          76,447 B   AppIcon60x60@2x.png 已编译
（无 _CodeSignature、无 embedded.mobileprovision → 未签名，符合预期）
```

### 4.2 待做：装进国区 iPhone（Windows 侧载）
1. 下载 ipa：GitHub → Actions → run `41012759537` → Artifacts → `longshot-unsigned-ipa`
   （或直接用本地已下载的 `LongShot-unsigned.ipa`，306,298 B）
2. 电脑装爱思助手（i4.cn，免费）→ iPhone 数据线连上 → 手机点"信任此电脑"
3. 爱思 → 工具箱 → **签名安装** → 选 ipa → 用你的 Apple ID 现场签
4. 手机：设置 → 通用 → VPN 与设备管理 → 信任该证书
5. 7 天过期就插线重签一次（约 30 秒）。国区不走 TestFlight 免签，也不建议越狱。

### 4.3 验收（手机上 5 张图跑一遍）
- 选 5 张连续截图 → 拼 → 看接缝有无重复/缺失
- 拖重叠滑块，对照白天玩 `stitch-demo.html` 的手感
- 30 张触发分片 → 看是否 ≤8000px 一片
- 闪退就把手机那一下截图回来，这是云端验不出来的唯一部分

---

## 5. 环境坑（会再咬人，务必先读）

### 5.1 git 隧道 502 —— 已解除
曾因代理掐 `CONNECT host:443` 导致 `git fetch` 一律 502，只能走 GitHub API 写入文件。
2026-10-29 复查 `git ls-remote` 已通，隧道恢复。（读操作无需凭证；**写仍需要 PAT 或已登录凭证**。）

### 5.2 Windows schannel 吊销检查 —— 会拦住 push
本机 push 报：

```
fatal: unable to access ...: schannel: next InitializeSecurityContext failed:
CRYPT_E_REVOCATION_OFFLINE (0x80092013)
```

`-c http.schannelCheckRevoke=false` **无效**，必须换后端：

```bash
git -c http.sslBackend=openssl push <url> <ref>:<ref>
```

OpenSSL 后端不带 CRL 检查，一次就通。`ls-remote` 也可能同样被拦，同样加这个参数。

### 5.3 凭证卫生
推送用 `https://x-access-token:<PAT>@github.com/...` 形式，用完确认：

```bash
grep -in "ghp_\|x-access-token\|password" .git/config   # 必须无命中
ls -a ~/.git-credentials                                # 必须不存在
```

历史 PAT（`ghp_3Sy2…`、`ghp_GRTl…`、`ghp_cd6V…`）都已明文出现过，**用完即吊销**。

---

## 6. 文件指纹（对账用，`git hash-object`，顺序固定）

```
cd4a36e97969a48866531c774780667e8ae17f67  StitchCore/Package.swift                      681
b0ee1fd1194f744ec3378d81a52d1760d0cf9b48  StitchCore/Sources/StitchCore/CGBackend.swift  4363
c3a91eec426ab96c410b12ac8fe836f1755e999e  StitchCore/Sources/StitchCore/CropParams.swift 4329
5ed2b046dce349d9ee3e98dc939e7934667e3b9f  StitchCore/Sources/StitchCore/OverlapAdvisor.swift 5620
d9a8e715b51333b3f21279a670f3a74f24900ffc  StitchCore/Sources/StitchCore/SeamRenderer.swift  8342
9c1380e7139e78ca9fdc942086396688ac5c831b  StitchCore/Sources/StitchCore/StreamingComposer.swift 15266
d23e07eea580ec9ed851b3f2be9eac4394df0c12  StitchCore/Tests/OverlapAdvisorTests/OverlapAdvisorSampleTests.swift 2932
33bcfbc5f68b477ae6b7325e8f8441a891f1d5e2  StitchCore/Tests/OverlapAdvisorTests/TestImages.swift 2432
794e43799390dc422b4e01f3accbe20ab260754e  StitchCore/Tests/StitchCoreTests/CropSeamTests.swift 5927
c593f404a45cf4297a8bed204098d1cf40ec2a6a  StitchCore/Tests/StitchCoreTests/StreamingComposerTests.swift 11140
6dea4743e2e5dc7f170b9175fdd575f1423e0920  StitchCore/Tests/StitchCoreTests/TestImages.swift 2649
```

文件数 = 11（`Package.swift` 本身也匹配 `*.swift`，别重复计）。2026-10-29 复验：11 项全部一致。

---

## 7. 冻结清单

- 拖拽调序 ❄️
- 打码 / 美化 ❄️（代码在 `ResultView.blurRegions`，能编译但未真机验证）
- UI 大改 ❄️
- CGBackend 协议形态 ❄️（动它要重跑 §2.2 的 grep 证明）
- StitchCore 全部源文件 ❄️（要改先想清楚：改了 §6 指纹就对不上了）
- 两个备份 ref ❄️

唯一解冻项：§4 的出包与签名，且只在"确认要上手机"这条线上动。

---

## 8. 给下一个会话的启动语

```
继续 LongShot 项目。先读仓库根目录 HANDOFF.md（就是这份）。
现状：StitchCore 25 tests 已绿；ipa 已产出并拆包验证（arm64 / 1058KB / com.simontang.longshot /
iOS 16.0 / 未签名）。远端 main = 158435c。
唯一目标：把 ipa 装进国区 iPhone 并做真机验收（§4.2 / §4.3）。
真机若暴露问题（接缝重复缺失、分片、闪退、内存），按报错改 —— 只改 LongShotApp/，不碰 StitchCore。
push 前记得加 -c http.sslBackend=openssl（见 §5.2）。
备份 ref backup/fb8cca2 一个字节都别动。
```
