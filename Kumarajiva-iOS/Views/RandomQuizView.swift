//
//  RandomQuizView.swift
//  Kumarajiva-iOS
//
//  Created by Assistant on 2024/12/19.
//

import SwiftUI

// MARK: - Data Models
enum RandomQuizQuestionType: String, CaseIterable {
    case listening = "听力模式"
    case definition = "释义模式"
    case word = "单词模式"
}

struct RandomQuizQuestion: Identifiable {
    let id: UUID
    let word: VocabularyItem
    let type: RandomQuizQuestionType
    let questionText: String
    let options: [String]
    let correctAnswer: String
}

struct RandomQuizView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vocabularyViewModel = VocabularyViewModel.shared
    
    @State private var isLoading = false
    @State private var error: String?
    @State private var questions: [RandomQuizQuestion] = []
    @State private var currentQuestionIndex = 0
    @State private var selectedAnswerIndex: Int?
    @State private var showingResult = false
    @State private var isCompleted = false
    @State private var correctAnswers = 0
    
    private let totalQuestions = 10
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if isLoading {
                    LoadingView()
                } else if let error = error {
                    ErrorView(error: error) {
                        Task {
                            await generateRandomQuiz()
                        }
                    }
                } else if isCompleted {
                let progress = Progress(
                    id: 0,
                    date: DateFormatter().string(from: Date()),
                    currentWordIndex: 0,
                    totalWords: questions.count,
                    completed: 1,
                    correct: correctAnswers
                )
                RandomQuizCompletionView(
                    progress: progress,
                    onReset: {
                        reset()
                        Task {
                            await generateRandomQuiz()
                        }
                    },
                    onDismiss: {
                        dismiss()
                    }
                )
            } else if !questions.isEmpty {
                QuizContentView(
                    question: questions[currentQuestionIndex],
                    questionIndex: currentQuestionIndex,
                    totalQuestions: questions.count,
                    selectedAnswer: selectedAnswerIndex != nil ? questions[currentQuestionIndex].options[selectedAnswerIndex!] : nil,
                    showingResult: showingResult,
                    onSelectAnswer: selectAnswer,
                    onSubmitAnswer: submitAnswer,
                    onNextQuestion: nextQuestion
                )
            }
            }
            .navigationTitle("随机测验")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await generateRandomQuiz()
        }
    }
    
    // MARK: - Quiz Logic
    
    private func generateRandomQuiz() async {
        isLoading = true
        error = nil
        
        do {
            // 确保词汇数据已加载
            if vocabularyViewModel.vocabularies.isEmpty {
                await vocabularyViewModel.loadVocabularies()
            }
            
            // 筛选出已掌握的单词
            let masteredWords = vocabularyViewModel.vocabularies.filter { $0.mastered > 0 }
            guard masteredWords.count >= totalQuestions else {
                error = "已掌握的单词数量不足，至少需要\(totalQuestions)个单词"
                isLoading = false
                return
            }
            
            let selectedWords = Array(masteredWords.shuffled().prefix(totalQuestions))
            var generatedQuestions: [RandomQuizQuestion] = []
            
            for word in selectedWords {
                let questionType = RandomQuizQuestionType.allCases.randomElement()!
                let question = createQuestion(for: word, type: questionType, allWords: masteredWords)
                generatedQuestions.append(question)
            }
            
            await MainActor.run {
                self.questions = generatedQuestions
                self.currentQuestionIndex = 0
                self.selectedAnswerIndex = nil
                self.showingResult = false
                self.isCompleted = false
                self.correctAnswers = 0
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "生成测验失败：\(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func createQuestion(for word: VocabularyItem, type: RandomQuizQuestionType, allWords: [VocabularyItem]) -> RandomQuizQuestion {
        let otherWords = allWords.filter { $0.word != word.word }.shuffled()
        let primaryDefinition = word.definitions.first?.meaning ?? "无定义"
        
        switch type {
        case .listening:
            let options = ([word] + Array(otherWords.prefix(3))).shuffled().map { "\($0.word) - \($0.definitions.first?.meaning ?? "")" }
            let correctAnswer = "\(word.word) - \(primaryDefinition)"
            return RandomQuizQuestion(
                id: UUID(),
                word: word,
                type: .listening,
                questionText: "请听发音，选择正确的单词和解释",
                options: options,
                correctAnswer: correctAnswer
            )
            
        case .definition:
            let options = ([primaryDefinition] + Array(otherWords.prefix(3).map { $0.definitions.first?.meaning ?? "" })).shuffled()
            return RandomQuizQuestion(
                id: UUID(),
                word: word,
                type: .definition,
                questionText: "\(word.word) 的含义是？",
                options: options,
                correctAnswer: primaryDefinition
            )
            
        case .word:
            let options = ([word.word] + Array(otherWords.prefix(3).map { $0.word })).shuffled()
            return RandomQuizQuestion(
                id: UUID(),
                word: word,
                type: .word,
                questionText: "\(primaryDefinition) 对应的单词是？",
                options: options,
                correctAnswer: word.word
            )
        }
    }
    
    private func selectAnswer(_ answer: String) {
        guard !showingResult else { return }
        
        if let index = questions[currentQuestionIndex].options.firstIndex(of: answer) {
            selectedAnswerIndex = index
        }
    }
    
    private func submitAnswer() {
        guard selectedAnswerIndex != nil else { return }
        
        let currentQuestion = questions[currentQuestionIndex]
        let selectedAnswer = currentQuestion.options[selectedAnswerIndex!]
        
        if selectedAnswer == currentQuestion.correctAnswer {
            correctAnswers += 1
        }
        
        showingResult = true
    }
    
    private func nextQuestion() {
        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            selectedAnswerIndex = nil
            showingResult = false
        } else {
            isCompleted = true
        }
    }
    
    private func reset() {
        questions = []
        currentQuestionIndex = 0
        selectedAnswerIndex = nil
        showingResult = false
        isCompleted = false
        correctAnswers = 0
        error = nil
    }
}



