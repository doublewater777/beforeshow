import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct LanguageSettingsView: View {
    @ObservedObject private var languageController = AppLanguageController.shared

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        languageController.select(language)
                    } label: {
                        HStack {
                            Text(language.displayName)
                                .font(BSFont.V3.body)
                                .foregroundColor(BSColor.Stage.foreground)
                            Spacer()
                            if languageController.language == language {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(BSColor.Stage.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(BSColor.Stage.surface)
                    .accessibilityLabel(language.displayName)
                    .accessibilityAddTraits(languageController.language == language ? .isSelected : [])
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .navigationTitle(BSLocalization.text("语言"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
