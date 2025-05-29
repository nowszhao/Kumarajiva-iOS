import SwiftUI

struct VocabularyView: View {
    @ObservedObject private var viewModel = VocabularyViewModel.shared
    @State private var showingDeleteAlert = false
    @State private var vocabularyToDelete: VocabularyItem?
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var showingMenu = false
    @State private var filterOption: FilterOption = .all
    @State private var sortOrder: SortOrder = .newestFirst
    
    enum FilterOption: String, CaseIterable {
        case all = "全部"
        case mastered = "已掌握"
        case notMastered = "未掌握"
        case newlyAdded = "新添加"
        
        var systemImage: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .mastered: return "checkmark.circle"
            case .notMastered: return "circle"
            case .newlyAdded: return "sparkles"
            }
        }
    }
    
    enum SortOrder: String, CaseIterable {
        case newestFirst = "最新优先"
        case oldestFirst = "最早优先"
        
        var systemImage: String {
            switch self {
            case .newestFirst: return "arrow.down.circle"
            case .oldestFirst: return "arrow.up.circle"
            }
        }
    }
    
    // 计算属性：根据搜索文本、过滤选项和排序过滤词汇
    var filteredVocabularies: [VocabularyItem] {
        var result = viewModel.vocabularies
        
        // 调试信息
        print("🔍 [Filter] 开始筛选，总词汇数: \(result.count)")
        print("🔍 [Filter] 当前筛选选项: \(filterOption.rawValue)")
        
        // 应用过滤选项
        switch filterOption {
        case .all:
            break
        case .mastered:
            result = result.filter { $0.mastered > 0 }
        case .notMastered:
            result = result.filter { $0.mastered == 0 }
        case .newlyAdded:
            let newlyAddedCount = result.filter { $0.isNewlyAdded == true }.count
            print("🔍 [Filter] 新添加的词汇数量: \(newlyAddedCount)")
            result.enumerated().forEach { index, vocab in
                if vocab.isNewlyAdded == true {
                    print("🔍 [Filter] 找到新添加词汇[\(index)]: \(vocab.word), isNewlyAdded: \(vocab.isNewlyAdded ?? false)")
                }
            }
            result = result.filter { $0.isNewlyAdded == true }
        }
        
        print("🔍 [Filter] 筛选后词汇数: \(result.count)")
        
        // 应用搜索过滤
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            result = result.filter { vocabulary in
                vocabulary.word.lowercased().contains(lowercasedSearch) ||
                (vocabulary.pronunciation?.values.contains { $0.lowercased().contains(lowercasedSearch) } ?? false) ||
                vocabulary.definitions.contains { definition in
                    definition.pos.lowercased().contains(lowercasedSearch) ||
                    definition.meaning.lowercased().contains(lowercasedSearch)
                } ||
                (vocabulary.memoryMethod?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }
        
        // 应用排序
        result.sort { first, second in
            switch sortOrder {
            case .newestFirst:
                return first.timestamp > second.timestamp
            case .oldestFirst:
                return first.timestamp < second.timestamp
            }
        }
        
        return result
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Bar with Search and Actions
                topBarSection
                
                // Filter and Sort Section
                filterSortSection
                
                // Content
                if viewModel.isLoading && viewModel.vocabularies.isEmpty {
                    loadingView
                } else if viewModel.vocabularies.isEmpty {
                    emptyStateView
                } else if filteredVocabularies.isEmpty {
                    noSearchResultsView
                } else {
                    vocabularyList
                }
            }
        }
        .task {
            print("📱 VocabularyView.task 触发，当前词汇数量: \(viewModel.vocabularies.count)")
            if viewModel.vocabularies.isEmpty {
                print("📱 词汇列表为空，开始加载...")
                await viewModel.loadVocabularies()
            } else {
                print("📱 词汇列表不为空，跳过加载")
            }
        }
        .alert("删除生词", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let vocabulary = vocabularyToDelete {
                    Task {
                        await viewModel.deleteVocabulary(vocabulary)
                    }
                }
            }
        } message: {
            if let vocabulary = vocabularyToDelete {
                Text("确定要删除「\(vocabulary.word)」吗？此操作无法撤销。")
            }
        }
        .alert("错误", isPresented: .constant(viewModel.error != nil)) {
            Button("确定") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
    }
    
    // MARK: - Top Bar Section
    
    private var topBarSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    TextField("搜索单词、释义、记忆方法...", text: $searchText)
                        .font(.system(size: 15))
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                // Refresh Button
                Button(action: {
                    Task {
                        await viewModel.refreshVocabularies()
                    }
                }) {
                    Image(systemName: viewModel.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                        .font(.system(size: 18))
                        .foregroundColor(viewModel.isRefreshing ? .gray : .blue)
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(viewModel.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isRefreshing)
                }
                .disabled(viewModel.isRefreshing)
                
                // Menu Button
                Menu {
                    Button(action: {
                        print("🔄 [Sync] 用户点击同步云端按钮")
                        print("🔄 [Sync] 当前生词数量: \(viewModel.vocabularies.count)")
                        print("🔄 [Sync] 本地修改数量: \(viewModel.modifiedCount)")
                        print("🔄 [Sync] 是否正在同步: \(viewModel.isSyncing)")
                        Task {
                            await viewModel.syncToCloud()
                        }
                    }) {
                        HStack {
                            Label("同步云端", systemImage: "icloud.and.arrow.up")
                            if viewModel.hasModifiedVocabularies {
                                Text("(\(viewModel.modifiedCount))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(viewModel.isSyncing)
                    
                    if viewModel.isSyncing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("同步中...")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                
                if isSearchFocused {
                    Button("取消") {
                        searchText = ""
                        isSearchFocused = false
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.blue)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
    
    // MARK: - Filter and Sort Section
    
    private var filterSortSection: some View {
        HStack(spacing: 12) {
            // Filter Menu
            Menu {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    Button(action: {
                        filterOption = option
                    }) {
                        Label {
                            HStack {
                                Text(option.rawValue)
                                Spacer()
                                Text("(\(getCountForFilter(option)))")
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: option.systemImage)
                                .foregroundColor(filterOption == option ? .blue : .primary)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: filterOption.systemImage)
                        .font(.system(size: 12))
                    Text(filterOption.rawValue)
                        .font(.system(size: 13, weight: .medium))
                    Text("(\(getCountForFilter(filterOption)))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
            
            // Sort Menu
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button(action: {
                        sortOrder = order
                    }) {
                        Label(order.rawValue, systemImage: order.systemImage)
                            .foregroundColor(sortOrder == order ? .blue : .primary)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: sortOrder.systemImage)
                        .font(.system(size: 12))
                    Text(sortOrder.rawValue)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
            
            Spacer()
            
            // Results count
//            if !searchText.isEmpty || filterOption != .all {
//                Text("\(filteredVocabularies.count) 个结果")
//                    .font(.system(size: 12))
//                    .foregroundColor(.secondary)
//            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
    
    private func getCountForFilter(_ option: FilterOption) -> Int {
        switch option {
        case .all:
            return viewModel.vocabularies.count
        case .mastered:
            return viewModel.vocabularies.filter { $0.mastered > 0 }.count
        case .notMastered:
            return viewModel.vocabularies.filter { $0.mastered == 0 }.count
        case .newlyAdded:
            return viewModel.vocabularies.filter { $0.isNewlyAdded == true }.count
        }
    }
    
    // MARK: - Vocabulary List
    
    private var vocabularyList: some View {
        List {
            ForEach(Array(filteredVocabularies.enumerated()), id: \.element.id) { index, vocabulary in
                VocabularyCard(
                    vocabulary: vocabulary,
                    isFirst: index == 0
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button(role: .destructive) {
                        vocabularyToDelete = vocabulary
                        showingDeleteAlert = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            print("📱 用户执行下拉刷新操作")
            await viewModel.refreshVocabularies()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在加载生词...")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("暂无生词")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("开始学习单词，生词会自动添加到这里")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                Task {
                    await viewModel.refreshVocabularies()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("刷新")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
    
    // MARK: - No Search Results View
    
    private var noSearchResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("没有找到相关结果")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("请尝试其他搜索词或筛选条件")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                searchText = ""
                filterOption = .all
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                    Text("清除筛选")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - Vocabulary Card

struct VocabularyCard: View {
    let vocabulary: VocabularyItem
    let isFirst: Bool
    
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(vocabulary.word)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.primary)
                        
                        // 新添加标记
                        if vocabulary.isNewlyAdded == true {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("新添加")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Mastered indicator
                        if vocabulary.mastered > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                Text("已掌握")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: "circle")
                                    .font(.system(size: 11))
                                Text("未掌握")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    if let pronunciation = vocabulary.pronunciation, !pronunciation.isEmpty {
                        Text(formatPronunciation(pronunciation))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Definitions
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(vocabulary.definitions.enumerated()), id: \.offset) { index, definition in
                    HStack(alignment: .top, spacing: 6) {
                        Text(definition.pos)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(3)
                        
                        Text(definition.meaning)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .lineLimit(showingDetails ? nil : 2)
                    }
                }
            }
            
            // Memory method
            if showingDetails {
                VStack(alignment: .leading, spacing: 3) {
                    Text("记忆方法")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if let memoryMethod = vocabulary.memoryMethod, !memoryMethod.isEmpty {
                        Text(memoryMethod)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                    } else {
                        Text("暂无记忆方法")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                    }
                }
            }
            
            // Footer
            HStack {
                Text(formatTimestamp(vocabulary.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingDetails.toggle()
                    }
                }) {
                    Text(showingDetails ? "收起" : "展开")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
    }
    
    private func formatPronunciation(_ pronunciation: [String: String]) -> String {
        // Prefer American pronunciation, fallback to British
        if let american = pronunciation["American"], !american.isEmpty {
            return american
        } else if let british = pronunciation["British"], !british.isEmpty {
            return british
        }
        return ""
    }
    
    private func formatTimestamp(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

#Preview {
    VocabularyView()
} 
