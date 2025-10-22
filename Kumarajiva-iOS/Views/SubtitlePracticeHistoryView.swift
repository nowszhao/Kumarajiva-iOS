import SwiftUI
import AVFoundation

/// 字幕练习历史视图
struct SubtitlePracticeHistoryView: View {
    let records: [SubtitlePracticeRecord]
    let onDelete: (UUID) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var playingRecordID: UUID?
    @State private var audioPlayer: AVAudioPlayer?
    
    var body: some View {
        NavigationView {
            Group {
                if records.isEmpty {
                    emptyStateView
                } else {
                    recordsList
                }
            }
            .navigationTitle("练习历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        stopPlayback()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            stopPlayback()
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("暂无练习记录")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Records List
    private var recordsList: some View {
        List {
            ForEach(records) { record in
                PracticeRecordRow(
                    record: record,
                    isPlaying: playingRecordID == record.id,
                    onPlay: {
                        if playingRecordID == record.id {
                            stopPlayback()
                        } else {
                            playRecording(record)
                        }
                    }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        onDelete(record.id)
                        if playingRecordID == record.id {
                            stopPlayback()
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Playback Control
    private func playRecording(_ record: SubtitlePracticeRecord) {
        stopPlayback()
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: record.audioURL)
            audioPlayer?.delegate = PlaybackDelegate(onFinish: {
                playingRecordID = nil
            })
            audioPlayer?.play()
            playingRecordID = record.id
        } catch {
            print("播放失败: \(error)")
        }
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingRecordID = nil
    }
}

/// 练习记录行视图
struct PracticeRecordRow: View {
    let record: SubtitlePracticeRecord
    let isPlaying: Bool
    let onPlay: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 时间和分数
            HStack {
                Text(formatDate(record.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                scoreBadge(score: record.score)
            }
            
            // 字幕文本
            Text(record.subtitleText)
                .font(.system(size: 15))
                .lineLimit(2)
            
            // 识别结果
            if !record.recognizedText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("识别结果:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(record.recognizedText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            // 单词匹配结果
            if !record.wordMatchResults.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(record.wordMatchResults.indices, id: \.self) { index in
                        let match = record.wordMatchResults[index]
                        Text(match.originalWord)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(match.isMatch ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 播放按钮
            Button(action: onPlay) {
                HStack {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    Text(isPlaying ? "停止播放" : "播放录音")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func scoreBadge(score: Int) -> some View {
        Text("\(score)")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(scoreColor(for: score))
            .cornerRadius(12)
    }
    
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 90...100: return .green
        case 70..<90: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// AVAudioPlayer Delegate
class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
