import SwiftUI

struct AddPodcastView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dataService = PodcastDataService.shared
    @StateObject private var searchService = PodcastSearchService.shared
    
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var rssURL = ""
    @State private var isAddingPodcast = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部标题区域
                headerView
                
                // 分段控制器
                segmentedControl
                
                // 内容区域
                TabView(selection: $selectedTab) {
                    // 搜索标签页
                    searchTabView
                        .tag(0)
                    
                    // RSS添加标签页
                    rssTabView
                        .tag(1)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarHidden(true)
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // MARK: - 头部视图
    private var headerView: some View {
        ZStack {
            VStack(spacing: 2) {
                // 顶部栏
                HStack {
                    Button("取消") {
                        dismiss()
                    }
                    .font(.body)
                    .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("添加播客")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // 平衡布局的占位符
                    Text("取消")
                        .font(.body)
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 5)
                .padding(.top, 20)
                
                // 图标和说明
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                    
                    Text("发现精彩播客")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("搜索热门播客或输入RSS地址")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            .padding(.bottom, 6)
        }.background(Color.accentColor)
    }
    
    // MARK: - 分段控制器
    private var segmentedControl: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // 搜索标签
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = 0
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                        Text("搜索播客")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(selectedTab == 0 ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                
                // RSS标签
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = 1
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "link.circle")
                            .font(.title3)
                        Text("RSS地址")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(selectedTab == 1 ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            
            // 指示器
            HStack {
                Rectangle()
                    .fill(selectedTab == 0 ? Color.accentColor : Color.clear)
                    .frame(height: 2)
                    .animation(.easeInOut(duration: 0.3), value: selectedTab)
                
                Rectangle()
                    .fill(selectedTab == 1 ? Color.accentColor : Color.clear)
                    .frame(height: 2)
                    .animation(.easeInOut(duration: 0.3), value: selectedTab)
            }
        }
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - 搜索标签页
    private var searchTabView: some View {
        VStack(spacing: 0) {
            // 搜索框
            searchBar
            
            // 搜索结果
            if searchService.isSearching {
                loadingView
            } else if searchService.searchResults.isEmpty && !searchText.isEmpty {
                emptySearchView
            } else if !searchService.searchResults.isEmpty {
                searchResultsList
            } else {
                searchPlaceholderView
            }
        }
    }
    
    // MARK: - 搜索框
    private var searchBar: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.body)
                
                TextField("搜索播客名称或主题...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchService.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.body)
                    }
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.systemGray6))
            )
            
            if !searchText.isEmpty {
                Button("搜索") {
                    performSearch()
                }
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - 搜索结果列表
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchService.searchResults) { result in
                    SearchResultCard(
                        result: result,
                        isAdding: isAddingPodcast
                    ) {
                        addPodcast(from: result)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
    
    // MARK: - 搜索占位符视图
    private var searchPlaceholderView: some View {
        VStack(spacing: 2) {
            
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                
                VStack(spacing: 8) {
                    Text("搜索播客")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("输入播客名称、主持人或关键词\n发现你感兴趣的内容")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }.padding(.top, 20)
            
            Spacer()
        }
        .padding(.horizontal, 10)
    }
    
     
    // MARK: - RSS标签页
    private var rssTabView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // RSS输入区域
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.title3)
                            
                            Text("RSS订阅地址")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        Text("如果你已经有播客的RSS地址，可以直接在这里添加")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // RSS输入框
                    VStack(spacing: 8) {
                        TextField("请输入", text: $rssURL, axis: .vertical)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor.systemGray6))
                            )
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            
                            Text("支持常见的播客RSS格式")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                    
                    // 添加按钮
                    Button {
                        addPodcastFromRSS()
                    } label: {
                        HStack {
                            if isAddingPodcast {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            
                            Text(isAddingPodcast ? "正在添加..." : "添加播客")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(rssURL.isEmpty ? Color.gray : Color.accentColor)
                        )
                    }
                    .disabled(rssURL.isEmpty || isAddingPodcast)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.systemBackground))
                )
                
            }
            .padding(20)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
    
 
    
    private func instructionStep(number: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - 其他视图
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("正在搜索...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("未找到相关播客")
                .font(.headline)
            
            Text("尝试使用不同的关键词搜索")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
    
    // MARK: - 方法
    private func performSearch() {
        Task {
            await searchService.searchPodcasts(query: searchText)
        }
    }
    
    private func addPodcast(from result: PodcastSearchResult) {
        guard !isAddingPodcast else { return }
        
        isAddingPodcast = true
        
        Task {
            do {
                try await dataService.addPodcast(rssURL: result.url)
                
                await MainActor.run {
                    isAddingPodcast = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAddingPodcast = false
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
        }
    }
    
    private func addPodcastFromRSS() {
        guard !rssURL.isEmpty, !isAddingPodcast else { return }
        
        isAddingPodcast = true
        
        Task {
            do {
                try await dataService.addPodcast(rssURL: rssURL.trimmingCharacters(in: .whitespacesAndNewlines))
                
                await MainActor.run {
                    isAddingPodcast = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAddingPodcast = false
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
        }
    }
}

// MARK: - 搜索结果卡片
struct SearchResultCard: View {
    let result: PodcastSearchResult
    let isAdding: Bool
    let onAdd: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // 播客封面
            AsyncImage(url: result.imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.systemGray5))
                    .overlay {
                        Image(systemName: "headphones")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // 播客信息
            VStack(alignment: .leading, spacing: 8) {
                Text(result.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if !result.author.isEmpty {
                    Text(result.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if !result.description.isEmpty {
                    Text(result.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // 添加按钮
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        if isAdding {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        
                        Text(isAdding ? "添加中" : "添加")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isAdding ? Color.gray : Color.accentColor)
                    )
                }
                .disabled(isAdding)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - 预览
#Preview {
    AddPodcastView()
} 
