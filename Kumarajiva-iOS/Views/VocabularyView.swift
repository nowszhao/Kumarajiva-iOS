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
    @State private var showingEditSheet = false
    @State private var vocabularyToEdit: VocabularyItem?
    
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
        .sheet(isPresented: $showingEditSheet) {
            if let vocabulary = vocabularyToEdit {
                EditVocabularyView(vocabulary: vocabulary) { updatedVocabulary in
                    Task {
                        await viewModel.updateVocabulary(updatedVocabulary)
                    }
                    showingEditSheet = false
                    vocabularyToEdit = nil
                }
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
                    
                    Button(action: {
                        vocabularyToEdit = vocabulary
                        showingEditSheet = true
                    }) {
                        Label("编辑", systemImage: "pencil")
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

// MARK: - Edit Vocabulary View

struct EditVocabularyView: View {
    let originalVocabulary: VocabularyItem
    let onSave: (VocabularyItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var word: String
    @State private var definitions: [EditableDefinition]
    @State private var americanPronunciation: String
    @State private var britishPronunciation: String
    @State private var memoryMethod: String
    @State private var mastered: Bool
    
    init(vocabulary: VocabularyItem, onSave: @escaping (VocabularyItem) -> Void) {
        self.originalVocabulary = vocabulary
        self.onSave = onSave
        
        _word = State(initialValue: vocabulary.word)
        _definitions = State(initialValue: vocabulary.definitions.map { EditableDefinition(pos: $0.pos, meaning: $0.meaning) })
        _americanPronunciation = State(initialValue: vocabulary.pronunciation?["American"] ?? "")
        _britishPronunciation = State(initialValue: vocabulary.pronunciation?["British"] ?? "")
        _memoryMethod = State(initialValue: vocabulary.memoryMethod ?? "")
        _mastered = State(initialValue: vocabulary.mastered > 0)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("单词信息") {
                    HStack {
                        Text("单词")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(word)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("发音") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("美式发音")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 80, alignment: .leading)
                            TextField("如：/əˈmerɪkən/", text: $americanPronunciation)
                                .font(.system(size: 15))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        HStack {
                            Text("英式发音")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 80, alignment: .leading)
                            TextField("如：/əˈmerɪkən/", text: $britishPronunciation)
                                .font(.system(size: 15))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("释义") {
                    ForEach($definitions) { $definition in
                        VStack(spacing: 8) {
                            HStack {
                                Text("词性")
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(width: 50, alignment: .leading)
                                TextField("如：n. / v. / adj.", text: $definition.pos)
                                    .font(.system(size: 15))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            HStack(alignment: .top) {
                                Text("释义")
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(width: 50, alignment: .leading)
                                    .padding(.top, 8)
                                TextField("请输入中文释义", text: $definition.meaning, axis: .vertical)
                                    .font(.system(size: 15))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .lineLimit(3...6)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(8)
                    }
                    .onDelete(perform: deleteDefinition)
                    
                    Button(action: addDefinition) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("添加释义")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                }
                
                Section("记忆方法") {
                    TextField("请输入记忆方法...", text: $memoryMethod, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(5...10)
                        .textFieldStyle(.plain)
                }
                
                Section("掌握状态") {
                    Toggle("已掌握", isOn: $mastered)
                        .font(.system(size: 16))
                }
            }
            .navigationTitle("编辑单词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveVocabulary()
                    }
                    .fontWeight(.semibold)
                    .disabled(definitions.isEmpty || definitions.allSatisfy { $0.pos.isEmpty || $0.meaning.isEmpty })
                }
            }
        }
    }
    
    private func addDefinition() {
        definitions.append(EditableDefinition(pos: "", meaning: ""))
    }
    
    private func deleteDefinition(at offsets: IndexSet) {
        definitions.remove(atOffsets: offsets)
    }
    
    private func saveVocabulary() {
        // 构建更新后的发音字典
        var pronunciation: [String: String] = [:]
        if !americanPronunciation.isEmpty {
            pronunciation["American"] = americanPronunciation
        }
        if !britishPronunciation.isEmpty {
            pronunciation["British"] = britishPronunciation
        }
        
        // 过滤掉空的释义
        let validDefinitions = definitions
            .filter { !$0.pos.isEmpty && !$0.meaning.isEmpty }
            .map { VocabularyDefinition(pos: $0.pos, meaning: $0.meaning) }
        
        // 创建更新后的词汇项
        let updatedVocabulary = VocabularyItem(
            word: originalVocabulary.word,
            definitions: validDefinitions,
            memoryMethod: memoryMethod.isEmpty ? nil : memoryMethod,
            pronunciation: pronunciation.isEmpty ? nil : pronunciation,
            mastered: mastered ? 1 : 0,
            timestamp: originalVocabulary.timestamp,  // 保持原有时间戳，不更新时间
            userId: originalVocabulary.userId,
            isNewlyAdded: originalVocabulary.isNewlyAdded
        )
        
        onSave(updatedVocabulary)
    }
}

// MARK: - Editable Definition Model

struct EditableDefinition: Identifiable {
    let id = UUID()
    var pos: String
    var meaning: String
}

// MARK: - Extensions

extension Date {
    var timeIntervalSince1970Milliseconds: Int64 {
        return Int64(self.timeIntervalSince1970 * 1000)
    }
} 
