import SwiftUI

// MARK: - 播放器字幕列表视图组件
struct PlayerSubtitleListView<RowView: View>: View {
    @ObservedObject var playerService: PodcastPlayerService
    let subtitles: [Subtitle]
    let rowBuilder: (Subtitle, Int, Bool) -> RowView
    
    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(spacing: 4) {
                ForEach(Array(subtitles.enumerated()), id: \.element.id) { index, subtitle in
                    rowBuilder(
                        subtitle,
                        index,
                        playerService.playbackState.currentSubtitleIndex == index
                    )
                    .id(index)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
            .onChange(of: playerService.playbackState.currentSubtitleIndex) { oldIndex, newIndex in
                if let index = newIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                    print("🎧 [SubtitleList] 字幕滚动：滚动到索引 \(index)")
                }
            }
            .onAppear {
                if let currentIndex = playerService.playbackState.currentSubtitleIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(currentIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}
