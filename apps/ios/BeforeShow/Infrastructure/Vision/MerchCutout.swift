import CoreImage
import UIKit
import Vision

/// 周边照片的前景抠图。识别不到主体或系统不支持时返回 nil，调用方保留原图。
enum MerchCutout {
    private static let maxEdge: CGFloat = 1400

    static func pngCutout(from data: Data) -> Data? {
        guard var image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let longest = max(image.extent.width, image.extent.height)
        if longest > maxEdge {
            let scale = maxEdge / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let output = CIImage(cvPixelBuffer: masked)
            guard let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
            return UIImage(cgImage: cgImage).pngData()
        } catch {
            return nil
        }
    }
}
