import PostHog
import SwiftUI

/// 把承载用户文字内容的视图标记为 session replay 需要遮罩的区域。
///
/// 规则见 `docs/observability/product-analytics.md`：不采集姓名、现场名、艺人名、
/// 场馆、邀请 token、URL、配文或任何用户输入文字。SDK 默认已遮罩全部输入框，
/// 但用户输入**展示**出来的内容（已保存的小记、昵称、配文）不会自动遮罩，
/// 需要显式标记。
extension View {
    /// 遮罩用户文字内容，使其不出现在 session replay 录像里。
    ///
    /// - Parameter isEnabled: 同一组件既承载用户素材又承载公共素材时（如封面全屏
    ///   预览）用它区分；默认无条件遮罩。
    func bsMaskUserContent(_ isEnabled: Bool = true) -> some View {
        postHogMask(isEnabled)
    }

    /// 记录 `$screen`。SwiftUI 下 SDK 的自动采集不生效，需显式调用。
    /// 名字会作为 `$screen_name` 附着到后续每个事件上，须用稳定的 ASCII 值。
    func bsScreenView(_ name: String) -> some View {
        postHogScreenView(name)
    }
}
