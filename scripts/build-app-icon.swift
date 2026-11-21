#!/usr/bin/env swift
// 按 Apple macOS App Icon HIG 规范，从浅色 / 深色源图生成：
//   - App/Resources/AppIcon-1024.png         （浅色真透明 1024×1024，824×824 Apple 连续圆角 + 100px 边距 + 原生投影）
//   - App/Resources/AppIcon-Dark-1024.png    （深色真透明 1024×1024，像素级对齐）
//   - App/Resources/Assets.xcassets/         （含 Light / Dark 全 10 档 macOS 分辨率）
//   - App/Resources/Assets.car               （actool 编译，供 macOS 15/26 深浅色自动切换）
//   - App/Resources/AppIcon.icns             （全分辨率 .icns 兜底）
//   - docs/branding/app-icon-*.png           （README / 宣传展示图）
//
// 用法：swift scripts/build-app-icon.swift [--qa-out /path/to/qa.png]

import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let resourcesURL = rootURL.appendingPathComponent("App/Resources", isDirectory: true)
let sourceURL = resourcesURL.appendingPathComponent("IconSource", isDirectory: true)
let brandingURL = rootURL.appendingPathComponent("docs/branding", isDirectory: true)
let xcassetsURL = resourcesURL.appendingPathComponent("Assets.xcassets", isDirectory: true)
let appIconSetURL = xcassetsURL.appendingPathComponent("AppIcon.appiconset", isDirectory: true)

var qaOutPath: String? = nil
for i in 1..<CommandLine.arguments.count {
    if CommandLine.arguments[i] == "--qa-out", i + 1 < CommandLine.arguments.count {
        qaOutPath = CommandLine.arguments[i + 1]
    }
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func loadCGImage(at url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("无法读取图片: \(url.path)")
    }
    return img
}

func savePNG(_ image: CGImage, to url: URL) {
    try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("无法创建 PNG 目标: \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("写入 PNG 失败: \(url.path)")
    }
}

/// 在水平/垂直中轴线上检测源图中的圆角方块精确边界（过滤白底与外部投影）。
func detectSquircleBounds(in image: CGImage) -> CGRect {
    let w = image.width
    let h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(
        data: &pixels,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: w * 4,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("无法创建像素分析上下文")
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    // 判据：白底与灰投影的饱和度都很低且亮度高；图标边框有明显蓝色/深色色度或低亮度。
    func isInsideIcon(x: Int, y: Int) -> Bool {
        let idx = (y * w + x) * 4
        let r = Double(pixels[idx])
        let g = Double(pixels[idx + 1])
        let b = Double(pixels[idx + 2])
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        let chroma = max(r, g, b) - min(r, g, b)
        // 图标边缘本身是蓝/深蓝玻璃，亮度 < 215 或色度 > 22
        return luma < 215.0 || chroma > 22.0
    }

    let midY = h / 2
    let midX = w / 2

    var left = 0
    for x in 0..<w { if isInsideIcon(x: x, y: midY) { left = x; break } }
    var right = w - 1
    for x in stride(from: w - 1, through: 0, by: -1) { if isInsideIcon(x: x, y: midY) { right = x; break } }
    var top = 0
    for y in 0..<h { if isInsideIcon(x: midX, y: y) { top = y; break } }

    // 源图圆角主体是严格 1:1 正方形；底部的原生投影会被亮度判据误判，
    // 因此直接用水平宽度 (right - left) 作为边长，从 top 向下对齐并四边内收 4px，
    // 彻底杜绝任何白底或灰投影毛边进入透明画布。
    let side = right - left
    let trim = 4
    let rect = CGRect(
        x: left + trim,
        y: top + trim,
        width: max(1, side - 2 * trim),
        height: max(1, side - 2 * trim)
    )
    print("  检测到圆角主体边界: \(rect) (原图 \(w)x\(h), 原始左右=\(left)..\(right), 顶=\(top))")
    return rect
}

/// 生成 Apple 连续圆角超椭圆路径：|x|^n + |y|^n = 1（n = 5.0 贴合 Apple macOS HIG 连续曲线）。
func appleSquirclePath(in rect: CGRect, n: Double = 5.0, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let cx = rect.midX
    let cy = rect.midY
    let rx = rect.width / 2.0
    let ry = rect.height / 2.0
    for i in 0..<steps {
        let theta = 2.0 * Double.pi * Double(i) / Double(steps)
        let c = cos(theta)
        let s = sin(theta)
        let x = cx + copysign(pow(abs(c), 2.0 / n), c) * rx
        let y = cy + copysign(pow(abs(s), 2.0 / n), s) * ry
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

/// 将原始 1024×1024 JPG 裁切并规范化为 Apple macOS HIG 透明 1024×1024 PNG：
/// - 主体 824×824，四周 100px 透明安全边距
/// - 精确 Apple 连续圆角裁切
/// - 原生 macOS 柔和向下投影
func buildAppleHIGIcon(from rawImage: CGImage, isDark: Bool) -> CGImage {
    let canvasSize = 1024
    let inset: CGFloat = 100.0
    let bodySize: CGFloat = CGFloat(canvasSize) - 2.0 * inset // 824.0
    let bodyRect = CGRect(x: inset, y: inset, width: bodySize, height: bodySize)

    // 先从原图精确裁剪出圆角方块区域（CGImage.cropping 使用左上为原点）
    let cropRect = detectSquircleBounds(in: rawImage)
    guard let cropped = rawImage.cropping(to: cropRect) else {
        fatalError("裁剪原图失败")
    }

    guard let ctx = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("无法创建 1024 画布")
    }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let squircle = appleSquirclePath(in: bodyRect, n: 5.0)

    // 1. 绘制 Apple 规范柔和投影（向下偏移 12px，模糊 24px，低透明黑）
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12),
        blur: 24,
        color: CGColor(colorSpace: sRGB, components: [0.0, 0.0, 0.0, isDark ? 0.36 : 0.28])!
    )
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(colorSpace: sRGB, components: [0.05, 0.1, 0.2, 1.0])!)
    ctx.fillPath()
    ctx.restoreGState()

    // 2. 用 Apple 连续圆角精确裁切并绘制主体
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    ctx.draw(cropped, in: bodyRect)

    // 3. 叠加极细的内缘玻璃高光描边（让深色/浅色背景下边界都锐利）
    ctx.addPath(squircle)
    ctx.setLineWidth(3.0)
    let rimAlpha: CGFloat = isDark ? 0.26 : 0.22
    ctx.setStrokeColor(CGColor(colorSpace: sRGB, components: [0.85, 0.94, 1.0, rimAlpha])!)
    ctx.strokePath()
    ctx.restoreGState()

    guard let result = ctx.makeImage() else {
        fatalError("生成最终图标失败")
    }
    return result
}

