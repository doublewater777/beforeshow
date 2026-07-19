import SwiftUI

// MARK: - Tokens (index.html :root + setlist CSS)

enum SetlistProto {
    static let bg = Color(red: 0.020, green: 0.027, blue: 0.051) // #05070d
    static let surface = Color(red: 0.051, green: 0.067, blue: 0.106) // #0d111b
    static let surfaceRaised = Color(red: 0.082, green: 0.102, blue: 0.153) // #151a27
    static let fg = Color(red: 0.949, green: 0.953, blue: 0.969) // #f2f3f7
    static let muted = Color(red: 0.576, green: 0.600, blue: 0.667) // #9399aa
    static let dim = Color(red: 0.392, green: 0.420, blue: 0.490) // #646b7d
    static let accent = Color(red: 0.910, green: 0.780, blue: 0.557) // #e8c78e
    static let stageBlue = Color(red: 0.322, green: 0.498, blue: 0.788) // #527fc9
    static let stageViolet = Color(red: 0.482, green: 0.404, blue: 0.561) // #7b678f
    static let danger = Color(red: 0.851, green: 0.537, blue: 0.569) // #d98991
    static let inkOnAccent = Color(red: 0.078, green: 0.063, blue: 0.039) // #14100a

    static func tierDot(_ tier: SongTier) -> some View {
        Group {
            switch tier {
            case .high:
                Circle().fill(accent)
            case .mid:
                Circle().fill(stageViolet.opacity(0.95))
            case .encore:
                Circle().fill(stageBlue.opacity(0.95))
            case .guest:
                Circle().fill(
                    LinearGradient(
                        colors: [accent, stageViolet],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
        .frame(width: 8, height: 8)
    }

    /// index.html `SETLIST_TIER_LABEL` display copy (not glossary short names).
    static func tierLabel(_ tier: SongTier) -> String {
        switch tier {
        case .high: return "高概率"
        case .mid: return "可能"
        case .guest: return "嘉宾曲目"
        case .encore: return "安可猜测"
        }
    }

    static func tierLabelColor(_ tier: SongTier) -> Color {
        tier == .high ? accent : muted
    }
}

// MARK: - Track row (prototype .track grid)

struct SetlistProtoTrackRow: View {
    let song: CandidateSong
    var bare: Bool = false
    var isEditing: Bool = false
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    /// When true (festival home preview), prefer artist over short hint for side text.
    var preferArtistSide: Bool = false
    var sideText: String? = nil
    var revealDelay: Double = 0
    var reveal: Bool = false
    var onToggleMostWanted: (() -> Void)? = nil
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var revealed = false

    var body: some View {
        HStack(spacing: 10) {
            // grid: 12px | name | meta | acts
            SetlistProto.tierDot(song.tier)
                .frame(width: 12, alignment: .center)

            Text(song.songName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(SetlistProto.fg)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !isEditing {
                // `.track-meta`: likelihood + side (seg / guest · artist)
                HStack(spacing: 8) {
                    Text(SetlistProto.tierLabel(song.tier))
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.22)
                        .foregroundColor(SetlistProto.tierLabelColor(song.tier))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let side = displaySide, !side.isEmpty {
                        Text(side)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(SetlistProto.dim)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }
                .layoutPriority(1)
            }

            if bare {
                EmptyView()
            } else if isEditing {
                HStack(spacing: 2) {
                    protoAct(system: "arrow.up", enabled: canMoveUp, action: onMoveUp)
                    protoAct(system: "arrow.down", enabled: canMoveDown, action: onMoveDown)
                    protoAct(system: "xmark", enabled: true, danger: true, action: onDelete)
                }
            } else if let onToggleMostWanted {
                Button(action: onToggleMostWanted) {
                    Image(systemName: song.isMostWanted ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(song.isMostWanted ? SetlistProto.accent : SetlistProto.dim)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(song.isMostWanted ? "取消最想看 \(song.songName)" : "最想看 \(song.songName)")
            }
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
        .opacity(reveal ? (revealed ? 1 : 0) : 1)
        .offset(y: reveal ? (revealed ? 0 : 10) : 0)
        .onAppear {
            guard reveal else { return }
            withAnimation(.easeOut(duration: 0.7).delay(revealDelay)) {
                revealed = true
            }
        }
        .onChange(of: reveal) { _, on in
            if on {
                revealed = false
                withAnimation(.easeOut(duration: 0.7).delay(revealDelay)) {
                    revealed = true
                }
            } else {
                revealed = true
            }
        }
    }

    private var displaySide: String? {
        // Prototype trackRowHtml side priority
        if preferArtistSide, !song.artist.isEmpty {
            return song.artist
        }
        if song.tier == .guest, !song.artist.isEmpty {
            return "嘉宾 · \(song.artist)"
        }
        if let hint = song.shortHint, !hint.isEmpty { return hint }
        if let sideText, !sideText.isEmpty { return sideText }
        return nil
    }

    private func protoAct(
        system: String,
        enabled: Bool,
        danger: Bool = false,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(
                    enabled
                        ? (danger ? SetlistProto.danger : SetlistProto.dim)
                        : SetlistProto.dim.opacity(0.35)
                )
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || action == nil)
    }
}

// MARK: - Artist group header (festival sheet)

struct SetlistProtoArtistGroupHeader: View {
    let name: String
    let count: Int
    var isFirst: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.26)
                .foregroundColor(SetlistProto.fg)
            Spacer(minLength: 0)
            Text("歌单猜想 · \(count) 首")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(SetlistProto.dim)
        }
        .padding(.horizontal, 2)
        // Prototype `.track-group:first-child { padding-top: 2px }`
        .padding(.top, isFirst ? 2 : 16)
        .padding(.bottom, 4)
    }
}

// MARK: - Festival artist chips (mrnv1rxl `.artist-chip`)

struct FlowArtistChips: View {
    let artists: [String]
    @Binding var selected: String

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(artists, id: \.self) { name in
                chip(name)
            }
        }
    }

    private func chip(_ name: String) -> some View {
        let on = selected == name
        return Button {
            selected = name
        } label: {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundColor(on ? SetlistProto.accent : SetlistProto.muted)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(on ? SetlistProto.accent.opacity(0.10) : Color.clear)
                )
                .overlay(
                    Capsule().stroke(
                        on ? SetlistProto.accent.opacity(0.55) : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Open-all row (.track-open)

struct SetlistProtoOpenAllRow: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SetlistProto.muted)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SetlistProto.dim)
            }
            .padding(.horizontal, 2)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }
}

// MARK: - Footer chip (.gen-again)

struct SetlistProtoChip: View {
    let title: String
    var isPrimary: Bool = false
    var isLoading: Bool = false
    /// When false, chip hugs content (prototype `.gen-again`); when true, fills grid cell.
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(isPrimary ? SetlistProto.inkOnAccent : SetlistProto.muted)
                }
                Text(title)
                    .font(.system(size: isPrimary ? 13 : 11, weight: isPrimary ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isPrimary ? SetlistProto.inkOnAccent : SetlistProto.muted)
            .padding(.horizontal, isPrimary ? 16 : 14)
            .frame(minHeight: isPrimary ? 42 : 34)
            .frame(maxWidth: expands ? .infinity : nil)
            .background(
                Capsule().fill(isPrimary ? SetlistProto.accent : Color.clear)
            )
            .overlay(
                Capsule().stroke(
                    isPrimary ? Color.clear : Color.white.opacity(0.12),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Primary CTA (.primary-action, empty card)

struct SetlistProtoPrimaryCTA: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(SetlistProto.bg)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Capsule().fill(SetlistProto.accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Sheet chrome (handle + head + close)

struct SetlistProtoSheetHeader: View {
    let title: String
    let note: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.16))
                .frame(width: 44, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(SetlistProto.fg)
                    Text(note)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(SetlistProto.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
        }
    }
}

// MARK: - Gen status

struct SetlistProtoGenStatus: View {
    let text: String
    var reduceMotion: Bool = false

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(SetlistProto.accent)
                .frame(width: 6, height: 6)
                .opacity(reduceMotion ? 0.7 : 1)
                .modifier(SetlistProtoPulse(enabled: !reduceMotion))
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(SetlistProto.muted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
    }
}

private struct SetlistProtoPulse: ViewModifier {
    let enabled: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .opacity(on ? 1 : 0.3)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                        on = true
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Share card (prototype .share-card)

struct SetlistProtoShareCard: View {
    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let artist: String?
        let isMostWanted: Bool
    }

    let title: String
    let meta: String
    let rows: [Row]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.043, green: 0.063, blue: 0.110),
                    Color(red: 0.027, green: 0.039, blue: 0.071)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // glows
            Ellipse()
                .fill(SetlistProto.accent.opacity(0.20))
                .frame(width: 320, height: 140)
                .blur(radius: 28)
                .offset(y: -150)
            Ellipse()
                .fill(SetlistProto.stageBlue.opacity(0.20))
                .frame(width: 200, height: 140)
                .blur(radius: 30)
                .offset(x: -90, y: 140)
            Ellipse()
                .fill(SetlistProto.stageViolet.opacity(0.18))
                .frame(width: 180, height: 120)
                .blur(radius: 28)
                .offset(x: 100, y: 100)

            VStack(alignment: .leading, spacing: 0) {
                Text("歌单猜想 · SETLIST GUESS · 非官方")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundColor(SetlistProto.accent)
                    .padding(.bottom, 10)

                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(SetlistProto.fg)
                    .lineLimit(3)

                Text(meta)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(SetlistProto.muted)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundColor(SetlistProto.dim)
                                .frame(width: 18, alignment: .leading)
                            HStack(spacing: 0) {
                                Text(row.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(SetlistProto.fg)
                                    .lineLimit(1)
                                if let artist = row.artist, !artist.isEmpty {
                                    Text(" · \(artist)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(SetlistProto.muted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            if row.isMostWanted {
                                Text("最想看")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(SetlistProto.accent)
                            }
                        }
                    }
                }
                .padding(.top, 14)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
                .padding(.top, 16)

                Spacer(minLength: 12)

                HStack {
                    Text("BeforeShow · 开场前")
                    Spacer()
                    Text("非官方 · 灯亮之前，先进入状态。")
                }
                .font(.system(size: 11, weight: .regular))
                .tracking(0.3)
                .foregroundColor(SetlistProto.dim)
                .padding(.top, 12)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Share action buttons (.share-actions grid)

struct SetlistProtoShareActions: View {
    let onCopy: () -> Void
    let onSave: () -> Void
    let isSaving: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                shareBtn("复制文本", accent: false, action: onCopy)
                shareBtn(isSaving ? "保存中…" : "保存海报", accent: true, action: onSave)
                    .disabled(isSaving)
            }
        }
    }

    private func shareBtn(
        _ title: String,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent ? SetlistProto.accent : SetlistProto.fg)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(
                    Capsule().fill(
                        accent
                            ? SetlistProto.accent.opacity(0.14)
                            : Color.white.opacity(0.06)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        accent
                            ? SetlistProto.accent.opacity(0.35)
                            : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}
