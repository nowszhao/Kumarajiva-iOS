import SwiftUI
import AVFoundation


// Practice tab content
struct PracticeTabView: View {
    let history: History
    @ObservedObject var viewModel: SpeechPracticeViewModel
    @State private var isExamplePlaying = false
    @State private var showScoreAlert = false
    @State private var isLongPressing = false
    @State private var dragOffset = CGSize.zero
    @State private var isCompleting = false
    @State private var showCancelAlert = false
    @State private var playbackRate: Float = 0.75
    
    private var exampleToShow: String {
        var exampleToShow = "No example available."
        if let method = history.memoryMethod, !method.isEmpty {
            exampleToShow =  method
        } else if !history.examples.isEmpty {
            exampleToShow =  history.examples[0]
        }
        exampleToShow = extractEnglishSentence(exampleToShow) ?? "No example available."
        return exampleToShow
    }
    
    private func extractEnglishSentence(_ input: String) -> String? {
        // 定义兼容中英文括号的正则表达式模式
        let pattern = #"[(（]([A-Za-z ,.'-]+.*?)[)）]"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        
        // 在输入字符串中查找所有匹配项
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        
        // 取最后一个匹配项（通常英文句子在末尾括号）
        guard let lastMatch = matches.last else { return nil }
        
        // 提取捕获组内容并去除前后空格
        let range = lastMatch.range(at: 1)
        guard let swiftRange = Range(range, in: input) else { return nil }
        return String(input[swiftRange]).trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Example section
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        // Word with pronunciation
                        VStack(alignment: .leading, spacing: 2) {
                            Text(history.word)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            if let pronunciation = getPronunciation(history.pronunciation) {
                                Text(pronunciation)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Add part of speech badge
                        if let firstDef = history.definitions.first {
                            Text(firstDef.pos)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Definition section
                    ForEach(history.definitions.prefix(1), id: \.meaning) { definition in
                        HStack(alignment: .top, spacing: 8) {
                            Text("「解释」")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                            
                            Text("\(definition.meaning)")
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    // Example section
//                    HStack(alignment: .top, spacing: 8) {
//                        Text("「例句」")
//                            .font(.system(size: 14, weight: .medium))
//                            .foregroundColor(.blue)
//                        
//                        Text("\(exampleToShow)")
//                            .font(.system(size: 15))
//                            .foregroundColor(.primary)
//                            .fixedSize(horizontal: false, vertical: true)
//                    }
                    
                    // Add Word Collocation section
                    WordCollocationView(word: history.word)
                        .padding(.top, 4)
                    
                    // Play example button with speed options
                    HStack(spacing: 12) {
                        // Play/Stop button
                        let buttonAction = {
                            isExamplePlaying.toggle()
                            if isExamplePlaying {
                                // 创建一个循环播放函数
                                func playExampleInLoop() {
                                    // 如果不再处于播放状态，则停止循环
                                    if !isExamplePlaying {
                                        return
                                    }
                                    
                                    // 播放例句
                                    AudioService.shared.playPronunciation(
                                        word: exampleToShow,
                                        le: "en",
                                        rate: playbackRate,
                                        onCompletion: {
                                            // 播放完成后，等待200ms再次播放
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                // 再次检查是否仍处于播放状态
                                                if self.isExamplePlaying {
                                                    playExampleInLoop()
                                                }
                                            }
                                        }
                                    )
                                }
                                
                                // 开始循环播放
                                let dispatchTime = DispatchTime.now() + 0.1
                                DispatchQueue.main.asyncAfter(deadline: dispatchTime) {
                                    playExampleInLoop()
                                }
                            } else {
                                AudioService.shared.stopPlayback()
                            }
                        }
                        
                        Button(action: buttonAction) {
                            // Extract button appearance to reduce complexity
                            let buttonIcon = isExamplePlaying ? "stop.fill" : "play.fill"
                            let buttonText = isExamplePlaying ? "停止播放" : "播放例句"
                            
                            HStack {
                                Image(systemName: buttonIcon)
                                    .font(.system(size: 12, weight: .medium))
                                Text(buttonText)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                        
                        // Playback rate selection
                        HStack(spacing: 8) {
                            // Define the rates array outside the ForEach
                            let rates: [Float] = [0.5, 0.75, 1.0]
                            
                            ForEach(rates, id: \.self) { rate in
                                let rateButtonAction = {
                                    playbackRate = rate
                                    if isExamplePlaying {
                                        AudioService.shared.setPlaybackRate(rate)
                                    }
                                }
                                
                                Button(action: rateButtonAction) {
                                    // Break up the complex expression into simpler parts
                                    let rateText = String(format: "%.2g", rate) + "x"
                                    let isSelected = playbackRate == rate
                                    let backgroundColor = isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1)
                                    let textColor = isSelected ? Color.blue : Color.gray
                                    
                                    Text(rateText)
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(backgroundColor)
                                        )
                                        .foregroundColor(textColor)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                )
                .padding(.horizontal)
                
                // Recording section
                VStack(spacing: 16) {
                    // Recognized text area
                    VStack(alignment: .leading, spacing: 8) {
                        Text("请朗读：")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if viewModel.wordResults.isEmpty && viewModel.recognizedText.isEmpty {
                            if viewModel.isTranscribing || !viewModel.interimResult.isEmpty {
                                VStack(spacing: 8) {
                                    // Show example sentence in gray
                                    Text(exampleToShow)
                                        .font(.system(size: 15))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.bottom, 4)
                                    
                                    if !viewModel.interimResult.isEmpty {
                                        Text(viewModel.interimResult)
                                            .font(.system(size: 15))
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text("正在识别...")
                                            .font(.system(size: 15))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if viewModel.isTranscribing {
                                        ProgressView(value: viewModel.transcriptionProgress)
                                            .progressViewStyle(LinearProgressViewStyle())
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                                .background(Color(.systemGray6).opacity(0.8))
                                .cornerRadius(8)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Show example sentence in gray
                                    Text(exampleToShow)
                                        .font(.system(size: 15))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                }
                                .padding()
                                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                                .background(Color(.systemGray6).opacity(0.8))
                                .cornerRadius(8)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                // Show example sentence with matched words highlighted
                                ExampleSentenceView(example: exampleToShow, recognizedResults: viewModel.wordResults)
                                
//                                Divider()
                                
                                // Show recognized text with highlighting
//                                HighlightedTextView(results: viewModel.formattedRecognizedText(), viewModel: viewModel)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                            .background(Color(.systemGray6).opacity(0.8))
                            .cornerRadius(8)
                        }
                    }
                    
                    // Recording indicator
                    if viewModel.isRecording {
                        HStack {
                            Text("录音中...")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                            
                            Spacer()
                            
                            if isLongPressing {
                                Text("向右滑动完成，其他方向放弃")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                            }
                            
                            Spacer()
                            
                            Text(viewModel.formatRecordingTime(viewModel.recordingTime))
                                .font(.system(size: 14, weight: .medium))
                                .monospacedDigit()
                        }
                    }
               
                    
                    // Recording button with gesture
                    ZStack {
                        // Determine circle color based on state
                        let circleColor: Color = {
                            if isLongPressing {
                                return isCompleting ? Color.green : Color.red
                            } else {
                                return Color.blue
                            }
                        }()
                        
                        Circle()
                            .fill(circleColor)
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                        
                        // Determine which icon to show
                        if isLongPressing {
                            if isCompleting {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 26))
                                    .foregroundColor(.white)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                            }
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                        }
                        
                        // 添加向右滑动箭头指示(当录音开始时)
                        if isLongPressing && !isCompleting {
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .offset(x: 40)
                            }
                            .frame(width: 120)
                        }
                    }
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if isLongPressing {
                                    // 只允许水平方向的滑动
                                    let horizontalDrag = CGSize(width: gesture.translation.width, height: 0)
                                    dragOffset = horizontalDrag
                                    
                                    // 如果向右滑动超过50，则标记为完成状态
                                    isCompleting = gesture.translation.width > 50
                                }
                            }
                            .onEnded { _ in
                                if isLongPressing {
                                    if isCompleting {
                                        // Extract completion logic to reduce complexity
                                        self.handleCompletedRecording()
                                    } else {
                                        // Extract cancellation logic to reduce complexity
                                        self.handleCancelledRecording()
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onEnded { _ in
                                if !isLongPressing {
                                    isLongPressing = true
                                    dragOffset = .zero
                                    isCompleting = false
                                    viewModel.startRecording()
                                }
                            }
                    )
                    .padding(.vertical, 12)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                )
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .padding(.vertical)
        }
//        .alert(isPresented: $showScoreAlert) {
//            // Extract score message to reduce complexity
//            let scoreTitle = "发音评分"
//            let scoreMessage = "您的发音得分: \(viewModel.currentScore)"
//            let dismissText = "确定"
//            
//            return Alert(
//                title: Text(scoreTitle),
//                message: Text(scoreMessage),
//                dismissButton: .default(Text(dismissText))
//            )
//        }
        .onDisappear {
            // Stop playing example when tab disappears
            if isExamplePlaying {
                AudioService.shared.stopPlayback()
                isExamplePlaying = false
            }
        }
        .onAppear {
            // 确保在视图出现时重置播放状态
            isExamplePlaying = false
            AudioService.shared.stopPlayback()
        }
    }
    
    private func getPronunciation(_ pronunciation: History.Pronunciation?) -> String? {
        guard let pronunciation = pronunciation else { return nil }
        return pronunciation.American.isEmpty ? pronunciation.British : pronunciation.American
    }
    
    private func handleCompletedRecording() {
        // 向右滑动完成录音并保存
        viewModel.stopRecording(word: history.word, example: exampleToShow, shouldSave: true)
        showScoreAlert = true
        
        // 添加延迟以确保状态更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLongPressing = false
            dragOffset = .zero
            isCompleting = false
        }
    }
    
    private func handleCancelledRecording() {
        // 其他方向滑动或就地松手，取消录音
        viewModel.stopRecording(word: history.word, example: exampleToShow, shouldSave: false)
        showCancelAlert = true
        
        // 添加延迟以确保状态更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLongPressing = false
            dragOffset = .zero
            isCompleting = false
        }
    }
    
}
