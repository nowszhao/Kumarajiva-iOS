import SwiftUI

// MARK: - 播放器进度条组件
struct PlayerProgressView: View {
    @ObservedObject var playerService: PodcastPlayerService
    @Binding var isSeeking: Bool
    @Binding var seekDebounceTimer: Timer?
    let isAudioReady: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            // 可拖动的进度条
            Slider(
                value: Binding(
                    get: {
                        guard playerService.audioPreparationState == .audioReady,
                              playerService.playbackState.duration > 0 else { return 0 }
                        return playerService.playbackState.currentTime / playerService.playbackState.duration
                    },
                    set: { newValue in
                        guard playerService.audioPreparationState == .audioReady else { return }
                        
                        // 取消之前的防抖动计时器
                        seekDebounceTimer?.invalidate()
                        
                        // 设置 seeking 状态
                        isSeeking = true
                        
                        let newTime = newValue * playerService.playbackState.duration
                        
                        // 立即更新时间显示（无需等待真实 seek）
                        playerService.playbackState.currentTime = newTime
                        
                        // 设置新的防抖动计时器
                        seekDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                            playerService.seek(to: newTime)
                            
                            // 延迟清除 seeking 状态
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isSeeking = false
                            }
                        }
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing {
                        // 用户结束拖动时，确保执行最后一次 seek
                        seekDebounceTimer?.fire()
                    }
                }
            )
            .accentColor(.accentColor)
            .frame(height: 10)
            .disabled(playerService.audioPreparationState != .audioReady)
            
            // 时间显示
            HStack {
                Text(playerService.formatTime(playerService.playbackState.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Group {
                    if isSeeking {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("跳转中...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                    } else {
                        switch playerService.audioPreparationState {
                        case .preparing:
                            Text("准备中...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.accentColor)
                        case .failed:
                            Text("加载失败")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)
                        default:
                            Text(playerService.formatTime(playerService.playbackState.duration))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}
