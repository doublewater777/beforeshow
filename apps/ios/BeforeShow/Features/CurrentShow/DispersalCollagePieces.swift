import SwiftUI
import UIKit

/// 散场记忆的拼贴物件:拍立得海报、邮戳、杂志日期栏、手绘圈与横线信纸。
/// 散场短评(暗场)与散场卡(纸本)共用,颜色由调用方给。

struct DispersalPolaroid: View {
    let coverURL: String?
    var ambient: Color? = nil
    let imageWidth: CGFloat
    var cornerColor: Color = BSColor.Stage.surfaceRaised

    private var imageHeight: CGFloat { imageWidth * 4 / 3 }

    var body: some View {
        ZStack {
            BSColor.Stage.surfaceRaised
            if let ambient {
                ambient.opacity(0.35)
            }
            ShowCoverImageView(
                urlString: coverURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                enforcesAspectRatio: true,
                cornerRadius: 0,
                restoresPersistedImageOnFirstFrame: true
            )
        }
        .frame(width: imageWidth, height: imageHeight)
        .clipped()
        .padding([.top, .horizontal], imageWidth * 0.058)
        .padding(.bottom, imageWidth * 0.16)
        .background(BSColor.Paper.photoFrame)
        .overlay { corners }
        .accessibilityHidden(true)
    }

    private var corners: some View {
        let size = imageWidth * 0.13
        return ZStack {
            PhotoCorner().fill(cornerColor).frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            PhotoCorner().fill(cornerColor).frame(width: size, height: size).rotationEffect(.degrees(90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            PhotoCorner().fill(cornerColor).frame(width: size, height: size).rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            PhotoCorner().fill(cornerColor).frame(width: size, height: size).rotationEffect(.degrees(270))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(-imageWidth * 0.026)
    }
}

/// 左上直角三角,旋转后用作四个相角。
private struct PhotoCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct DispersalPostmark: View {
    let city: String?
    let date: String
    let ink: Color
    /// 文字底色,挡住邮戳波纹。
    let knockout: Color
    var diameter: CGFloat = 84

    var body: some View {
        ZStack {
            Circle().stroke(ink, lineWidth: 1.4)
            Circle().stroke(ink, lineWidth: 1.4).padding(diameter * 0.095)
            PostmarkWaves()
                .stroke(ink, lineWidth: 1)
                .frame(width: diameter * 1.3, height: diameter * 0.15)
            VStack(spacing: 1) {
                if let city {
                    Text(verbatim: city)
                        .font(BSFont.Editorial.song(size: diameter * 0.18, weight: .black))
                        .tracking(2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 2)
                        .background(knockout)
                }
                Text(verbatim: date)
                    .font(BSFont.Editorial.numerals(size: diameter * 0.11))
                    .tracking(1)
                    .padding(.horizontal, 2)
                    .background(knockout)
            }
            .foregroundStyle(ink)
            .frame(width: diameter * 0.7)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// 邮戳两道横向波纹。
private struct PostmarkWaves: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for y in [rect.minY, rect.maxY] {
            path.move(to: CGPoint(x: rect.minX, y: y))
            let step = rect.width / 6
            for index in 0..<6 {
                let x = rect.minX + step * CGFloat(index)
                path.addQuadCurve(
                    to: CGPoint(x: x + step, y: y),
                    control: CGPoint(x: x + step / 2, y: y + (index.isMultiple(of: 2) ? -3 : 3))
                )
            }
        }
        return path
    }
}

/// 「11 / 02 / 2026 · 周一」杂志日期栏。
struct DispersalDateColumn: View {
    let stamp: DispersalCeremonyCardCopy.DateStamp
    let caption: String
    let numeralSize: CGFloat
    let color: Color
    let captionColor: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: stamp.month)
                .font(BSFont.Editorial.numerals(size: numeralSize))
            Rectangle()
                .fill(color.opacity(0.5))
                .frame(width: numeralSize * 0.74, height: 1)
                .padding(.vertical, numeralSize * 0.1)
            Text(verbatim: stamp.day)
                .font(BSFont.Editorial.numerals(size: numeralSize))
            Text(verbatim: caption)
                .font(BSFont.V3.caption)
                .tracking(BSFont.Editorial.kickerTracking)
                .foregroundStyle(captionColor)
                .padding(.top, numeralSize * 0.12)
        }
        .foregroundStyle(color)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

/// 选中评级外的一圈手绘椭圆。
struct DispersalHandCircle: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.11, y: rect.minY + h * 0.55))
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.58, y: rect.minY + h * 0.12),
            control1: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.25),
            control2: CGPoint(x: rect.minX + w * 0.36, y: rect.minY + h * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.89, y: rect.minY + h * 0.6),
            control1: CGPoint(x: rect.minX + w * 0.8, y: rect.minY + h * 0.14),
            control2: CGPoint(x: rect.minX + w * 0.95, y: rect.minY + h * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.3, y: rect.minY + h * 0.88),
            control1: CGPoint(x: rect.minX + w * 0.83, y: rect.minY + h * 0.86),
            control2: CGPoint(x: rect.minX + w * 0.55, y: rect.minY + h * 0.92)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.17, y: rect.minY + h * 0.38),
            control1: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.84),
            control2: CGPoint(x: rect.minX + w * 0.05, y: rect.minY + h * 0.6)
        )
        return path
    }
}

/// 宋体横线信纸:横线跟着文字行高走。
struct DispersalRuledNoteField: View {
    @Binding var text: String
    let placeholder: String
    let ink: Color
    let ruleColor: Color
    var focus: FocusState<Bool>.Binding

    private static let fontSize: CGFloat = 16
    private static let lineSpacing: CGFloat = 10
    private static let minimumLines = 3

    private static var lineHeight: CGFloat {
        let font = UIFont(name: BSFont.Editorial.SongWeight.regular.postScriptName, size: fontSize)
            ?? .systemFont(ofSize: fontSize)
        return font.lineHeight + lineSpacing
    }

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(Self.minimumLines...8)
            .lineSpacing(Self.lineSpacing)
            .font(BSFont.Editorial.song(size: Self.fontSize))
            .foregroundStyle(ink)
            .tint(BSColor.Stage.accent)
            .focused(focus)
            .padding(.top, Self.lineSpacing / 2)
            .frame(minHeight: Self.lineHeight * CGFloat(Self.minimumLines), alignment: .top)
            .background(alignment: .top) {
                Canvas { context, size in
                    var y = Self.lineHeight
                    while y <= size.height + 0.5 {
                        context.fill(Path(CGRect(x: 0, y: y - 1, width: size.width, height: 1)), with: .color(ruleColor))
                        y += Self.lineHeight
                    }
                }
                .accessibilityHidden(true)
            }
    }
}
