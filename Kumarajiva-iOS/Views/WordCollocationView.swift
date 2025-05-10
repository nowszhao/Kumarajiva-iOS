import SwiftUI

struct WordCollocationView: View {
    let word: String
    @State private var collocation: WordCollocation?
    @State private var isLoading = false
    @State private var error: String?
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with button
            HStack {
                Text("「词语搭配」")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                
                if let wordCollocation = collocation,
                   !wordCollocation.chunks.isEmpty,
                   !isLoading {
                    
                    // 添加折叠/展开按钮
                    Button(action: { 
                        withAnimation { isExpanded.toggle() }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 2)
                    }
                }
                
                Spacer()
                
                // 添加解析/重新解析按钮
                Button(action: {
                    Task {
                        // 如果已有解析结果，清除后重新解析
                        if collocation != nil {
                            WordCollocationService.shared.clearCache(for: word)
                            collocation = nil
                        }
                        isLoading = true
                        error = nil
                        collocation = await WordCollocationService.shared.getCollocations(for: word)
                        isLoading = false
                        withAnimation { isExpanded = true }
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .frame(width: 18, height: 18)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: collocation == nil ? "sparkles" : "arrow.clockwise")
                                .font(.system(size: 11))
                            
                            Text(collocation == nil ? "解析" : "重新解析")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    }
                }
            }
            
            // Content area
            if isLoading {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        ProgressView()
                        Text("正在解析中...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(8)
            } else if let errorMessage = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(8)
            } else if let wordCollocation = collocation {
                if wordCollocation.chunks.isEmpty {
                    Text("无法找到相关词语搭配")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        // 显示第一个词块，总是可见
                        if !wordCollocation.chunks.isEmpty {
                            ImprovedChunkView(chunk: wordCollocation.chunks[0], isFirst: true)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                        }
                        
                        // 展开时显示额外的词块
                        if isExpanded && wordCollocation.chunks.count > 1 {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(wordCollocation.chunks.dropFirst().enumerated()), id: \.element.id) { index, chunk in
                                    ImprovedChunkView(chunk: chunk, isFirst: false)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 8)
                                    
                                    if index < wordCollocation.chunks.count - 2 {
                                        Divider()
                                    }
                                }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(8)
                }
            } else {
                Text("点击解析按钮查看该单词的常用搭配")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(8)
            }
        }
        // 移除自动加载，需要用户手动点击解析按钮
    }
}

// 改进的词块视图组件
struct ImprovedChunkView: View {
    let chunk: WordCollocation.Chunk
    let isFirst: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 词块和中文含义
            HStack(alignment: .top) {
                Text(chunk.chunk)
                    .font(.system(size: 15, weight: isFirst ? .semibold : .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                Text(chunk.chunkChinese)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // 示例句子
            HStack(alignment: .top, spacing: 4) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 2)
                
                Text(chunk.chunkSentence)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
        }
    }
}

// 保留原始ChunkView以兼容性
struct ChunkView: View {
    let chunk: WordCollocation.Chunk
    let isFirst: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 词块和中文含义
            HStack(alignment: .top) {
                Text(chunk.chunk)
                    .font(.system(size: 15, weight: isFirst ? .medium : .regular))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(chunk.chunkChinese)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            // 所有词块的示例句子
            Text(chunk.chunkSentence)
                .font(.system(size: isFirst ? 13 : 14))
                .foregroundColor(.gray)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}