func resizeImage(_ image: CGImage, to px: Int) -> CGImage {
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("无法创建缩放上下文 \(px)")
    }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

/// 生成深浅色背景 + 多尺寸（256 / 128 / 64 / 32 / 16px）检验图。
func renderQASheet(light: CGImage, dark: CGImage, to url: URL) {
    let w = 1080
    let h = 760
    guard let ctx = CGContext(
        data: nil,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    // 上半部分：浅色 macOS 桌面/Dock 背景；下半部分：深色 macOS 桌面/Dock 背景
    ctx.setFillColor(CGColor(colorSpace: sRGB, components: [0.95, 0.96, 0.98, 1.0])!)
    ctx.fill(CGRect(x: 0, y: h / 2, width: w, height: h / 2))

    ctx.setFillColor(CGColor(colorSpace: sRGB, components: [0.10, 0.11, 0.14, 1.0])!)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 2))

    let sizes = [256, 128, 64, 32, 16]
    let gap = 48

    func drawRow(icon: CGImage, centerY: Int) {
        var x = 80
        for sz in sizes {
            let resized = resizeImage(icon, to: sz)
            let y = centerY - sz / 2
            ctx.draw(resized, in: CGRect(x: x, y: y, width: sz, height: sz))
            x += sz + gap
        }
    }

    // CoreGraphics 坐标系原点在左下：
    // 上半区（浅底）放 Light 图标；下半区（深底）放 Dark 图标
    drawRow(icon: light, centerY: h * 3 / 4)
    drawRow(icon: dark, centerY: h / 4)

    if let img = ctx.makeImage() {
        savePNG(img, to: url)
    }
}

@discardableResult
func runProcess(_ executable: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = args
    try! p.run()
    p.waitUntilExit()
    return p.terminationStatus
}

// ---------------------------------------------------------------- 主流程

print("==> 读取源图")
let rawLight = loadCGImage(at: sourceURL.appendingPathComponent("AppIcon-Light-raw.jpg"))
let rawDark = loadCGImage(at: sourceURL.appendingPathComponent("AppIcon-Dark-raw.jpg"))

