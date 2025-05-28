                // 统计信息
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("共找到 \(vocabulary.count) 个生词")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("点击单词查看详细信息")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 重新解析按钮
                    Button {
                        Task {
                            await playerService.analyzeVocabulary()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                            Text("重新解析")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                    }
                    .disabled(playerService.vocabularyAnalysisState == .analyzing)
                } 