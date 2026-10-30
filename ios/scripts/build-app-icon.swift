// Headless asset conversion of the existing brand mark, with an opaque RGB background.
// Run from ios/: swift scripts/build-app-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let assets = URL(fileURLWithPath: "App/Assets.xcassets", isDirectory: true)
let input = assets.appendingPathComponent("BrandMark.imageset/BrandMark.png")
let output = assets.appendingPathComponent("AppIcon.appiconset/AppIcon.png")
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
  let context = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("Unable to load the brand mark or allocate an icon context.") }
context.setFillColor(CGColor(srgbRed: 21 / 255, green: 30 / 255, blue: 40 / 255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 96, y: 96, width: 832, height: 832))
guard let rendered = context.makeImage(),
  let destination = CGImageDestinationCreateWithURL(
    output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("Unable to create the app icon.") }
CGImageDestinationAddImage(destination, rendered, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write the app icon.") }
print("Generated 1024 × 1024 opaque app icon from the existing brand mark.")
