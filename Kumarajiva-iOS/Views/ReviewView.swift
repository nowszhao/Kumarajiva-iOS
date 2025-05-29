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
            
            VStack(spacing: 24) {
                Spacer()
                
                // 成功图标区域
                VStack(spacing: 16) {
                    ZStack {
                        // 背景圆圈 - 简化效果
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 90, height: 90)
                            .scaleEffect(animateCheckmark ? 1.0 : 0.8)
                        
                        // 主图标
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48, weight: .medium))
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
                    VStack(spacing: 6) {
                        Text("今日学习完成!")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("正确率: \(calculateAccuracy(progress))%")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.secondary, Color.secondary.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .opacity(animateCheckmark ? 1.0 : 0)
                    .animation(.easeInOut(duration: 0.6).delay(0.5), value: animateCheckmark)
                }
                
                // 统计卡片区域 - 简化版本
                HStack(spacing: 12) {
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
                .padding(.horizontal, 20)
                
                // 准确率进度条 - 简化版本
                CompactAccuracyView(accuracy: calculateAccuracy(progress))
                    .opacity(animateStats ? 1.0 : 0)
                    .animation(.easeInOut(duration: 0.8).delay(0.9), value: animateStats)
                    .padding(.horizontal, 20)
                
                Spacer()
                
                // 重新开始按钮
                Button(action: onReset) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                        Text("重新开始")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .opacity(animateStats ? 1.0 : 0)
                .scaleEffect(animateStats ? 1.0 : 0.9)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.0), value: animateStats)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            animateCheckmark = true
            animateStats = true
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
        VStack(spacing: 8) {
            // 图标区域
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
            }
            
            // 数值和标题
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// 简化准确率显示组件
struct CompactAccuracyView: View {
    let accuracy: Int
    @State private var progress: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("正确率")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(accuracy)%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accuracy >= 80 ? .green : accuracy >= 60 ? .orange : .red)
            }
            
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    
                    // 进度
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: accuracy >= 80 ? [Color.green, Color.green.opacity(0.7)] :
                                        accuracy >= 60 ? [Color.orange, Color.orange.opacity(0.7)] :
                                        [Color.red, Color.red.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 1.0), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                progress = CGFloat(accuracy) / 100.0
            }
        }
    }
}
