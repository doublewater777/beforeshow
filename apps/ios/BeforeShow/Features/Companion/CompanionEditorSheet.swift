import SwiftData
import SwiftUI

/// Local companion names for one show. Every edit saves immediately; the list itself
/// is the feedback. Works the same before the show and on past footprints.
struct CompanionEditorSheet: View {
    let show: Show

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var allShows: [Show]
    @State private var newName = ""
    @State private var editingName: String?
    @State private var editingText = ""
    @State private var selectedPairName: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case add
        case rename
    }

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            VStack(spacing: BSSpacing.md) {
                BSStageSheetHeader(
                    icon: show.hasCompanions ? "person.2.fill" : "person.2",
                    title: CompanionQuickActionPresentation(companionNames: show.companionNames).displayTitle,
                    subtitle: show.name
                )
                addField
                if !suggestions.isEmpty {
                    suggestionRow
                }
                if show.hasCompanions {
                    VStack(spacing: BSSpacing.sm) {
                        ForEach(show.companionNames, id: \.self) { name in
                            row(for: name)
                        }
                    }
                }
            }
        }
        .onChange(of: focusedField) { old, new in
            if old == .rename, new != .rename, let editingName { commitRename(editingName) }
        }
        .sheet(
            isPresented: Binding(
                get: { selectedPairName != nil },
                set: { if !$0 { selectedPairName = nil } }
            )
        ) {
            if let selectedPairName {
                NavigationStack {
                    CompanionPairFootprintView(
                        companionName: selectedPairName,
                        shows: CompanionHistory.shows(with: selectedPairName, from: allShows)
                    )
                }
            }
        }
    }

    private var suggestions: [String] {
        CompanionHistory.recentNames(from: allShows, excluding: show.companionNames)
    }

    private var addField: some View {
        HStack(spacing: BSSpacing.sm) {
            TextField(BSLocalization.text("名字"), text: $newName)
                .focused($focusedField, equals: .add)
                .submitLabel(.done)
                .onSubmit { add(newName) }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BSColor.Stage.foreground)
            Button {
                add(newName)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(BSColor.Stage.foreground)
            }
            .buttonStyle(.plain)
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(BSLocalization.text("添加"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: BSLayout.minTouchTarget)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.sm) {
                ForEach(suggestions, id: \.self) { name in
                    Button {
                        add(name)
                    } label: {
                        Label(name, systemImage: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(BSColor.Stage.foreground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(BSColor.Stage.surface, in: Capsule())
                            .overlay(Capsule().stroke(BSColor.Stage.border))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(for name: String) -> some View {
        let count = CompanionHistory.shows(with: name, from: allShows).count
        HStack(spacing: BSSpacing.compact) {
            Text(String(name.prefix(1)))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(BSColor.Stage.background)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [BSColor.Stage.accent, BSColor.Stage.glowBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .accessibilityHidden(true)

            if editingName == name {
                TextField(name, text: $editingText)
                    .focused($focusedField, equals: .rename)
                    .submitLabel(.done)
                    .onSubmit { commitRename(name) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
            } else {
                Button {
                    editingName = name
                    editingText = name
                    focusedField = .rename
                } label: {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .bsMaskUserContent()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if count > 0, editingName != name {
                Button {
                    selectedPairName = name
                } label: {
                    HStack(spacing: 4) {
                        Text(BSLocalization.format("一起 %lld 场", Int64(count)))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                }
                .buttonStyle(.plain)
            }

            Button {
                remove(name)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(BSColor.Stage.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.format("移除%@", name))
        }
        .padding(.horizontal, BSSpacing.compact)
        .padding(.vertical, 8)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
    }

    private func add(_ name: String) {
        if show.addCompanion(name) {
            try? modelContext.save()
        }
        newName = ""
    }

    private func remove(_ name: String) {
        if editingName == name { editingName = nil }
        show.removeCompanion(name)
        try? modelContext.save()
    }

    private func commitRename(_ name: String) {
        show.renameCompanion(name, to: editingText)
        try? modelContext.save()
        editingName = nil
    }
}
