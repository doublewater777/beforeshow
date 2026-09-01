import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct LanguageSettingsView: View {
    @ObservedObject private var languageController = AppLanguageController.shared

    var body: some View {
        BSStageScaffold(title: "", subtitle: nil, bottomPadding: BSLayout.tabBarContentInset) {
            BSSettingsSurface {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            languageController.select(language)
                        } label: {
                            HStack(spacing: BSSpacing.compact) {
                                Text(language.displayName)
                                    .font(BSFont.V3.body.weight(.semibold))
                                    .foregroundColor(BSColor.Stage.foreground)
                                Spacer(minLength: 0)
                                if languageController.language == language {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(BSColor.Stage.accent)
                                }
                            }
                            .padding(.horizontal, BSSpacing.md)
                            .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
                            .frame(maxWidth: .infinity, minHeight: BSSettingsStyle.rowMinimumHeight, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SettingsPressButtonStyle())
                        .accessibilityLabel(language.displayName)
                        .accessibilityAddTraits(languageController.language == language ? .isSelected : [])

                        if language != AppLanguage.allCases.last {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
        .navigationTitle(BSLocalization.text("语言"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
