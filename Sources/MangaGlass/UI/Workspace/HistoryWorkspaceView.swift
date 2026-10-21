import AppKit
import Foundation
import SwiftUI

struct HistoryWorkspaceView: View {
    @ObservedObject var vm: MainViewModel
    let openDownload: () -> Void
    @State private var showClearConfirmation = false

    private var records: [RecentComicRecord] {
        vm.recentRecords.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let latest = records.first {
                recentBanner(latest)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("书架").font(MGFont.pageTitle)
                Text("\(records.count) 部").font(MGFont.caption).foregroundStyle(.secondary)
                Spacer()
                Button("清空书架", role: .destructive) { showClearConfirmation = true }
                    .buttonStyle(MGActionButtonStyle(variant: .ghost))
                    .disabled(records.isEmpty)
            }

            if records.isEmpty {
                MGEmptyState(
                    title: "书架还是空的",
                    systemImage: "books.vertical",
                    detail: "在首页解析过的漫画会摆在这里，点一下就能回到它。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 168), spacing: 20, alignment: .top)],
                              alignment: .leading, spacing: 24) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            shelfItem(record)
                                .mgStaggerAppear(index: index * 2)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: records.map(\.id))
        .onAppear { MGRevealClock.mark() }
        .alert("清空书架？", isPresented: $showClearConfirmation) {
            Button("清空", role: .destructive) { vm.clearRecentRecords() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移除 \(records.count) 部最近打开的漫画，不会影响已经下载到本地的文件。")
        }
    }

    /// The most recently opened comic, presented like the chapter page banner.
    private func recentBanner(_ record: RecentComicRecord) -> some View {
        MGHeroBanner(coverURL: record.coverURL, height: 190) {
            HStack(alignment: .bottom, spacing: 20) {
                MGHeroCover(url: record.coverURL, title: record.title, width: 104)
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近打开 · \(relativeTime(record.updatedAt))")
                        .font(MGFont.captionStrong.weight(.semibold))
                        .opacity(0.75)
                    Text(record.title)
                        .font(MGFont.heroTitle)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        MGBannerStat(value: record.siteName, label: "来源")
                        MGBannerStat(value: "\(records.count)", label: "书架共")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("继续") {
                    vm.applyRecentRecord(record)
                    openDownload()
                }
                .buttonStyle(MGBannerButtonStyle(kind: .primary))
                .help("打开这部漫画")
            }
        }
    }

    private func shelfItem(_ record: RecentComicRecord) -> some View {
        Button {
            vm.applyRecentRecord(record)
            openDownload()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                MGBookCover(url: record.coverURL, title: record.title)
                    .aspectRatio(0.72, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .mgHoverLift()
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).font(MGFont.bodyStrong).lineLimit(2)
                    HStack(spacing: 4) {
                        Text(record.siteName)
                        Text("·")
                        Text(relativeTime(record.updatedAt)).help(absoluteTime(record.updatedAt))
                    }
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                    if CopyMangaMirror.isRetired(record.input) {
                        Text("站点已停用").font(MGFont.caption).foregroundStyle(MGTheme.danger)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(record.input)
        .contextMenu {
            Button("打开") {
                vm.applyRecentRecord(record)
                openDownload()
            }
            Button("复制链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.input, forType: .string)
            }
            Divider()
            Button("从书架移除", role: .destructive) { vm.removeRecentRecord(record) }
        }
        .accessibilityLabel("\(record.title)，\(record.siteName)")
        .accessibilityHint("打开这部漫画")
    }

    private static let relativeFormatter = RelativeDateTimeFormatter()

    private func relativeTime(_ date: Date) -> String {
        let now = Date()
        // Under a minute reads "刚刚"; the formatter would say "0 秒钟后".
        if now.timeIntervalSince(date) < 60 { return "刚刚" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    private func absoluteTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}
