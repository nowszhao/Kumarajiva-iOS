import SwiftUI

struct ReviewView: View {
    @StateObject private var viewModel = ReviewViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingView()
            } else if let quiz = viewModel.currentQuiz {
                QuizView(quiz: quiz, progress: viewModel.progress, viewModel: viewModel) { isCorrect in
                    Task {
                        await viewModel.submitAnswer(word: quiz.word, isCorrect: isCorrect)
                    }
                }
            } else if let progress = viewModel.progress {
                CompletionView(progress: progress) {
                    Task {
                        await viewModel.reset()
                    }
                }
            } else {
                ReviewEmptyStateView()
            }
        }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                Text(viewModel.error ?? "")
        }
        .task {
            await viewModel.loadTodayWords()
        }
    }
}

// MARK: - 加载状态视图
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在加载今日单词...")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 今日学习空状态视图
struct ReviewEmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 图标
            Image(systemName: "book.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.6))
            
            // 文字
            VStack(spacing: 8) {
                Text("今日暂无新单词")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("继续保持学习习惯\n明天会有新的单词等你来挑战")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// 完成视图组件
struct CompletionView: View {
    let progress: Progress
    let onReset: () -> Void
    @State private var animateCheckmark = false
    @State private var animateStats = false
    @State private var showingRandomQuiz = false
    
    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.05),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
            
                // 成功图标区域
                VStack(spacing: 20) {
                    ZStack {
                        // 背景圆圈 - 简化效果
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 100, height: 100)
                            .scaleEffect(animateCheckmark ? 1.0 : 0.8)
                        
                        // 主图标
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(animateCheckmark ? 1.0 : 0.3)
                            .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2), value: animateCheckmark)
                    }
                    
                    // 标题文字
                    VStack(spacing: 8) {
                        Text("今日学习完成!")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("正确率: \(calculateAccuracy(progress))%")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .opacity(animateCheckmark ? 1.0 : 0)
                    .animation(.easeInOut(duration: 0.6).delay(0.5), value: animateCheckmark)
                }
            
                // 统计卡片区域
                HStack(spacing: 16) {
                    CompactStatCard(
                        title: "总题数",
                        value: "\(progress.totalWords)",
                        icon: "list.bullet.circle.fill",
                        color: .blue
                    )
                    .opacity(animateStats ? 1.0 : 0)
                    .offset(y: animateStats ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.7), value: animateStats)
                    
                    CompactStatCard(
                        title: "正确数", 
                        value: "\(progress.correct)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    .opacity(animateStats ? 1.0 : 0)
                    .offset(y: animateStats ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.8), value: animateStats)
                }
                .padding(.horizontal, 24)
                
            
                Spacer()
                
                // 主要行动区域 - 鼓励继续学习
                VStack(spacing: 16) {
                    // 鼓励文字
                    VStack(spacing: 4) {
                        Text("太棒了！")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("继续保持这个学习节奏")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .opacity(animateStats ? 1.0 : 0)
                    .animation(.easeInOut(duration: 0.6).delay(1.1), value: animateStats)
                    
                    // 操作按钮区域
                    HStack(spacing: 12) {
                        // 重新练习按钮
                        Button(action: onReset) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                Text("重新练习")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color(.systemBackground))
                                    )
                            )
                        }
                        
                        // 随机测验按钮
                        Button(action: { showingRandomQuiz = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 14, weight: .medium))
                                Text("随机测验")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.blue)
                            )
                        }
                    }
                    .opacity(animateStats ? 1.0 : 0)
                    .scaleEffect(animateStats ? 1.0 : 0.9)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.2), value: animateStats)
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            animateCheckmark = true
            animateStats = true
        }
        .sheet(isPresented: $showingRandomQuiz) {
            RandomQuizView()
        }
    }
    
    private func calculateAccuracy(_ progress: Progress) -> Int {
        guard progress.totalWords > 0 else { return 0 }
        return Int((Double(progress.correct) / Double(progress.totalWords)) * 100)
    }
}

// 现代化统计卡片组件
struct CompactStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 10) {
            // 图标区域
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)
            }
            
            // 数值和标题
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// 简化准确率显示组件
struct CompactAccuracyView: View {
    let accuracy: Int
    @State private var progress: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("正确率")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(accuracy)%")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(accuracy >= 80 ? .green : accuracy >= 60 ? .orange : .red)
            }
            
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    // 进度
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: accuracy >= 80 ? [Color.green, Color.green.opacity(0.7)] :
                                        accuracy >= 60 ? [Color.orange, Color.orange.opacity(0.7)] :
                                        [Color.red, Color.red.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 1.2), value: progress)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                progress = CGFloat(accuracy) / 100.0
            }
        }
    }
}
