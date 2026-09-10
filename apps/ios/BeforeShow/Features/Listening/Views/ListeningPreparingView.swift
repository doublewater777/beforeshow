import SwiftUI

struct ListeningPreparingView: View {
    var body: some View {
        ZStack {
            FootprintBackground()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BSSpacing.lg) {
                        artistSelectorSkeleton
                        cabinetSkeleton
                        machineStageSkeleton
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.sm)
                    .padding(.bottom, BSLayout.tabBarContentInset)
                }
                .scrollDisabled(true)
            }
        }
        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
    }

    private var header: some View {
        HStack(spacing: BSSpacing.sm) {
            Text(BSLocalization.text("听"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .foregroundStyle(BSColor.Stage.foreground)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .frame(width: 86, height: 26)
        }
        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSLayout.pageHeaderTopPadding)
        .padding(.bottom, BSSpacing.sm)

    }

    private var artistSelectorSkeleton: some View {
        HStack(spacing: BSSpacing.compact) {
            ForEach(0..<5, id: \.self) { _ in
                VStack(spacing: 6) {
                    Circle()
                        .fill(BSColor.Stage.surfaceRaised)
                        .frame(width: 56, height: 56)
                        .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 40, height: 10)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, BSSpacing.xs)
    }

    private var cabinetSkeleton: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 120, height: 16)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 48, height: 18)
                Spacer()
            }
            HStack(spacing: BSSpacing.compact) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                                .stroke(BSColor.Stage.border, lineWidth: 1)
                        )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var machineStageSkeleton: some View {
        VStack(spacing: BSSpacing.md) {
            ZStack {
                Ellipse()
                    .fill(BSColor.Stage.accent.opacity(0.06))
                    .frame(height: 180)
                    .blur(radius: 40)
                Circle()
                    .stroke(BSColor.Stage.accent.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 170, height: 170)
                Circle()
                    .fill(BSColor.Stage.surfaceRaised)
                    .frame(width: 60, height: 60)
                    .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
                ProgressView()
                    .tint(BSColor.Stage.accent)
            }
            .frame(height: 200)

            Text(BSLocalization.text("正在准备唱片与曲目…"))
                .font(BSFont.caption)
                .foregroundStyle(BSColor.Stage.muted)
        }
    }
}
