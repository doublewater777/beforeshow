import Photos
import UIKit

// MARK: - Footprint Photo Library

enum FootprintPhotoSaveError: LocalizedError {
    case rendererFailed
    case authorizationDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .rendererFailed:
            return BSLocalization.text("足迹图片生成失败，请重试。")
        case .authorizationDenied:
            return BSLocalization.text("没有照片添加权限，请在系统设置中允许 BeforeShow 添加照片。")
        case .saveFailed:
            return BSLocalization.text("照片保存失败，请重试。")
        }
    }
}

enum FootprintPhotoLibrary {
    static func save(_ image: UIImage) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw FootprintPhotoSaveError.authorizationDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FootprintPhotoSaveError.saveFailed)
                }
            }
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
