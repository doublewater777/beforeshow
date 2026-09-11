import Foundation
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Shared Show Draft Form

enum ShowDraftArtistAutoMatchPolicy {
    static func uniqueExactMatch(
        for query: String,
        among candidates: [RecognizedArtist]
    ) -> RecognizedArtist? {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return nil }
        let exact = candidates.filter { normalized($0.canonicalName) == normalizedQuery }
        let identities = Set(exact.map(\.id))
        guard identities.count == 1 else { return nil }
        return exact.first
    }

    static func normalized(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split { $0.isWhitespace || $0.isNewline }
        .joined(separator: " ")
    }
}

struct ShowDraftFormFields: View {
    @Binding var draft: ShowDraft
    /// 添加现场·识别导入（链接 / 截图）：识别出的字段标「✓ 已识别」薄荷绿描边。
    let recognizedHighlight: Bool
    /// 添加现场：无封面时显示虚线引导占位。
    let coverEmptyPlaceholder: Bool
    /// OCR 未识别日期（回退为今天）且未确认：日期瓷贴金色「待确认」并显示确认按钮。
    let requiresDateConfirmation: Bool
    let onConfirmFallbackDate: () -> Void
    let onCoverImported: (String, String) -> Void
    /// Apple Music 艺人搜索;可注入 Stub 跑测试。Phase 5 加。
    var artistSearch: any ArtistSearchServicing = AppleMusicArtistSearchService()
    /// 用户自上次 import 后手改过的字段;下次 import 会跳过这些字段,
    /// 防止 OCR / link 解析偷偷覆盖用户输入。
    @Binding var userEditedFields: Set<ShowDraftField>
    @State private var startTime: Date
    @State private var hasEndTime: Bool
    @State private var endDate: Date
    @State private var endTime: Date
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isImportingCover = false
    @State private var coverImportMessage: String?
    @State private var coverImportFailed = false
    @State private var showsLinkField = false

