import SwiftUI

// MARK: - 音频状态指示器组件
struct AudioStatusIndicator: View {
    @ObservedObject var playerService: PodcastPlayerService
    
    var body: some View {
        if playerService.audioPreparationState != .audioReady {
            HStack(spacing: 6) {
                switch playerService.audioPreparationState {
                case .preparing:
                    ProgressView()
                        .scaleEffect(0.7)
                case .failed:
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                default:
                    Image(systemName: "waveform.badge.exclamationmark")
                        .foregroundColor(.secondary)
                }
                
                Text(audioStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }
    
    private var audioStatusText: String {
        switch playerService.audioPreparationState {
        case .idle:
            return "待准备"
        case .preparing:
            return "准备中 \(Int(playerService.audioPreparationProgress * 100))%"
        case .audioReady:
            return "已就绪"
        case .failed(let error):
            return "准备失败: \(error.localizedDescription)"
        }
    }
}
