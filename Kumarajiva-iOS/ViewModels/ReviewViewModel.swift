import Foundation

@MainActor
class ReviewViewModel: ObservableObject {
    @Published var words: [Word] = []
    @Published var currentQuiz: Quiz?
    @Published var progress: Progress?
    @Published var isLoading = false
    @Published var error: String?
    
    private var currentWordIndex = 0
    private let authService = AuthService.shared
    
    func loadTodayWords() async {
        isLoading = true
        do {
            // 并行执行这两个请求
            async let progressTask = APIService.shared.getProgress()
            async let wordsTask = APIService.shared.getTodayWords()
            
            // 等待两个请求都完成
            let (fetchedProgress, fetchedWords) = await (try progressTask, try wordsTask)
            
            // 更新状态
            self.progress = fetchedProgress
            self.words = fetchedWords
            
            // 设置当前索引
            currentWordIndex = fetchedProgress.currentWordIndex
            
            // 加载当前单词的测验
            if currentWordIndex < words.count {
                try await loadQuiz(for: words[currentWordIndex].word)
            } else {
                currentQuiz = nil
            }
        } catch {
            handleError(error)
        }
        isLoading = false
    }
    
    func loadQuiz(for word: String) async throws {
        currentQuiz = try await APIService.shared.getQuiz(word: word)
        print("🔍 Quiz loaded for word: \(word)")
        print("🔍 memoryMethod: '\(currentQuiz?.memoryMethod ?? "nil")'")
        print("🔍 memoryMethod isEmpty: \(currentQuiz?.memoryMethod?.isEmpty ?? true)")
    }
    
    func submitAnswer(word: String, isCorrect: Bool) async {
        do {
            // Record the answer on the server
            _ = try await APIService.shared.submitReview(word: word, result: isCorrect)

            // Update progress using the new updateProgress endpoint.
            if let prevProgress = progress {
                let newCurrentIndex = prevProgress.currentWordIndex + 1
                let newCompleted = prevProgress.completed + 1
                let newCorrect = prevProgress.correct + (isCorrect ? 1 : 0)
                _ = try await APIService.shared.updateProgress(
                    currentWordIndex: newCurrentIndex,
                    completed: newCompleted,
                    correct: newCorrect
                )
            }

            // Fetch the updated progress from the server
            progress = try await APIService.shared.getProgress()
            currentWordIndex = progress?.currentWordIndex ?? 0

            if currentWordIndex < words.count {
                try await loadQuiz(for: words[currentWordIndex].word)
            } else {
                // No more words to review
                currentQuiz = nil
            }
        } catch {
            handleError(error)
        }
    }
    
    func reset() async {
        isLoading = true
        do {
            // Reset progress first
            progress = try await APIService.shared.resetProgress()
            // Then reload words
            words = try await APIService.shared.getTodayWords()
            currentWordIndex = 0
            if let firstWord = words.first {
                try await loadQuiz(for: firstWord.word)
            }
        } catch {
            handleError(error)
        }
        isLoading = false
    }
    
    private func handleError(_ error: Error) {
        if let apiError = error as? APIError, case .unauthorized = apiError {
            // 认证失败，自动登出
            authService.logout()
            self.error = "登录已过期，请重新登录"
        } else {
            self.error = error.localizedDescription
        }
    }
} 
