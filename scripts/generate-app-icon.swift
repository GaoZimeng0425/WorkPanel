#!/usr/bin/env swift

import AppKit
import SwiftUI

// WorkPanel AppIcon 生成器:noir 深底 + 三列看板卡片剪影(中列顶卡 accent 橙)。
// 配色与 Theme.swift 对齐(panelTop/panelBottom/accent),改图案请同步注释来源。
// 用法:swift scripts/generate-app-icon.swift(输出直接落 Assets.xcassets/AppIcon.appiconset)

// MARK: - Colors(镜像 Theme.swift:7-16)

private let backgroundTop = Color(red: 0.039, green: 0.035, blue: 0.031)
private let backgroundBottom = Color(red: 0.005, green: 0.005, blue: 0.004)
private let cardForeground = Color(red: 245.0 / 255, green: 242.0 / 255, blue: 236.0 / 255)
private let accentCard = Color(red: 1.0, green: 0.55, blue: 0.08)

// MARK: - View

private struct AppIconView: View {
    let side: CGFloat

    var body: some View {
        let pad = side * 0.18                       // 四周安全区
        let gap = side * 0.05                       // 列间距
        let colW = (side - pad * 2 - gap * 2) / 3   // 列宽
        let cardH = (side - pad * 2 - colW * 0.18 * 2) / 3   // 三卡列的单卡高
        let cardGap = colW * 0.18

        RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [backgroundTop, backgroundBottom],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                HStack(spacing: gap) {
                    VStack(spacing: cardGap) {              // 左列:两卡
                        Card(w: colW, h: cardH, color: cardForeground)
                        Card(w: colW, h: cardH, color: cardForeground)
                    }
                    VStack(spacing: cardGap) {              // 中列:三卡,顶卡 accent
                        Card(w: colW, h: cardH, color: accentCard)
                        Card(w: colW, h: cardH, color: cardForeground)
                        Card(w: colW, h: cardH, color: cardForeground)
                    }
                    VStack(spacing: cardGap) {              // 右列:一卡 + 短卡
                        Card(w: colW, h: cardH, color: cardForeground)
                        Card(w: colW, h: cardH * 0.55, color: cardForeground.opacity(0.75))
                    }
                }
            }
            .frame(width: side, height: side)
    }

    private struct Card: View {
        let w: CGFloat
        let h: CGFloat
        let color: Color

        var body: some View {
            RoundedRectangle(cornerRadius: w * 0.22, style: .continuous)
                .fill(color)
                .frame(width: w, height: h)
        }
    }
}

// MARK: - Render targets

private let targets: [(filename: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

// MARK: - Output path

// #filePath resolves to this script's source file at compile time, even when
// invoked via shebang from anywhere.
let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDir = repoRoot
    .appendingPathComponent("WorkPanel")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")

guard FileManager.default.fileExists(atPath: outputDir.path) else {
    FileHandle.standardError.write(
        Data("error: output dir not found: \(outputDir.path)\n".utf8)
    )
    exit(1)
}

// MARK: - Render & write

@MainActor func renderAll() {
    for (filename, pixels) in targets {
        let renderer = ImageRenderer(content: AppIconView(side: pixels))
        renderer.scale = 1 // view side already equals output pixel count

        guard
            let nsImage = renderer.nsImage,
            let tiff = nsImage.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(
                Data("error: render failed for \(filename)\n".utf8)
            )
            exit(1)
        }

        let outURL = outputDir.appendingPathComponent(filename)
        do {
            try png.write(to: outURL)
        } catch {
            FileHandle.standardError.write(
                Data("error: write failed for \(filename): \(error)\n".utf8)
            )
            exit(1)
        }
    }
}

MainActor.assumeIsolated {
    renderAll()
}
print("ok: wrote \(targets.count) icons to \(outputDir.path)")
