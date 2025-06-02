import SwiftUI

struct AddYouTuberView: View {
    @StateObject private var dataService = YouTubeDataService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var channelId = ""
    @State private var isSubscribing = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // 标题和说明
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("订阅YouTuber")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("输入YouTuber的频道ID来订阅他们的视频")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // 输入区域
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("输入YouTuber ID")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("例如: @LexClips", text: $channelId)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.body)
                        
                        Text("支持多种格式：@username、频道ID、用户名等")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 示例
                    VStack(alignment: .leading, spacing: 8) {
                        Text("示例格式:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ExampleChannelView(channelId: "@LexClips", description: "@ 用户名格式（推荐）")
                            ExampleChannelView(channelId: "@TED", description: "TED 演讲官方频道")
                            ExampleChannelView(channelId: "UCuAXFkgsw1L7xaCfnd5JJOw", description: "频道ID格式")
                            ExampleChannelView(channelId: "lexfridman", description: "用户名格式")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // 订阅按钮
                VStack(spacing: 12) {
                    Button {
                        subscribeToYouTuber()
                    } label: {
                        HStack {
                            if isSubscribing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(.white)
                            }
                            
                            Text(isSubscribing ? "订阅中..." : "订阅")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(canSubscribe ? Color.red : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!canSubscribe || isSubscribing)
                    
                    Button("取消") {
                        dismiss()
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("添加YouTuber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .alert("订阅失败", isPresented: $showingErrorAlert) {
            Button("确定", role: .cancel) { }
            if errorMessage.contains("已经订阅") {
                Button("查看列表") {
                    dismiss()
                }
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - 计算属性
    
    private var canSubscribe: Bool {
        !channelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - 方法
    
    private func subscribeToYouTuber() {
        let cleanChannelId = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanChannelId.isEmpty else { return }
        
        isSubscribing = true
        
        Task {
            do {
                try await dataService.subscribeToYouTuber(channelId: cleanChannelId)
                
                await MainActor.run {
                    isSubscribing = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubscribing = false
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
}

// MARK: - 示例频道视图
struct ExampleChannelView: View {
    let channelId: String
    let description: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(channelId)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("使用") {
                // 复制到剪贴板的功能
                UIPasteboard.general.string = channelId
            }
            .font(.caption)
            .foregroundColor(.accentColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 预览
#Preview {
    AddYouTuberView()
} 