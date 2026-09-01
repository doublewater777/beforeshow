import SwiftUI
import UIKit

// MARK: - Shared Draft Field Components

struct AddShowLabeledTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isRequired = false
    var isRecognized = false
    var keyboardType: UIKeyboardType = .default
    var helperText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(
                title: title,
                isRequired: isRequired,
                mark: isRecognized ? .recognized : nil
            )
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .textContentType(keyboardType == .URL ? .URL : nil)
                .keyboardType(keyboardType)
                .addShowInputChrome()
                .overlay {
                    if isRecognized {
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.Accent.prepare.opacity(0.30), lineWidth: 1)
                    }
                }

            if let helperText {
                Text(helperText)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AddShowFieldLabel: View {
    enum Mark {
        /// 识别导入成功：薄荷绿「✓ 已识别」
        case recognized
        /// 缺确认：金色「待确认」
        case needed
    }

    let title: String
    let isRequired: Bool
    var mark: Mark? = nil

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BSColor.textTertiary)
            if isRequired {
                Text("*")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
            }

            Spacer(minLength: 0)

            switch mark {
            case .recognized:
                Label("已识别", systemImage: "checkmark")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(BSColor.Accent.prepare)
            case .needed:
                Label("待确认", systemImage: "exclamationmark")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
            case nil:
                EmptyView()
            }
        }
    }
}
