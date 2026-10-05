import CoreGraphics

/// Cheap image measurements used while tracking a card in the live feed.
public enum ImageMetrics {
    /// Renders `image` as 8-bit grayscale at the given size.
    static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Variance of the Laplacian over a 480px-wide grayscale copy: higher is sharper.
    /// Crisp card text typically scores in the hundreds; motion blur drops it below ~50.
    public static func sharpness(of image: CGImage) -> Double {
        let width = 480
        let height = max(8, Int(Double(width) * Double(image.height) / Double(max(image.width, 1))))
        guard let pixels = grayscale(image, width: width, height: height) else { return 0 }
        var sum = 0.0, sumSquares = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let laplacian = Double(pixels[i - 1]) + Double(pixels[i + 1]) + Double(pixels[i - width])
                    + Double(pixels[i + width]) - 4 * Double(pixels[i])
                sum += laplacian
                sumSquares += laplacian * laplacian
            }
        }
        let count = Double((width - 2) * (height - 2))
        let mean = sum / count
        return sumSquares / count - mean * mean
    }
}
