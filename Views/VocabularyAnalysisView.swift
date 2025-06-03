                // 统计信息
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        // 智能显示解析类型
                        if playerService.markedWordCount > 0 {
                            Text("已标注 \(playerService.markedWordCount) 个单词")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("将优先解析标注的单词")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("共找到 \(vocabulary.count) 个生词")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("点击单词查看详细信息")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 8) {
                        // 智能解析按钮
                        if playerService.markedWordCount > 0 {
                            Button {
                                Task {
                                    await playerService.analyzeMarkedWords()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("解析标注")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .cornerRadius(8)
                            }
                            .disabled(playerService.vocabularyAnalysisState == .analyzing)
                        }
                        
                        // 重新解析按钮
                        Button {
                            Task {
                                await playerService.analyzeVocabulary()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                Text("全文解析")
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
                } 