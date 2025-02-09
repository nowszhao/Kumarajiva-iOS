import Foundation

@MainActor
class ReviewViewModel: ObservableObject {
    @Published var words: [Word] = []
    @Published var currentQuiz: Quiz?
    @Published var progress: Progress?
    @Published var isLoading = false
    @Published var error: String?
    
    private var currentWordIndex = 0
    
    func loadTodayWords() async {
        isLoading = true
        do {
            // First get progress to know where we left off
            progress = try await APIService.shared.getProgress()
            words = try await APIService.shared.getTodayWords()
            
            // Set current index from progress
            currentWordIndex = progress?.currentWordIndex ?? 0
            print("currentWordIndex:\(currentWordIndex)")
            
            // Load current word's quiz
            if currentWordIndex < words.count {
                try await loadQuiz(for: words[currentWordIndex].word)
            } else {
                currentQuiz = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    func loadQuiz(for word: String) async throws {
        currentQuiz = try await APIService.shared.getQuiz(word: word)
        print("currentQuiz:\(currentQuiz)")
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
            self.error = error.localizedDescription
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
            self.error = error.localizedDescription
        }
        isLoading = false
    }
} 
