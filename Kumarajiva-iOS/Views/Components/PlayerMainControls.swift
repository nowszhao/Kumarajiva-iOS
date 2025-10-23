import SwiftUI

// MARK: - 播放器主控制按钮组件
struct PlayerMainControls: View {
    @ObservedObject var playerService: PodcastPlayerService
    let isAudioReady: Bool
    @Binding var showingConfigPanel: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // 播放速度
            Menu {
                ForEach([0.5, 0.6, 0.65, 0.7, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        playerService.setPlaybackRate(Float(rate))
                    } label: {
                        HStack {
                            Text("\(rate, specifier: "%.2g")x")
                            if playerService.playbackState.playbackRate == Float(rate) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 22, weight: .medium))
                    Text("\(playerService.playbackState.playbackRate, specifier: "%.2g")x")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            
            // 上一句
            Button {
                playerService.previousSubtitle()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 22, weight: .medium))
                    Text("上一句")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(isAudioReady && playerService.hasPreviousSubtitle ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .disabled(!isAudioReady || !playerService.hasPreviousSubtitle)
            
            // 播放/暂停
            Button {
                playerService.togglePlayPause()
            } label: {
                ZStack {
                    // 根据音频准备状态显示不同的图标
                    switch playerService.audioPreparationState {
                    case .idle, .failed:
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 45))
                            .foregroundColor(.secondary)
                    case .preparing:
                        // 显示准备进度
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                                .frame(width: 45, height: 45)
                            
                            Circle()
                                .trim(from: 0, to: playerService.audioPreparationProgress)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 45, height: 45)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.3), value: playerService.audioPreparationProgress)
                            
                            // 使用音频波形图标，更符合音频准备状态
                            Image(systemName: "waveform")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.accentColor)
                                .rotationEffect(.degrees(playerService.audioPreparationProgress * 360))
                                .animation(.easeInOut(duration: 0.5), value: playerService.audioPreparationProgress)
                        }
                    case .audioReady:
                        Image(systemName: playerService.playbackState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 45))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(playerService.audioPreparationState == .preparing)
            
            // 下一句
            Button {
                playerService.nextSubtitle()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 22, weight: .medium))
                    Text("下一句")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(isAudioReady && playerService.hasNextSubtitle ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .disabled(!isAudioReady || !playerService.hasNextSubtitle)
            
            // 更多设置按钮
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingConfigPanel.toggle()
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: showingConfigPanel ? "chevron.up" : "ellipsis")
                        .font(.system(size: 22, weight: .medium))
                    Text("更多")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(showingConfigPanel ? .accentColor : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
        }
        .padding(.horizontal, 20)
    }
}
