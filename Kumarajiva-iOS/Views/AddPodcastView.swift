import SwiftUI

struct AddPodcastView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dataService = PodcastDataService.shared
    
    @State private var rssURL = ""
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // 标题和说明
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.accentColor)
                    
                    Text("添加播客")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("输入播客的RSS地址，我们会自动获取播客信息")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // RSS输入框
                VStack(alignment: .leading, spacing: 8) {
                    Text("RSS地址")
                        .font(.headline)
                    
                    TextField("https://example.com/podcast.rss", text: $rssURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Text("支持常见的播客RSS格式")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // 添加按钮
                Button {
                    addPodcast()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        
                        Text(isLoading ? "正在添加..." : "添加播客")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(rssURL.isEmpty ? Color.gray : Color.accentColor)
                    )
                }
                .disabled(rssURL.isEmpty || isLoading)
                .padding(.horizontal)
            }
            .padding(.top)
            .navigationTitle("添加播客")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // MARK: - 方法
    
    private func addPodcast() {
        guard !rssURL.isEmpty else { return }
        
        isLoading = true
        
        Task {
            do {
                try await dataService.addPodcast(rssURL: rssURL.trimmingCharacters(in: .whitespacesAndNewlines))
                
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
        }
    }
}

// MARK: - 示例RSS行视图
struct ExampleRSSRow: View {
    let title: String
    let url: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}

// MARK: - 预览
#Preview {
    AddPodcastView()
} 