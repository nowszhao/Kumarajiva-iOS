import SwiftUI

struct ReviewView: View {
    @StateObject private var viewModel = ReviewViewModel()
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if let quiz = viewModel.currentQuiz {
                    QuizView(quiz: quiz, progress: viewModel.progress,viewModel:viewModel) { isCorrect in
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
                    EmptyStateView()
                }
            }
            // .navigationTitle("今日回顾")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                Text(viewModel.error ?? "")
            }
        }
        .task {
            await viewModel.loadTodayWords()
        }
    }
}

// 完成视图组件
struct CompletionView: View {
    let progress: Progress
    let onReset: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            // 顶部图标
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .padding(.top, 60)
            
            // 完成信息
            VStack(spacing: 16) {
                Text("今日学习完成!")
                    .font(.title.bold())
                    .foregroundColor(.primary)
                
                Text("正确率: \(calculateAccuracy(progress))%")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // 统计卡片
            HStack(spacing: 20) {
                StatCard(title: "总题数", value: "\(progress.totalWords)")
                StatCard(title: "正确数", value: "\(progress.correct)")
            }
            .padding(.horizontal)
            
            Spacer()
            
            // 重新开始按钮
            Button(action: onReset) {
                Text("重新开始")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.blue)
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
    
    private func calculateAccuracy(_ progress: Progress) -> Int {
        guard progress.totalWords > 0 else { return 0 }
        return Int((Double(progress.correct) / Double(progress.totalWords)) * 100)
    }
}

// 统计卡片组件
struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}
