import SwiftUI

struct QuizView: View {
    let quiz: Quiz
    let progress: Progress?
    let viewModel: ReviewViewModel
    let onAnswer: (Bool) -> Void
   
    
    @State private var selectedAnswer: Word.Definition?
    @State private var showingResult = false
    @State private var hasSubmitted = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 进度头部
                ProgressHeader(
                    current: (progress?.currentWordIndex ?? 0) + 1,
                    total: progress?.totalWords ?? 0,
                    percentage: Double(progress?.completed ?? 0) / Double(progress?.totalWords ?? 1)
                )
                
                // 问题内容
                QuestionCard(quiz: quiz, word: viewModel.words[progress?.currentWordIndex ?? 0])
                
                // 使用新的选项列表组件
                OptionsListView(
                    options: quiz.options,
                    selectedAnswer: selectedAnswer,
                    showingResult: showingResult,
                    correctAnswer: quiz.correctAnswer
                ) { definition in
                    guard !hasSubmitted else { return }
                    selectedAnswer = definition
                    showingResult = true
                    hasSubmitted = true
                }
                
                if showingResult {
                    // 单词展示卡片
                    WordCard(quiz: quiz)
                    
                    // 下一题按钮
                    NextButton {
                        if let selected = selectedAnswer {
                            onAnswer(selected.meaning == quiz.correctAnswer)
                        }
                        selectedAnswer = nil
                        showingResult = false
                        hasSubmitted = false
                        
                        
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGray6))
    }
}

// 进度头部组件
struct ProgressHeader: View {
    let current: Int
    let total: Int
    let percentage: Double
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("题目 \(current)/\(total)")
                    .font(.title3.bold())
                Spacer()
                Text("\(Int(percentage * 100))%")
                    .font(.title3.bold())
                    .foregroundColor(.blue)
            }
            
            ProgressBar(value: percentage)
        }
        .padding(.horizontal)
    }
}

// 进度条组件
struct ProgressBar: View {
    let value: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 8)
                    .cornerRadius(4)
                
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: geometry.size.width * value, height: 8)
                    .cornerRadius(4)
            }
        }
        .frame(height: 8)
    }
}

// 问题卡片组件
struct QuestionCard: View {
    let quiz: Quiz
    let word : Word
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 添加新词/复习标签
            HStack(spacing: 8) {
                Text(word.isNew ?? false ? "新词" : "复习")
                    .font(.system(size: 13))
                    .foregroundColor(word.isNew ?? false ? .orange : .blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(word.isNew ?? false ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                    )
                
                Spacer()
            }
            
            // 记忆方法
            if let method = quiz.memoryMethod {
                VStack(alignment: .leading, spacing: 8) {
                    Text("场景例句")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    
                    Text(method)
                        .font(.system(size: 17))
                        .lineSpacing(4)
                        .lineLimit(nil)
                    
                    Button(action: {
                        AudioService.shared.playPronunciation(word: method)
                    }){
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
          
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// 选项列表组件
struct OptionsListView: View {
    let options: [Quiz.Option]
    let selectedAnswer: Word.Definition?
    let showingResult: Bool
    let correctAnswer: String?
    let onSelect: (Word.Definition) -> Void
    
    private let optionLabels = ["A", "B", "C", "D"]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.element.definition) { index, option in
                AnswerOptionButton(
                    label: optionLabels[index],
                    option: option.toDefinition,
                    isSelected: selectedAnswer?.meaning == option.definition,
                    isCorrect: showingResult ? correctAnswer == option.definition : nil
                ) {
                    onSelect(option.toDefinition)
                }
            }
        }
        .padding(.horizontal)
    }
}

// 答案选项按钮组件
struct AnswerOptionButton: View {
    let label: String
    let option: Word.Definition
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.meaning)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(option.pos)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
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

// 单词卡片组件
struct WordCard: View {
    let quiz: Quiz
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 单词部分
            VStack(alignment: .leading, spacing: 8) {
                Text("单词")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                
                HStack(alignment: .center, spacing: 12) {
                    Text(quiz.word)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    
                    if let phonetic = quiz.phonetic {
                        Button(action: {
                            AudioService.shared.playPronunciation(word: quiz.word)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                                Text(phonetic)
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }
                    }
                }
            }
            
            // 分隔线
            Divider()
                .background(Color.gray.opacity(0.1))
            
            // 释义部分
            VStack(alignment: .leading, spacing: 16) {
                Text("释义")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                
                ForEach(quiz.definitions.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1).")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(quiz.definitions[index].meaning)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                            
                            Text(quiz.definitions[index].pos)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// 下一题按钮组件
struct NextButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("下一题")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.blue)
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
} 
