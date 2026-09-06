import SwiftUI

struct FootprintSetlistRecallSheet: View {
    @Bindable var coordinator: FootprintListeningCoordinator
    @State private var title = ""
    @State private var artist = ""
    @State private var surprising = false
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section(BSLocalization.text("现场听到了")) {
                    ForEach(coordinator.memories) { memory in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(coordinator.title(memory))
                                if memory.isMostSurprising { Label(BSLocalization.text("最惊喜"), systemImage: "sparkle").font(.caption) }
                            }
                            Spacer()
                            Menu {
                                Button(BSLocalization.text("设为最惊喜")) { coordinator.setSurprising(memory) }
                                Button(BSLocalization.text("删除回记"), role: .destructive) { coordinator.delete(memory) }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                .accessibilityLabel(BSLocalization.text("更多操作"))
                        }
                    }
                }
                Section(BSLocalization.text("手动填写")) {
                    TextField(BSLocalization.text("歌名"), text: $title)
                    TextField(BSLocalization.text("艺人名称"), text: $artist)
                    Toggle(BSLocalization.text("设为最惊喜"), isOn: $surprising)
                    Button(BSLocalization.text("添加")) {
                        coordinator.add(title: title, artist: artist, surprising: surprising)
                        if coordinator.error == nil { title = ""; artist = ""; surprising = false }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section(BSLocalization.text("选择歌曲")) {
                    TextField(BSLocalization.text("搜索歌曲"), text: $search)
                    ForEach(coordinator.catalogChoices.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { song in
                        Button { coordinator.add(songID: song.appleMusicSongID) } label: {
                            HStack {
                                VStack(alignment: .leading) { Text(song.title); Text(song.artistName).font(.caption) }
                                Spacer()
                                if coordinator.memories.contains(where: { $0.catalogSongID == song.appleMusicSongID }) { Image(systemName: "checkmark") }
                            }.frame(minHeight: 44)
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(BSColor.Stage.background)
                .navigationTitle(BSLocalization.text("回记现场歌曲"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(BSLocalization.text("完成")) { dismiss() } } }
                .alert(BSLocalization.text("保存失败，请重试"), isPresented: Binding(get: { coordinator.error != nil }, set: { if !$0 { coordinator.error = nil } })) {
                    Button(BSLocalization.text("好")) { coordinator.error = nil }
                }
        }.tint(BSColor.Stage.foreground)
    }
}