print("==> 生成 Apple HIG 规范透明 1024×1024 主图")
let masterLight = buildAppleHIGIcon(from: rawLight, isDark: false)
let masterDark = buildAppleHIGIcon(from: rawDark, isDark: true)

savePNG(masterLight, to: resourcesURL.appendingPathComponent("AppIcon-1024.png"))
savePNG(masterDark, to: resourcesURL.appendingPathComponent("AppIcon-Dark-1024.png"))

print("==> 生成 Assets.xcassets (Light + Dark 全 10 档 macOS 分辨率)")
try? fileManager.removeItem(at: xcassetsURL)
try! fileManager.createDirectory(at: appIconSetURL, withIntermediateDirectories: true)

let rootContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try! rootContents.write(to: xcassetsURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

struct Slot {
    let pt: Int
    let scale: Int
    var px: Int { pt * scale }
    var sizeStr: String { "\(pt)x\(pt)" }
    var scaleStr: String { "\(scale)x" }
    var lightFile: String { "icon_\(pt)x\(pt)@\(scale)x.png" }
    var darkFile: String { "icon_\(pt)x\(pt)@\(scale)x_dark.png" }
}

let slots: [Slot] = [
    Slot(pt: 16, scale: 1), Slot(pt: 16, scale: 2),
    Slot(pt: 32, scale: 1), Slot(pt: 32, scale: 2),
    Slot(pt: 128, scale: 1), Slot(pt: 128, scale: 2),
    Slot(pt: 256, scale: 1), Slot(pt: 256, scale: 2),
    Slot(pt: 512, scale: 1), Slot(pt: 512, scale: 2),
]

var imageEntries: [[String: Any]] = []
for slot in slots {
    savePNG(resizeImage(masterLight, to: slot.px), to: appIconSetURL.appendingPathComponent(slot.lightFile))
    savePNG(resizeImage(masterDark, to: slot.px), to: appIconSetURL.appendingPathComponent(slot.darkFile))

    imageEntries.append([
        "filename": slot.lightFile,
        "idiom": "mac",
        "scale": slot.scaleStr,
        "size": slot.sizeStr
    ])
    imageEntries.append([
        "appearances": [["appearance": "luminosity", "value": "dark"]],
        "filename": slot.darkFile,
        "idiom": "mac",
        "scale": slot.scaleStr,
        "size": slot.sizeStr
    ])
}

let appIconContents: [String: Any] = [
    "images": imageEntries,
    "info": ["author": "xcode", "version": 1]
]
let jsonData = try! JSONSerialization.data(withJSONObject: appIconContents, options: [.prettyPrinted, .sortedKeys])
try! jsonData.write(to: appIconSetURL.appendingPathComponent("Contents.json"))

print("==> 使用 actool 编译 Assets.car 与 AppIcon.icns")
let tmpPlist = resourcesURL.appendingPathComponent(".actool-info.plist")
let status = runProcess("/usr/bin/xcrun", [
    "actool",
    xcassetsURL.path,
    "--compile", resourcesURL.path,
    "--platform", "macosx",
    "--minimum-deployment-target", "14.0",
    "--app-icon", "AppIcon",
    "--output-partial-info-plist", tmpPlist.path
])
try? fileManager.removeItem(at: tmpPlist)
if status != 0 {
    fatalError("actool 编译失败，退出码 \(status)")
}

print("==> 导出 docs/branding/ 展示图")
try? fileManager.createDirectory(at: brandingURL, withIntermediateDirectories: true)
savePNG(masterLight, to: brandingURL.appendingPathComponent("app-icon-1024.png"))
savePNG(masterDark, to: brandingURL.appendingPathComponent("app-icon-dark-1024.png"))
for px in [512, 256, 128] {
    savePNG(resizeImage(masterLight, to: px), to: brandingURL.appendingPathComponent("app-icon-\(px).png"))
    savePNG(resizeImage(masterDark, to: px), to: brandingURL.appendingPathComponent("app-icon-dark-\(px).png"))
}

if let qaOut = qaOutPath {
    print("==> 生成深浅色多尺寸检验图: \(qaOut)")
    renderQASheet(light: masterLight, dark: masterDark, to: URL(fileURLWithPath: qaOut))
}

print("OK -> App/Resources/AppIcon.icns & App/Resources/Assets.car")
