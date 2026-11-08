import SwiftData
import SwiftUI

/// 改一件周边的种类和名字。
struct MerchEditSheet: View {
    let item: MerchItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var kind: MerchKind = .other
    @State private var name = ""
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    ForEach(MerchKind.allCases) { option in
                        let isOn = option == kind
                        Button { kind = option } label: {
                            Text(option.title)
                                .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                                .foregroundStyle(isOn ? BSColor.Stage.background : BSColor.Stage.foreground.opacity(0.75))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(isOn ? AnyShapeStyle(BSColor.Stage.foreground.opacity(0.92)) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                TextField(kind.title, text: $name)
                    .font(.system(size: 16))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                if saveFailed {
                    Text(BSLocalization.text("没有保存，请重试")).font(.system(size: 13)).foregroundStyle(BSColor.Stage.live)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle(BSLocalization.text("周边"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: commit) { Image(systemName: "checkmark") }
                        .tint(BSColor.Stage.foreground)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .accessibilityLabel(BSLocalization.text("完成"))
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .preferredColorScheme(.dark)
        .onAppear {
            kind = item.kind
            name = item.name
        }
    }

    private func commit() {
        item.edit(kind: kind, name: name)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveFailed = true
        }
    }
}
