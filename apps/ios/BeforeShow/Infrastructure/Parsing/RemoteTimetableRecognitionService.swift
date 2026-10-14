import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum RemoteTimetableRecognitionError: LocalizedError, Equatable {
    case noImages
    case imageTooLarge
    case networkFailure
    case rateLimited
    case quotaExceeded
    case parseFailed(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .noImages:
            return BSLocalization.text("请先选择时刻表图片")
        case .imageTooLarge:
            return BSLocalization.text("图片过大，请压缩或选择更小图片后重试")
        case .networkFailure:
            return BSLocalization.text("网络连接失败，请检查网络后重试")
        case .rateLimited:
            return BSLocalization.text("当前识别请求较多，请稍后重试")
        case .quotaExceeded:
            return BSLocalization.text("免费识别次数已用完，升级 Pro 可无限次识别")
        case .parseFailed(let message):
            return message
        case .serverError(let message):
            return message
        }
    }
}

protocol TimetableRecognitionService: Sendable {
    #if canImport(UIKit)
    func recognize(images: [UIImage]) async throws -> TimetableExchangeDocument
    #endif
}

struct RemoteTimetableRecognitionService: TimetableRecognitionService {
    var client: BeforeShowCloudClient
    var maxImages: Int
    var maxDimension: CGFloat
    var compressionQuality: CGFloat

    init(
        client: BeforeShowCloudClient,
        maxImages: Int = 3,
        maxDimension: CGFloat = 2048,
        compressionQuality: CGFloat = 0.8
    ) {
        self.client = client
        self.maxImages = maxImages
        self.maxDimension = maxDimension
        self.compressionQuality = compressionQuality
    }

    @MainActor
    static func production() -> RemoteTimetableRecognitionService {
        RemoteTimetableRecognitionService(client: .production())
    }

    private struct RequestImage: Encodable {
        let mimeType: String
        let base64: String
    }

    private struct RequestBody: Encodable {
        let appInstanceId: String
        let appSignature: String
        let images: [RequestImage]
    }

    private struct ResponsePayload: Decodable {
        let ok: Bool
        let document: TimetableExchangeDocument?
        let model: String?
        let error: ErrorPayload?

        struct ErrorPayload: Decodable {
            let code: String
            let message: String
        }
    }

    #if canImport(UIKit)
    func recognize(images: [UIImage]) async throws -> TimetableExchangeDocument {
        guard !images.isEmpty else {
            throw RemoteTimetableRecognitionError.noImages
        }

        let slice = Array(images.prefix(maxImages))
        var requestImages: [RequestImage] = []

        for image in slice {
            let prepared = prepareImage(image)
            guard let data = prepared.jpegData(compressionQuality: compressionQuality) else {
                continue
            }
            if data.count > 4 * 1024 * 1024 {
                throw RemoteTimetableRecognitionError.imageTooLarge
            }
            requestImages.append(
                RequestImage(
                    mimeType: "image/jpeg",
                    base64: data.base64EncodedString()
                )
            )
        }

        guard !requestImages.isEmpty else {
            throw RemoteTimetableRecognitionError.noImages
        }

        let body = RequestBody(
            appInstanceId: client.credentials.appInstanceId,
            appSignature: client.credentials.appSignature,
            images: requestImages
        )

        let responseData: Data
        do {
            responseData = try await client.postJSON(
                path: "recognizeTimetable",
                body: body
            )
        } catch {
            throw RemoteTimetableRecognitionError.networkFailure
        }

        let response: ResponsePayload
        do {
            response = try JSONDecoder().decode(ResponsePayload.self, from: responseData)
        } catch {
            throw RemoteTimetableRecognitionError.serverError(BSLocalization.text("识别时刻表失败，请稍后重试"))
        }

        guard response.ok, let document = response.document else {
            if response.error?.code == "RATE_LIMITED" {
                throw RemoteTimetableRecognitionError.rateLimited
            }
            let message = response.error?.message ?? BSLocalization.text("未在图片中识别到演出时刻表，请确保图片清晰或手动重试")
            throw RemoteTimetableRecognitionError.serverError(message)
        }

        return document
    }

    private func prepareImage(_ image: UIImage) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }
        let aspect = size.width / size.height
        let targetSize: CGSize
        if aspect > 1 {
            targetSize = CGSize(width: maxDimension, height: maxDimension / aspect)
        } else {
            targetSize = CGSize(width: maxDimension * aspect, height: maxDimension)
        }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    #endif
}
