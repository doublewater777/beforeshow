import SwiftUI
import UIKit

/// No timetable yet: an empty stage waiting for its schedule.
struct TimetableEmptyStateView: View {
    let errorMessage: String?
    let onPickPhotos: () -> Void

    @State private var breathe = false

    private struct Ghost: Identifiable {
        let id: Int
        let top: CGFloat
        let height: CGFloat
        var isMine = false
    }

    private let lanes: [[Ghost]] = [
        [.init(id: 0, top: 44, height: 58), .init(id: 1, top: 110, height: 92), .init(id: 2, top: 210, height: 70)],
        [.init(id: 3, top: 66, height: 76), .init(id: 4, top: 150, height: 52, isMine: true), .init(id: 5, top: 210, height: 96)],
        [.init(id: 6, top: 38, height: 66), .init(id: 7, top: 112, height: 58), .init(id: 8, top: 178, height: 80)]
    ]

    var body: some View {
        VStack(spacing: 0) {
            stage
                .padding(.top, 28)

            Text(BSLocalization.text("添加时刻表"))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(TimetableStyle.foreground)
                .padding(.top, 20)
            Text(BSLocalization.text("支持多张截图 · 多日 · 多舞台"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TimetableStyle.muted)
                .padding(.top, 10)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TimetableStyle.attention)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(TimetableStyle.attention.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
            }

            Spacer(minLength: 24)

            Button(action: onPickPhotos) {
                Label(BSLocalization.text("从相册选择"), systemImage: "photo")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(TimetableStyle.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(TimetableStyle.foreground))
            }
            .buttonStyle(TimetablePressStyle())
            .padding(.horizontal, 24)

            TimetableOnDeviceNote()
                .padding(.top, 14)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            RadialGradient(colors: [Color(red: 1, green: 0.925, blue: 0.8).opacity(0.13), .clear], center: .center, startRadius: 0, endRadius: 260)
                .frame(width: 520, height: 420)
                .offset(y: -40)
                .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    private var stage: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(lanes.indices, id: \.self) { index in
                ZStack(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                        .fill(TimetableStyle.lane)
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 38, height: 6)
                        .padding(.top, 15)
                    ForEach(lanes[index]) { ghost in
                        ghostCard(ghost)
                            .opacity(breathe == (ghost.id % 2 == 0) ? 1 : 0.55)
                    }
                }
                .frame(width: 96, height: 330)
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }

    private func ghostCard(_ ghost: Ghost) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(ghost.isMine ? TimetableStyle.cardMine : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(ghost.isMine ? TimetableStyle.mine.opacity(0.28) : Color.white.opacity(0.09), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.07)).frame(width: 40, height: 6).padding(.top, 12).padding(.leading, 9)
            }
            .overlay(alignment: .topTrailing) {
                if ghost.isMine {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(TimetableStyle.mine.opacity(0.7))
                        .padding(8)
                }
            }
            .frame(height: ghost.height)
            .offset(y: ghost.top)
    }
}

/// Recognition in progress: the picked screenshot with a scanning light passing over it.
struct TimetableRecognizingView: View {
    let image: UIImage?
    let imageCount: Int

    @State private var sweep = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if imageCount > 1 {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08)))
                        .frame(width: 260, height: 347)
                        .rotationEffect(.degrees(5))
                        .offset(x: 16, y: -10)
                }
                photo
            }
            .padding(.top, 70)

            Text(BSLocalization.text("识别中"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(TimetableStyle.foreground)
                .padding(.top, 48)

            Spacer()
            TimetableOnDeviceNote()
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            RadialGradient(colors: [TimetableStyle.mine.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 280)
                .frame(width: 560, height: 520)
                .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { sweep = true }
        }
    }

    private var photo: some View {
        ZStack(alignment: .top) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.05)
            }
            LinearGradient(colors: [.clear, Color(red: 1, green: 0.925, blue: 0.8).opacity(0.16)], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(red: 1, green: 0.945, blue: 0.855))
                        .frame(height: 2)
                        .shadow(color: TimetableStyle.mine.opacity(0.8), radius: 6)
                }
                .offset(y: sweep ? 347 : -70)
        }
        .frame(width: 260, height: 347)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12)))
        .overlay(alignment: .bottomTrailing) {
            if imageCount > 1 {
                Text("1/\(imageCount)")
                    .font(TimetableStyle.mono(11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(8)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 30, y: 30)
    }
}
