import Foundation

enum DynamicCoverErrorMessagePolicy {
    static func message(for error: DynamicCoverMediaStoreError) -> String {
        switch error {
        case .fileTooLarge: return BSLocalization.text("视频太大，最多支持 100 MB。")
        case .invalidDuration: return BSLocalization.text("视频不能超过 15 秒。")
        case .unsupportedVideo, .missingVideoTrack: return BSLocalization.text("这个文件不是可用的视频。")
        case .insufficientDiskSpace: return BSLocalization.text("设备存储空间不足。")
        case .staleReplacement: return BSLocalization.text("现场信息已变化，请重新选择视频。")
        case .importCancelled: return BSLocalization.text("视频导入已取消，请重新选择。")
        default: return BSLocalization.text("视频没有载入，请重试。")
        }
    }
}
