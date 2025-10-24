import SwiftUI

// MARK: - 阿里云盘字幕行视图
/// 与 VideoSubtitleRowView 保持一致的样式
struct AliyunSubtitleRowView: View {
    let subtitle: Subtitle
    let isActive: Bool
    let currentTime: TimeInterval
    let showTranslation: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 时间和单词统计信息 - 移到上方
                HStack {
                    Text(formatTime(subtitle.startTime))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(isActive ? .accentColor : .secondary)
                    
                    Spacer()
                    
                    Text("\(subtitle.words.count)词")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, isActive ? 16 : 12)
                .padding(.top, 8)
                
                // 字幕文本区域
                VStack(alignment: .leading, spacing: showTranslation && subtitle.translatedText != nil ? 8 : 0) {
                    // 原始字幕文本
                    Text(subtitle.text)
                        .font(.system(size: 15, weight: isActive ? .medium : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, isActive ? 12 : 10)
                        .padding(.horizontal, isActive ? 16 : 12)
                    
                    // 翻译文本（如果有）
                    if showTranslation, let translatedText = subtitle.translatedText {
                        Divider()
                            .padding(.horizontal, isActive ? 16 : 12)
                            
                        Text(translatedText)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.blue)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, isActive ? 12 : 10)
                            .padding(.horizontal, isActive ? 16 : 12)
                    }
                }
                .padding(.bottom, showTranslation && subtitle.translatedText != nil ? 0 : 8)
            }
            .background(
                RoundedRectangle(cornerRadius: isActive ? 14 : 10)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : Color(.systemGray6).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: isActive ? 14 : 10)
                            .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: isActive ? 2 : 0)
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isActive)
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
