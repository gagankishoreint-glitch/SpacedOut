import AppKit
import SwiftUI

enum BrandLogo {
    private static let pngBase64 = """
        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
        """

    private static let cachedSourceImage: NSImage? = {
        guard let data = Data(base64Encoded: pngBase64, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data) else {
            return nil
        }
        image.isTemplate = true
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