// MARK: - 错误视图
struct ErrorView: View {
    let error: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(error)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("重试") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}



// MARK: - 测验内容视图
struct QuizContentView: View {
    let question: RandomQuizQuestion
    let questionIndex: Int
    let totalQuestions: Int
    let selectedAnswer: String?
    let showingResult: Bool
    let onSelectAnswer: (String) -> Void
    let onSubmitAnswer: () -> Void
    let onNextQuestion: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 进度条
            ProgressHeader(
                current: questionIndex + 1,
                total: totalQuestions,
                percentage: Double(questionIndex + 1) / Double(totalQuestions)
            )
            
            ScrollView {
                VStack(spacing: 24) {
                    // 题目卡片
                    RandomQuizQuestionCard(question: question)
                    
                    // 选项列表
                    OptionsView(
                        question: question,
                        selectedAnswer: selectedAnswer,
                        showingResult: showingResult,
                        onSelectAnswer: onSelectAnswer
                    )
                }
                .padding(.top, 20)
            }
            
            // 底部按钮
            BottomButton(
                showingResult: showingResult,
                isLastQuestion: questionIndex >= totalQuestions - 1,
                hasSelectedAnswer: selectedAnswer != nil,
                onSubmit: onSubmitAnswer,
                onNext: onNextQuestion
            )
        }
    }
}



// MARK: - 题目卡片
struct RandomQuizQuestionCard: View {
    let question: RandomQuizQuestion
    
