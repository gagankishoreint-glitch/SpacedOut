import AppKit
import SwiftUI

enum BrandLogo {
    private static let pngBase64 = """
        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
        """

    private static let appIconBase64 = """
        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
        MDAksrHWAAAAAElFTkSuQmCC
        """

    private static let cachedSourceImage: NSImage? = {
        guard let data = Data(base64Encoded: pngBase64, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()

    private static let cachedAppIconImage: NSImage? = {
        guard let data = Data(base64Encoded: appIconBase64, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }()

    @MainActor
    static func menuBarImage(pointSize: CGFloat = 17) -> NSImage? {
        guard let base = cachedSourceImage?.copy() as? NSImage else { return nil }
        base.size = NSSize(width: pointSize, height: pointSize)
        base.isTemplate = true
        return base
    }

    @MainActor
    static func dockAppIcon() -> NSImage? {
        cachedAppIconImage
    }

    @MainActor
    static func swiftUIImage() -> Image? {
        guard let image = cachedSourceImage else { return nil }
        return Image(nsImage: image)
            .renderingMode(.template)
    }
}

struct BrandLogoMark: View {
    var size: CGFloat = 18
    var color: Color = .primary

    var body: some View {
        if let image = BrandLogo.swiftUIImage() {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(color)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.8))
                .foregroundStyle(color)
        }
    }
}
