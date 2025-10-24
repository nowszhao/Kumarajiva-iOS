import SwiftUI

/// 阿里云盘字幕选择器视图
struct AliyunSubtitlePickerView: View {
    let drive: AliyunDrive
    let mediaFile: AliyunMediaFile
    @Binding var selectedSubtitle: AliyunSubtitleFile?
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var service = AliyunDriveService.shared
    @State private var currentFolderId: String
    @State private var folderPath: [FolderPathItem] = []
    @State private var items: [AliyunFileItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    
    init(drive: AliyunDrive, mediaFile: AliyunMediaFile, selectedSubtitle: Binding<AliyunSubtitleFile?>) {
        self.drive = drive
        self.mediaFile = mediaFile
        self._selectedSubtitle = selectedSubtitle
        self._currentFolderId = State(initialValue: mediaFile.parentFileId)
    }
    
    // 筛选字幕文件
    private var subtitleFiles: [AliyunFileItem] {
        let filtered = searchText.isEmpty ? items : items.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) 
        }
        
        return filtered.filter { item in
            guard item.type == "file" else { return false }
            let ext = (item.name as NSString).pathExtension.lowercased()
            return ["ass", "ssa", "srt", "vtt"].contains(ext)
        }
    }
    
    // 文件夹列表
    private var folders: [AliyunFileItem] {
        let filtered = searchText.isEmpty ? items : items.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) 
        }
        return filtered.filter { $0.type == "folder" }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 路径导航
                if !folderPath.isEmpty {
                    pathNavigationBar
                }
                
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
            .navigationTitle("选择字幕文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
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
                    // 初始化路径
                    folderPath = [FolderPathItem(id: "root", name: "全部文件")]
                    if currentFolderId != "root" {
                        folderPath.append(FolderPathItem(id: currentFolderId, name: "当前目录"))
                    }
                    loadFiles()
                }
            }
        }
    }
    
    // MARK: - 子视图
    
    private var pathNavigationBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(folderPath.enumerated()), id: \.element.id) { index, folder in
                    Button {
                        navigateToFolder(at: index)
                    } label: {
                        HStack(spacing: 4) {
                            if index == 0 {
                                Image(systemName: "house.fill")
                                    .font(.caption)
                            }
                            Text(folder.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundColor(index == folderPath.count - 1 ? .primary : .blue)
                    }
                    
                    if index < folderPath.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索字幕文件", text: $searchText)
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
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
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
                .font(.system(size: 48))
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
            // 字幕文件
            if !subtitleFiles.isEmpty {
                Section {
                    ForEach(subtitleFiles, id: \.fileId) { file in
                        subtitleFileRow(file)
                    }
                } header: {
                    HStack {
                        Image(systemName: "captions.bubble.fill")
                        Text("字幕文件 (\(subtitleFiles.count))")
                    }
                }
            }
            
            // 文件夹
            if !folders.isEmpty {
                Section {
                    ForEach(folders, id: \.fileId) { folder in
                        folderRow(folder)
                    }
                } header: {
                    HStack {
                        Image(systemName: "folder.fill")
                        Text("文件夹 (\(folders.count))")
                    }
                }
            }
            
            // 空状态
            if subtitleFiles.isEmpty && folders.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text(searchText.isEmpty ? "此文件夹中没有字幕文件" : "未找到匹配的字幕文件")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("支持的格式: ASS, SSA, SRT, VTT")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func subtitleFileRow(_ file: AliyunFileItem) -> some View {
        Button {
            selectSubtitle(file)
        } label: {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(formatColor(for: file).opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: formatIcon(for: file))
                        .font(.title3)
                        .foregroundColor(formatColor(for: file))
                }
                
                // 文件信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Text(formatName(for: file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let size = file.size {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // 选中标记
                if let selected = selectedSubtitle, selected.fileId == file.fileId {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func folderRow(_ folder: AliyunFileItem) -> some View {
        Button {
            navigateToFolder(folder)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 44)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(formatDateString(folder.updatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - 辅助方法
    
    private func loadFiles() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fileItems = try await service.listFiles(
                    driveId: drive.driveId,
                    parentFileId: currentFolderId
                )
                
                await MainActor.run {
                    self.items = fileItems
                    isLoading = false
                    print("☁️ [SubtitlePicker] 加载了 \(items.count) 个项目")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "加载失败: \(error.localizedDescription)"
                    print("☁️ [SubtitlePicker] ❌ 加载失败: \(error)")
                }
            }
        }
    }
    
    private func navigateToFolder(_ folder: AliyunFileItem) {
        currentFolderId = folder.fileId
        folderPath.append(FolderPathItem(id: folder.fileId, name: folder.name))
        items = []
        loadFiles()
    }
    
    private func navigateToFolder(at index: Int) {
        guard index < folderPath.count else { return }
        
        let targetFolder = folderPath[index]
        currentFolderId = targetFolder.id
        folderPath = Array(folderPath.prefix(index + 1))
        items = []
        loadFiles()
    }
    
    private func selectSubtitle(_ file: AliyunFileItem) {
        let ext = (file.name as NSString).pathExtension.lowercased()
        guard let format = AliyunSubtitleFile.SubtitleFormat(rawValue: ext) else { return }
        
        let subtitle = AliyunSubtitleFile(
            fileId: file.fileId,
            driveId: drive.driveId,
            name: file.name,
            format: format,
            size: file.size ?? 0
        )
        
        selectedSubtitle = subtitle
        dismiss()
    }
    
    private func formatIcon(for file: AliyunFileItem) -> String {
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "ass", "ssa":
            return "star.fill"
        default:
            return "captions.bubble.fill"
        }
    }
    
    private func formatColor(for file: AliyunFileItem) -> Color {
        let ext = (file.name as NSString).pathExtension.lowercased()
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
    
    private func formatName(for file: AliyunFileItem) -> String {
        let ext = (file.name as NSString).pathExtension.lowercased()
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
    
    private func formatDateString(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .abbreviated
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return dateString
    }
}

// MARK: - 辅助模型

struct FolderPathItem: Identifiable {
    let id: String
    let name: String
}

// MARK: - Preview

#Preview {
    AliyunSubtitlePickerView(
        drive: AliyunDrive.example,
        mediaFile: AliyunMediaFile.example,
        selectedSubtitle: .constant(nil)
    )
}