    /// 「已识别」标记只读字段级 provenance，不按字段是否有值推断。
    private var nameRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.name)
    }
    private var cityRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.city)
    }
    private var venueRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.venueName)
    }
    private var dateRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.date)
    }
    private var startTimeRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.startTime)
    }

    init(
        draft: Binding<ShowDraft>,
        recognizedHighlight: Bool = false,
        coverEmptyPlaceholder: Bool = false,
        requiresDateConfirmation: Bool = false,
        onConfirmFallbackDate: @escaping () -> Void = {},
        onCoverImported: @escaping (String, String) -> Void = { _, _ in },
        artistSearch: any ArtistSearchServicing = AppleMusicArtistSearchService(),
        userEditedFields: Binding<Set<ShowDraftField>>
    ) {
        let initialDraft = draft.wrappedValue
        let eventCalendar = initialDraft.timingCalendar()
        let fallbackStart = eventCalendar.date(
            bySettingHour: 20,
            minute: 0,
            second: 0,
            of: initialDraft.date
        ) ?? initialDraft.date
        let initialEndDate = initialDraft.endDate ?? initialDraft.date
        let fallbackEnd = initialDraft.endTimingCalendar().date(
            bySettingHour: 23,
            minute: 0,
            second: 0,
            of: initialEndDate
        ) ?? initialEndDate

        self._draft = draft
        self.recognizedHighlight = recognizedHighlight
        self.coverEmptyPlaceholder = coverEmptyPlaceholder
        self.requiresDateConfirmation = requiresDateConfirmation
        self.onConfirmFallbackDate = onConfirmFallbackDate
        self.onCoverImported = onCoverImported
        self.artistSearch = artistSearch
        self._userEditedFields = userEditedFields
        // Picker display state may use a fallback clock; draft.startTime stays nil until confirmed.
        _startTime = State(initialValue: initialDraft.startTime ?? fallbackStart)
        // End section covers both end clock and multi-day end date.
        _hasEndTime = State(initialValue: initialDraft.endTime != nil || initialDraft.endDate != nil)
        _endDate = State(initialValue: initialEndDate)
        _endTime = State(initialValue: initialDraft.endTime ?? fallbackEnd)
    }

    var body: some View {
        formCards
        .environment(\.calendar, draft.timingCalendar())
        .environment(\.timeZone, draft.timingCalendar().timeZone)
        .onChange(of: hasEndTime) { _, newValue in
            syncEndTimeToDraft(isEnabled: newValue)
        }
        .onChange(of: startTime) { _, _ in
            // Only write committed start times; unconfirmed picker value stays local.
            if draft.startTime != nil {
                draft.startTime = mergedStartTime()
            }
            if hasEndTime {
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: endTime) { _, _ in
            if hasEndTime {
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: endDate) { _, _ in
            if hasEndTime {
                let startDay = draft.timingCalendar().startOfDay(for: draft.date)
                if draft.endTimingCalendar().startOfDay(for: endDate) < startDay {
                    endDate = startDay
                }
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: draft.date) { _, _ in
            if draft.startTime != nil {
                draft.startTime = mergedStartTime()
            }
            if hasEndTime {
                let startDay = draft.timingCalendar().startOfDay(for: draft.date)
                if draft.endTimingCalendar().startOfDay(for: endDate) < startDay {
                    endDate = startDay
                }
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: selectedCoverItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importCover(from: newItem)
            }
        }
        // Imported lineup names are enriched before the user ever reaches Listen.
        // This is best-effort and invisible: only one unambiguous exact match is
        // accepted, and any user edit immediately stops automatic matching.
        .task(id: artistAutoMatchKey) {
            await autoMatchRecognizedArtists()
        }
    }

    /// 四张卡片布局（Stage 色板，与首页 V4 / 现场状态卡同一语言）。
    private var formCards: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditShowFormCard(title: BSLocalization.text("基本信息"), icon: "square.and.pencil", tint: BSColor.Stage.accent) {
                AddShowLabeledTextField(
                    title: BSLocalization.text("现场名称"),
                    placeholder: BSLocalization.text("例：五月天上海演唱会"),
                    text: $draft.name,
                    isRequired: true,
                    isRecognized: nameRecognized
                )
                .onChange(of: draft.name) { _, _ in
                    userEditedFields.insert(.name)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("艺人 / 阵容")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(BSColor.textSecondary)
                        Spacer()
                        if artistRowRecognized {
                            Label("已识别", systemImage: "checkmark.seal.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(BSColor.Accent.prepare)
                        }
                    }
                    ForEach(Array(draft.artists.enumerated()), id: \.offset) { index, _ in
                        ArtistInputRow(
                            index: index,
                            name: Binding(
                                get: { draft.artists[safe: index]?.name ?? "" },
                                set: { newValue in
                                    ensureArtistSlot(at: index)
                                    draft.artists[index].name = newValue
                                }
                            ),
                            avatar: Binding(
                                get: { draft.artists[safe: index]?.avatarURL ?? nil },
                                set: { newValue in
                                    ensureArtistSlot(at: index)
                                    draft.artists[index].avatarURL = newValue
                                }
                            ),
                            artistSearch: artistSearch,
                            canDelete: draft.artists.count > 1,
                            onPick: { recognition in
                                ensureArtistSlot(at: index)
                                draft.artists[index].name = recognition.canonicalName
                                draft.artists[index].avatarURL = recognition.avatarURL?.absoluteString
                                draft.artists[index].appleMusicURL = recognition.appleMusicURL?.absoluteString
                                draft.artists[index].appleMusicArtistID = recognition.id
                                draft.recognizedFields.remove(.artist)
                            },
                            onDelete: { removeArtistRow(at: index) },
                            onTextChange: { userEditedFields.insert(.artist) }
                        )
                    }
                    Button {
                        draft.artists.append(ArtistSlot(name: "", avatarURL: nil))
                    } label: {
                        Label("+ 新增艺人", systemImage: "plus.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(BSColor.Accent.violet)
                    }
                    .buttonStyle(.plain)
                }
                .onAppear {
                    if draft.artists.isEmpty {
                        draft.artists = [ArtistSlot(name: "", avatarURL: nil)]
                    }
                    Task { await artistSearch.requestAuthorizationIfNeeded() }
                }
            }

            EditShowFormCard(
                title: BSLocalization.text("日期与时间"),
                icon: "clock",
                tint: BSColor.Accent.violet
            ) {
                AddShowScheduleFields(
                    draft: $draft,
                    startTime: $startTime,
                    isStartTimeConfirmed: draft.startTime != nil,
                    onConfirmStartTime: {
                        draft.startTime = mergedStartTime()
                        userEditedFields.insert(.startTime)
                    },
                    hasEndTime: $hasEndTime,
                    endDate: $endDate,
                    endTime: $endTime,
                    dateRecognized: dateRecognized,
                    dateNeeded: requiresDateConfirmation,
                    startTimeRecognized: startTimeRecognized,
                    onConfirmFallbackDate: onConfirmFallbackDate
                )
                .onChange(of: draft.date) { _, _ in
                    userEditedFields.insert(.date)
                }

                if draft.startTime != nil && !draft.hasValidEndTime() {
                    Label("结束时间需要晚于开始时间", systemImage: "exclamationmark.circle.fill")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Accent.danger)
                        .accessibilityLabel("时间范围无效，结束时间需要晚于开始时间")
                }
            }

            EditShowFormCard(title: BSLocalization.text("地点"), icon: "mappin.and.ellipse", tint: BSColor.Accent.prepare) {
                AddShowLabeledTextField(
                    title: BSLocalization.text("城市"),
                    placeholder: BSLocalization.text("上海"),
                    text: $draft.city,
                    isRecognized: cityRecognized
                )
                .onChange(of: draft.city) { _, _ in
                    userEditedFields.insert(.city)
                }

                BSVenueField(
                    venueName: $draft.venueName,
                    venueAddress: $draft.venueAddress,
                    city: draft.city,
                    isRecognized: venueRecognized
                )
                .onChange(of: draft.venueName) { _, _ in
                    userEditedFields.insert(.venueName)
                }
            }

            EditShowFormCard(
                title: BSLocalization.text("封面"),
                icon: "photo",
                tint: BSColor.Stage.accent
            ) {
                if !draft.coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ShowDraftCoverPreview(urlString: draft.coverImageURL)
                } else if coverEmptyPlaceholder {
                    HStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(BSColor.Accent.violet)
                        Text("还没加封面")
                            .font(.system(size: 12.5))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .background(Color.white.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                Color.white.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                            )
                    )
                }

                AddShowCoverActions(
                    selectedItem: $selectedCoverItem,
                    showsLinkField: $showsLinkField,
                    isImporting: isImportingCover,
                    message: coverImportMessage,
                    messageIsError: coverImportFailed
                )

                if showsLinkField {
                    AddShowLabeledTextField(
                        title: BSLocalization.text("图片链接"),
                        placeholder: "https://...",
                        text: $draft.coverImageURL,
                        keyboardType: .URL
                    )
                }
            }
        }
    }

    private var artistAutoMatchKey: String {
        guard recognizedHighlight,
              draft.recognizedFields.contains(.artist),
              !userEditedFields.contains(.artist) else {
            return "disabled"
        }
        return draft.artists
            .map { "\($0.name)|\($0.appleMusicArtistID ?? "")" }
            .joined(separator: "\u{1F}")
    }

    @MainActor
    private func autoMatchRecognizedArtists() async {
        guard recognizedHighlight,
              draft.recognizedFields.contains(.artist),
              !userEditedFields.contains(.artist) else { return }

        let importedArtists = draft.artists
        for (index, imported) in importedArtists.enumerated() where imported.appleMusicArtistID == nil {
            guard !Task.isCancelled, !userEditedFields.contains(.artist) else { return }
            let query = imported.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { continue }

            let candidates = (try? await artistSearch.searchArtists(query: query)) ?? []
            guard !Task.isCancelled, !userEditedFields.contains(.artist) else { return }
            guard let match = ShowDraftArtistAutoMatchPolicy.uniqueExactMatch(for: query, among: candidates),
                  draft.artists.indices.contains(index),
                  draft.artists[index].appleMusicArtistID == nil,
                  ShowDraftArtistAutoMatchPolicy.normalized(draft.artists[index].name)
                    == ShowDraftArtistAutoMatchPolicy.normalized(imported.name) else {
                continue
            }

            // Identity enrichment must not rewrite the imported/user-visible name.
            draft.artists[index].appleMusicArtistID = match.id
            draft.artists[index].appleMusicURL = match.appleMusicURL?.absoluteString
            if draft.artists[index].avatarURL == nil {
                draft.artists[index].avatarURL = match.avatarURL?.absoluteString
            }
        }
    }

    private func mergedStartTime() -> Date {
        draft.mergedTime(startTime, into: draft.date, calendar: draft.timingCalendar())
    }

    private func syncEndTimeToDraft(isEnabled: Bool) {
        guard isEnabled else {
            draft.endDate = nil
            draft.endTime = nil
            return
        }

        let resolvedEndDay = max(
            draft.endTimingCalendar().startOfDay(for: endDate),
            draft.timingCalendar().startOfDay(for: draft.date)
        )
        endDate = resolvedEndDay
        draft.endDate = resolvedEndDay
        draft.endTime = draft.mergedTime(
            endTime,
            into: resolvedEndDay,
            calendar: draft.endTimingCalendar()
        )
    }

    @MainActor
    private func ensureArtistSlot(at index: Int) {
        if draft.artists.count <= index {
            while draft.artists.count <= index {
                draft.artists.append(ArtistSlot(name: "", avatarURL: nil))
            }
        }
    }

    @MainActor
    private func removeArtistRow(at index: Int) {
        guard draft.artists.indices.contains(index) else { return }
        draft.artists.remove(at: index)
        if draft.artists.isEmpty {
            draft.artists.append(ArtistSlot(name: "", avatarURL: nil))
        }
    }

    private var artistRowRecognized: Bool {
        recognizedHighlight
            && draft.recognizedFields.contains(.artist)
            && draft.artists.contains { $0.avatarURL != nil }
    }

    @MainActor
    private func importCover(from item: PhotosPickerItem) async {
        isImportingCover = true
        coverImportMessage = nil
        coverImportFailed = false
        defer {
            isImportingCover = false
            selectedCoverItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpegData = image.jpegData(compressionQuality: 0.86) else {
                coverImportMessage = BSLocalization.text("没有读到这张图片")
                coverImportFailed = true
                return
            }

            let directory = try ShowCoverLocalImageStore.directory()
            let fileURL = directory.appendingPathComponent("\(UUID().uuidString).jpg")
            try jpegData.write(to: fileURL, options: [.atomic])
            let previousURL = draft.coverImageURL
            draft.coverImageURL = fileURL.absoluteString
            onCoverImported(previousURL, draft.coverImageURL)
            coverImportMessage = BSLocalization.text("已换成本地封面")
        } catch {
            coverImportMessage = BSLocalization.text("封面图导入失败")
            coverImportFailed = true
        }
    }
}


private extension Array {
    /// 越界返回 nil,form 写入路径用,避免每次 append 后都要判 range。
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
