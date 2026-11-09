import SwiftUI

/// 右上角的星空菜单：音阶和星图。免费的是五声音阶和自由星空；其余带锁，非会员点了去付费页。
struct FootprintSkyMenu: View {
    let scale: FootprintSkyScale
    let shape: FootprintSkyShape
    let isPro: Bool
    let onScale: (FootprintSkyScale) -> Void
    let onShape: (FootprintSkyShape) -> Void
    let onLocked: () -> Void

    var body: some View {
        Menu {
            Section(BSLocalization.text("音阶")) {
                ForEach(FootprintSkyScale.allCases) { option in
                    item(option.title, isSelected: option == scale, isLocked: option.isPro && !isPro) { onScale(option) }
                }
            }
            Section(BSLocalization.text("星图")) {
                ForEach(FootprintSkyShape.allCases) { option in
                    item(option.title, isSelected: option == shape, isLocked: option.isPro && !isPro) { onShape(option) }
                }
            }
        } label: {
            Image(systemName: "sparkles")
        }
        .accessibilityLabel(BSLocalization.text("音阶和星图"))
    }

    private func item(_ title: String, isSelected: Bool, isLocked: Bool, select: @escaping () -> Void) -> some View {
        Button {
            isLocked ? onLocked() : select()
        } label: {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else if isLocked {
                Label(title, systemImage: "lock")
            } else {
                Text(title)
            }
        }
    }
}

/// 星空的读法和玩法，右上角 info 打开。
struct FootprintConstellationGuide: View {
    private let sections: [(title: String, lines: [String])] = [
        (BSLocalization.text("怎么看"), [
            BSLocalization.text("每颗星是一位看过的艺人，越亮看得越多"),
            BSLocalization.text("只看过一场的小星不写名字，点一下就能看到"),
            BSLocalization.text("连线：同一场演出里一起出现过"),
            BSLocalization.text("「某某座」：连在一起的一组，以最亮的星命名"),
            BSLocalization.text("背景里的小星点：其他艺人")
        ]),
        (BSLocalization.text("怎么玩"), [
            BSLocalization.text("点一颗星，看和这位艺人的现场"),
            BSLocalization.text("每颗星都是一个音，越往右越高"),
            BSLocalization.text("连着点几颗再停一下，会合成一个和弦"),
            BSLocalization.text("可以几根手指一起按"),
            BSLocalization.text("点右上角 ▶，星空会自己弹一首歌"),
            BSLocalization.text("点右上角 ✦ 换音阶和星图，每种音阶有自己的音色和歌")
        ])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                    ForEach(section.lines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(BSColor.Stage.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 280, alignment: .leading)
    }
}