    var body: some View {
        VStack(spacing: 20) {
            // 题目类型标签
            HStack {
                Text(question.type.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(typeColor)
                    .cornerRadius(12)
                
                Spacer()
            }
            
            // 题目内容
            VStack(spacing: 16) {
                if question.type == .listening {
                    // 听力模式：显示发音按钮
                    ListeningQuestionView(word: question.word)
                } else {
                    // 其他模式：显示文本
                    Text(question.questionText)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(typeColor.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    private var typeColor: Color {
        switch question.type {
        case .listening: return .blue
        case .definition: return .green
        case .word: return .orange
        }
    }
}

// MARK: - 听力题目视图
struct ListeningQuestionView: View {
    let word: VocabularyItem
    @State private var isPlaying = false
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("请听发音，选择正确的单词和解释")
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Button(action: playPronunciation) {
                ZStack {
                    // 外部脉动圆环
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: isPulsing ? 110 : 90, height: isPulsing ? 110 : 90)
                        .animation(
                            Animation.easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                    
                    // 中间圆环
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: isPulsing ? 95 : 80, height: isPulsing ? 95 : 80)
                        .animation(
                            Animation.easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: true)
                                .delay(0.1),
                            value: isPulsing
                        )
                    
                    // 主按钮背景
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
                    
                    // 图标
                    Image(systemName: isPlaying ? "pause.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isPlaying ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPlaying)
        }
    }
    
    private func playPronunciation() {
        isPlaying = true
        isPulsing = true
        AudioService.shared.playPronunciation(word: word.word, le: "en") {
            self.isPlaying = false
            // 保持脉动效果持续一段时间后停止
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.isPulsing = false
            }
        }
    }
}

// MARK: - 选项视图
struct OptionsView: View {
    let question: RandomQuizQuestion
    let selectedAnswer: String?
    let showingResult: Bool
    let onSelectAnswer: (String) -> Void
    
    private let optionLabels = ["A", "B", "C", "D"]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(question.options.enumerated()), id: \.element) { index, option in
                // 对于听力模式，在未提交答案前隐藏单词部分
                if question.type == .listening && !showingResult {
                    // 只显示解释部分，完全隐藏单词
                    let components = option.components(separatedBy: " - ")
                    let explanation = components.count > 1 ? components[1] : ""
                    OptionButton(
                        label: optionLabels[index],
                        text: explanation,
                        isSelected: selectedAnswer == option,
                        isCorrect: nil
                    ) {
                        onSelectAnswer(option)
                    }
                } else {
                    OptionButton(
                        label: optionLabels[index],
                        text: option,
                        isSelected: selectedAnswer == option,
                        isCorrect: showingResult ? question.correctAnswer == option : nil
                    ) {
                        onSelectAnswer(option)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - 选项按钮
struct OptionButton: View {
    let label: String
    let text: String
    let isSelected: Bool
    let isCorrect: Bool?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 选项标签
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(labelColor)
                    .frame(width: 24, height: 24)
                    .background(labelBackground)
                    .clipShape(Circle())
                
                // 选项内容
                Text(text)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 结果图标
                if let isCorrect = isCorrect {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isCorrect ? .green : .red)
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: shadowColor, radius: 4, y: 2)
        }
        .disabled(isCorrect != nil)
    }
    
    private var labelColor: Color {
        if let isCorrect = isCorrect {
            return .white
        }
        return isSelected ? .white : .secondary
    }
    
    private var labelBackground: Color {
        if let isCorrect = isCorrect {
            return isCorrect ? .green : .red
        }
        return isSelected ? .blue : Color(.systemGray5)
    }
    
    private var backgroundColor: Color {
        if let isCorrect = isCorrect {
            return isCorrect ? Color.green.opacity(0.05) : Color.red.opacity(0.05)
        }
        return isSelected ? Color.blue.opacity(0.05) : Color(.systemBackground)
    }
    
    private var borderColor: Color {
        if let isCorrect = isCorrect {
            return isCorrect ? .green.opacity(0.3) : .red.opacity(0.3)
        }
        return isSelected ? .blue.opacity(0.3) : Color(.systemGray4)
    }
    
    private var shadowColor: Color {
        Color.black.opacity(isSelected ? 0.08 : 0.04)
    }
}

// MARK: - 底部按钮
struct BottomButton: View {
    let showingResult: Bool
    let isLastQuestion: Bool
    let hasSelectedAnswer: Bool
    let onSubmit: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        VStack {
            if showingResult {
                Button(action: onNext) {
                    Text(isLastQuestion ? "查看结果" : "下一题")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.blue)
                        .cornerRadius(16)
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                }
            } else {
                Button(action: onSubmit) {
                    Text("提交答案")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(hasSelectedAnswer ? Color.blue : Color.gray)
                        .cornerRadius(16)
                        .shadow(color: (hasSelectedAnswer ? Color.blue : Color.gray).opacity(0.3), radius: 8, y: 4)
                }
                .disabled(!hasSelectedAnswer)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 1, y: -1)
    }
}

// MARK: - 随机测验完成视图
struct RandomQuizCompletionView: View {
    let progress: Progress
    let onReset: () -> Void
    let onDismiss: () -> Void
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
                        Text("随机测验完成!")
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
                
                // 操作按钮区域
                HStack(spacing: 16) {
                    // 返回按钮
                    Button(action: onDismiss) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 14, weight: .medium))
                            Text("返回")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color(.systemBackground))
                                )
                        )
                    }
                    
                    // 再来一次按钮
                    Button(action: onReset) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                            Text("再来一次")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.blue)
                        )
                    }
                }
                .opacity(animateStats ? 1.0 : 0)
                .scaleEffect(animateStats ? 1.0 : 0.9)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.2), value: animateStats)
                .padding(.bottom, 40)
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



#Preview {
    RandomQuizView()
}