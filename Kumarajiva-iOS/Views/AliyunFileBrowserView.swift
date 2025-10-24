import SwiftUI

/// 阿里云盘文件浏览器视图
struct AliyunFileBrowserView: View {
    let drive: AliyunDrive
    let parentFileId: String
    let folderName: String
    
    @StateObject private var service = AliyunDriveService.shared
    @State private var items: [AliyunFileItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    
    init(drive: AliyunDrive, parentFileId: String = "root", folderName: String = "全部文件") {
        self.drive = drive
        self.parentFileId = parentFileId
        self.folderName = folderName
    }
    
    // 筛选后的项目
    private var filteredItems: [AliyunFileItem] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // 文件夹列表
    private var folders: [AliyunFileItem] {
        filteredItems.filter { $0.type == "folder" }
    }
    
    // 媒体文件列表
    private var mediaFiles: [AliyunFileItem] {
        filteredItems.filter { $0.category == "video" || $0.category == "audio" }
    }
    
    // 字幕文件列表
    private var subtitleFiles: [AliyunFileItem] {
        filteredItems.filter { item in
            guard item.type == "file" else { return false }
            let ext = (item.name as NSString).pathExtension.lowercased()
            return ["ass", "ssa", "srt", "vtt"].contains(ext)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            searchBar
            
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                contentView
            }
        }
        .navigationTitle(folderName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    loadFiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .onAppear {
            if items.isEmpty {
                loadFiles()
            }
        }
    }
    
    // MARK: - 子视图
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索文件", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("加载中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("重试") {
                loadFiles()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var contentView: some View {
        List {
            // 文件夹部分
            if !folders.isEmpty {
                Section {
                    ForEach(folders, id: \.fileId) { folder in
                        NavigationLink(destination: AliyunFileBrowserView(
                            drive: drive,
                            parentFileId: folder.fileId,
                            folderName: folder.name
                        )) {
                            FolderRowView(folder: folder)
                        }
                    }
                } header: {
                    Text("文件夹 (\(folders.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            
            // 媒体文件部分
            if !mediaFiles.isEmpty {
                Section {
                    ForEach(mediaFiles, id: \.fileId) { item in
                        NavigationLink(destination: destinationView(for: item)) {
                            MediaFileItemRowView(item: item)
                        }
                    }
                } header: {
                    Text("媒体文件 (\(mediaFiles.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            
            // 字幕文件部分
            if !subtitleFiles.isEmpty {
                Section {
                    ForEach(subtitleFiles, id: \.fileId) { item in
                        SubtitleFileRowView(item: item)
                    }
                } header: {
                    HStack {
                        Image(systemName: "captions.bubble.fill")
                            .font(.caption)
                        Text("字幕文件 (\(subtitleFiles.count))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
            
            // 空状态
            if folders.isEmpty && mediaFiles.isEmpty && subtitleFiles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "此文件夹为空" : "未找到匹配的文件")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - 方法
    
    private func loadFiles() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fileList = try await service.listFiles(
                    driveId: drive.driveId,
                    parentFileId: parentFileId
                )
                
                await MainActor.run {
                    self.items = fileList
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    @ViewBuilder
    private func destinationView(for item: AliyunFileItem) -> some View {
        let mediaFile = convertToMediaFile(item)
        
        if item.category == "video" {
            AliyunVideoPlayerView(file: mediaFile)
        } else if item.category == "audio" {
            AliyunAudioPlayerView(file: mediaFile)
        } else {
            Text("不支持的文件类型")
        }
    }
    
    // 将 AliyunFileItem 转换为 AliyunMediaFile
    private func convertToMediaFile(_ item: AliyunFileItem) -> AliyunMediaFile {
        let duration = parseDuration(item.videoMediaMetadata?.duration)
        let createdAt = parseDate(item.createdAt) ?? Date()
        let updatedAt = parseDate(item.updatedAt) ?? Date()
        
        return AliyunMediaFile(
            fileId: item.fileId,
            driveId: drive.driveId,
            parentFileId: parentFileId,
            name: item.name,
            type: item.category == "video" ? .video : .audio,
            size: item.size ?? 0,
            duration: duration,
            thumbnailURL: item.thumbnail,
            category: item.category,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    private func parseDuration(_ durationString: String?) -> TimeInterval {
        guard let durationString = durationString,
              let duration = Double(durationString) else {
            return 0
        }
        return duration
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}

// MARK: - 文件夹行视图
struct FolderRowView: View {
    let folder: AliyunFileItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 文件夹图标
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(formatDate(folder.updatedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        displayFormatter.locale = Locale(identifier: "zh_CN")
        return displayFormatter.string(from: date)
    }
}

// MARK: - 字幕文件行视图
struct SubtitleFileRowView: View {
    let item: AliyunFileItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(formatColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: formatIcon)
                    .font(.title3)
                    .foregroundColor(formatColor)
            }
            
            // 文件信息
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    // 格式标签
                    Text(formatName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(formatColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(formatColor.opacity(0.15))
                        .cornerRadius(4)
                    
                    // 文件大小
                    if let size = item.size {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.fill")
                                .font(.caption2)
                            Text(formatSize(size))
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    
    private var formatIcon: String {
        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "ass", "ssa":
            return "star.fill"
        default:
            return "captions.bubble.fill"
        }
    }
    
    private var formatColor: Color {
        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "ass":
            return .purple
        case "ssa":
            return .indigo
        case "srt":
            return .blue
        case "vtt":
            return .cyan
        default:
            return .gray
        }
    }
    
    private var formatName: String {
        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "ass":
            return "ASS字幕"
        case "ssa":
            return "SSA字幕"
        case "srt":
            return "SRT字幕"
        case "vtt":
            return "VTT字幕"
        default:
            return ext.uppercased()
        }
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - 媒体文件行视图
struct MediaFileItemRowView: View {
    let item: AliyunFileItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 缩略图或图标
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.category == "video" ? Color.purple.opacity(0.1) : Color.green.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                if let thumbnailURL = item.thumbnail, !thumbnailURL.isEmpty {
                    AsyncImage(url: URL(string: thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } placeholder: {
                        Image(systemName: item.category == "video" ? "play.rectangle.fill" : "music.note")
                            .font(.title2)
                            .foregroundColor(item.category == "video" ? .purple : .green)
                    }
                } else {
                    Image(systemName: item.category == "video" ? "play.rectangle.fill" : "music.note")
                        .font(.title2)
                        .foregroundColor(item.category == "video" ? .purple : .green)
                }
            }
            
            // 文件信息
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    // 时长标签
                    if let duration = item.videoMediaMetadata?.duration {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(.caption2)
                            Text(formatDuration(duration))
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // 文件大小
                    if let size = item.size {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.fill")
                                .font(.caption2)
                            Text(formatSize(size))
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private func formatDuration(_ durationString: String) -> String {
        guard let duration = Double(durationString) else { return durationString }
        
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - 预览
#Preview {
    NavigationView {
        AliyunFileBrowserView(drive: AliyunDrive.example)
    }
}
