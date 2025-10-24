import SwiftUI

struct AliyunDriveDetailView: View {
    let drive: AliyunDrive
    @StateObject private var service = AliyunDriveService.shared
    @State private var isRefreshing = false
    
    // 计算属性：从 service 获取最新的云盘数据
    private var currentDrive: AliyunDrive {
        service.drives.first { $0.driveId == drive.driveId } ?? drive
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                // 云盘信息头部
                driveHeaderView
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                
                // 文件浏览器入口
                Section {
                    NavigationLink(destination: AliyunFileBrowserView(drive: currentDrive)) {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("浏览文件")
                                    .font(.body)
                                    .fontWeight(.medium)
                                
                                Text("查看云盘中的所有文件和文件夹")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("文件管理")
                        .font(.headline)
                }
            }
            .listStyle(.insetGrouped)
            
            // 底部迷你播放器
            MiniPlayerView()
        }
        .navigationTitle(currentDrive.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    refreshFiles()
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
    }
    
    // MARK: - 子视图
    
    private var driveHeaderView: some View {
        VStack(spacing: 16) {
            // 云盘信息卡片
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // 头像
                    if let avatar = currentDrive.avatar, let url = URL(string: avatar) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.title)
                                        .foregroundColor(.blue)
                                }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 60, height: 60)
                            .overlay {
                                Image(systemName: "cloud.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                    }
                    
                    // 用户信息
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentDrive.nickname)
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Text(currentDrive.userId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // 容量信息
                VStack(spacing: 8) {
                    HStack {
                        Text("容量")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(currentDrive.formattedUsedSize) / \(currentDrive.formattedTotalSize)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    // 进度条
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * currentDrive.usagePercentage)
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("已用 \(Int(currentDrive.usagePercentage * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // 统计信息
            HStack(spacing: 16) {
                StatItemView(
                    title: "视频",
                    value: "\(currentDrive.videoCount)",
                    icon: "video.fill",
                    color: .red
                )
                
                StatItemView(
                    title: "音频",
                    value: "\(currentDrive.audioCount)",
                    icon: "music.note",
                    color: .green
                )
                
                Spacer()
            }
        }
        .padding(16)
    }
    
    // MARK: - 方法
    
    private func refreshFiles() {
        isRefreshing = true
        
        Task {
            do {
                try await service.addDrive()
                await MainActor.run {
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    isRefreshing = false
                    print("❌ [AliyunDriveDetail] 刷新失败: \(error)")
                }
            }
        }
    }
    
    private func refreshFilesAsync() async {
        await MainActor.run {
            isRefreshing = true
        }
        
        do {
            try await service.addDrive()
        } catch {
            print("❌ [AliyunDriveDetail] 刷新失败: \(error)")
        }
        
        await MainActor.run {
            isRefreshing = false
        }
    }
}

// MARK: - 预览
#Preview {
    NavigationView {
        AliyunDriveDetailView(drive: AliyunDrive.example)
    }
}
