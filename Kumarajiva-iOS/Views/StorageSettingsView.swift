import SwiftUI

struct StorageSettingsView: View {
    @StateObject private var dataService = PodcastDataService.shared
    @State private var storageSize: String = "计算中..."
    @State private var showingClearAlert = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            List {
                Section("存储信息") {
                    HStack {
                        Image(systemName: "internaldrive")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("数据存储位置")
                                .font(.headline)
                            Text("应用程序支持目录")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("持久化")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                    }
                    
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("iCloud备份")
                                .font(.headline)
                            Text("数据会被备份到iCloud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("已启用")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                    }
                    
                    HStack {
                        Image(systemName: "externaldrive")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("存储大小")
                                .font(.headline)
                            Text("包含播客数据和字幕缓存")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(storageSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("数据持久化") {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("APP重装后保留")
                                .font(.headline)
                            Text("字幕和播客数据会在APP重装后保留")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("自动备份")
                                .font(.headline)
                            Text("数据会自动备份到iCloud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading) {
                            Text("数据安全")
                                .font(.headline)
                            Text("多层次存储保护，确保数据不丢失")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("数据管理") {
                    Button(action: {
                        refreshStorageInfo()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                            Text("刷新存储信息")
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isLoading)
                    
                    Button(action: {
                        showingClearAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("清除所有数据")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section("说明") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("数据存储说明")
                            .font(.headline)
                        
                        Text("• 播客数据和字幕存储在应用程序支持目录中")
                        Text("• 数据会自动备份到iCloud（如果启用）")
                        Text("• APP重装后数据会自动恢复")
                        Text("• 只有手动删除才会清除数据")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("存储设置")
            .onAppear {
                refreshStorageInfo()
            }
            .alert("清除所有数据", isPresented: $showingClearAlert) {
                Button("取消", role: .cancel) { }
                Button("确认清除", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("这将删除所有播客数据和字幕。此操作不可撤销。")
            }
        }
    }
    
    private func refreshStorageInfo() {
        isLoading = true
        
        Task {
            let size = PersistentStorageManager.shared.getStorageSize()
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            
            await MainActor.run {
                self.storageSize = formatter.string(fromByteCount: size)
                self.isLoading = false
            }
        }
    }
    
    private func clearAllData() {
        Task {
            do {
                try PersistentStorageManager.shared.clearAllData()
                
                await MainActor.run {
                    // 清除内存中的数据
                    dataService.podcasts.removeAll()
                    
                    // 刷新存储信息
                    refreshStorageInfo()
                }
                
                print("🎧 [Storage] 所有数据已清除")
            } catch {
                print("🎧 [Storage] 清除数据失败: \(error)")
            }
        }
    }
} 