import Foundation
import AVFoundation
import WhisperKit

@MainActor
class WhisperKitService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = WhisperKitService()
    
    // Published properties
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var recordingTime: TimeInterval = 0
    @Published var wordResults: [WordMatchResult] = []
    @Published var isModelLoading = false
    @Published var modelLoadingProgress: Float = 0.0
    @Published var modelError: String? = nil
    
    // 添加实时识别相关属性
    @Published var isTranscribing = false
    @Published var interimResult = ""
    @Published var transcriptionProgress: Float = 0.0
    
    // New download status properties
    @Published var isModelDownloading = false
    @Published var downloadProgress: Float = 0.0
    @Published var downloadedModelSize: WhisperModelSize?
    @Published var modelDownloadState: ModelDownloadState = .idle
    
    // Private properties
    private var whisperKit: WhisperKit?
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var modelIsReady = false
    
    // 添加流式识别相关属性
    private var audioPlayer: AVAudioPlayer?
    private var transcriptionTask: Task<Void, Never>?
    
    // Model download state enum
    enum ModelDownloadState: Equatable {
        case idle
        case downloading(progress: Float)
        case downloadComplete
        case loading(progress: Float) 
        case ready
        case failed(error: String)
        
        var description: String {
            switch self {
            case .idle: return "待下载"
            case .downloading(let progress): return "下载中 \(Int(progress * 100))%"
            case .downloadComplete: return "下载完成"
            case .loading(let progress): return "加载中 \(Int(progress * 100))%"
            case .ready: return "可用"
            case .failed(let error): return "错误: \(error)"
            }
        }
        
        // Implementation of Equatable
        static func == (lhs: ModelDownloadState, rhs: ModelDownloadState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case (.downloading(let lhsProgress), .downloading(let rhsProgress)):
                return lhsProgress == rhsProgress
            case (.downloadComplete, .downloadComplete):
                return true
            case (.loading(let lhsProgress), .loading(let rhsProgress)):
                return lhsProgress == rhsProgress
            case (.ready, .ready):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }
    
    override private init() {
        super.init()
        // Check if model exists but delay loading until needed
        checkModelStatus()
    }
    
    // New method to just check if model exists without loading it
    private func checkModelStatus() {
        Task {
            do {
                print("WhisperKitService: Checking model status...")
                // Initialize config to check
                let modelName = UserSettings.shared.whisperModelSize.rawValue
                
                // 获取文档目录URL
                guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw NSError(domain: "WhisperKitService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "无法获取文档目录"])
                }
                
                // 构建模型目录路径
                let modelStorageDir = "huggingface/models/argmaxinc/whisperkit-coreml"
                let modelStorageURL = documentsURL.appendingPathComponent(modelStorageDir)
                let modelDirectoryName = modelName
                let modelDirectoryURL = modelStorageURL.appendingPathComponent(modelDirectoryName)
                
                print("WhisperKitService: Checking model at path: \(modelDirectoryURL.path)")
                
                // Check if we have a saved model path in UserDefaults
                if let savedModelPath = UserDefaults.standard.string(forKey: "whisperkit_model_path_\(modelName)") {
                    print("WhisperKitService: Found saved model path: \(savedModelPath)")
                    
                    // Verify the saved path exists and is valid
                    let savedModelURL = URL(fileURLWithPath: savedModelPath)
                    if FileManager.default.fileExists(atPath: savedModelPath) {
                        print("WhisperKitService: Saved model path exists, validating...")
                        
                        // If the saved path is valid, use it
                        if await validateModelIntegrity(at: savedModelURL) {
                            print("WhisperKitService: Saved model is valid")
                            downloadedModelSize = UserSettings.shared.whisperModelSize
                            modelDownloadState = .ready
                            
                            // 自动预加载模型，如果用户选择了WhisperKit作为语音识别服务
                            if UserSettings.shared.speechRecognitionServiceType == .whisperKit {
                                print("WhisperKitService: WhisperKit is the selected service, preloading model...")
                                // Load the model if it's not already loaded
                                if whisperKit == nil && !modelIsReady && !isModelLoading {
                                    loadWhisperKit()
                                }
                            }
                            return
                        } else {
                            print("WhisperKitService: Saved model is invalid, will check standard location")
                            // Clear invalid saved path
                            UserDefaults.standard.removeObject(forKey: "whisperkit_model_path_\(modelName)")
                        }
                    } else {
                        print("WhisperKitService: Saved model path doesn't exist, will check standard location")
                        // Clear invalid saved path
                        UserDefaults.standard.removeObject(forKey: "whisperkit_model_path_\(modelName)")
                    }
                }
                
                // Ensure the model storage directory exists
                if !FileManager.default.fileExists(atPath: modelStorageURL.path) {
                    try FileManager.default.createDirectory(at: modelStorageURL, withIntermediateDirectories: true)
                    print("WhisperKitService: Created model storage directory")
                    modelDownloadState = .idle
                    return
                }
                
                // 检查模型完整性
                if await validateModelIntegrity(at: modelDirectoryURL) {
                    print("WhisperKitService: Model found and validated")
                    downloadedModelSize = UserSettings.shared.whisperModelSize
                    modelDownloadState = .ready
                    
                    // Save the valid model path
                    UserDefaults.standard.set(modelDirectoryURL.path, forKey: "whisperkit_model_path_\(modelName)")
                    
                    // 自动预加载模型，如果用户选择了WhisperKit作为语音识别服务
                    if UserSettings.shared.speechRecognitionServiceType == .whisperKit {
                        print("WhisperKitService: WhisperKit is the selected service, preloading model...")
                        // Load the model if it's not already loaded
                        if whisperKit == nil && !modelIsReady && !isModelLoading {
                            loadWhisperKit()
                        }
                    }
                } else {
                    print("WhisperKitService: Model files incomplete or corrupted, need to download")
                    modelDownloadState = .idle
                }
            } catch {
                print("WhisperKitService: Error checking model status: \(error)")
                modelDownloadState = .idle
            }
        }
    }
    
    // 检查模型完整性
    private func validateModelIntegrity(at modelDirectoryURL: URL) async -> Bool {
        let fileManager = FileManager.default
        
        // 检查目录是否存在
        guard fileManager.fileExists(atPath: modelDirectoryURL.path) else {
            print("WhisperKitService: Model directory does not exist")
            return false
        }
        
        do {
            // 获取目录内容
            let contents = try fileManager.contentsOfDirectory(at: modelDirectoryURL, includingPropertiesForKeys: nil)
            
            // Print detailed directory contents for debugging
            print("WhisperKitService: Directory contents:")
            for (index, item) in contents.enumerated() {
                let attributes = try fileManager.attributesOfItem(atPath: item.path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                print("  \(index). \(item.lastPathComponent) - \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
            }
            
            // 检查是否有文件
            if contents.isEmpty {
                print("WhisperKitService: Model directory is empty")
                return false
            }
            
            print("WhisperKitService: Found \(contents.count) files in model directory")
            
            // WhisperKit models use .mlmodelc and .mlpackage files rather than .bin
            // Check for the expected files in downloaded WhisperKit models
            let requiredFiles = ["config.json", ".mlmodelc", ".mlpackage"]
            var missingFiles: [String] = []
            
            for filePattern in requiredFiles {
                let hasFile = contents.contains { $0.path.contains(filePattern) }
                if !hasFile {
                    print("WhisperKitService: Missing required model file type: \(filePattern)")
                    missingFiles.append(filePattern)
                }
            }
            
            // Check for specific required components
            let requiredComponents = ["AudioEncoder", "TextDecoder", "MelSpectrogram"]
            var missingComponents: [String] = []
            
            for component in requiredComponents {
                let hasComponent = contents.contains { $0.lastPathComponent.contains(component) }
                if !hasComponent {
                    print("WhisperKitService: Missing required model component: \(component)")
                    missingComponents.append(component)
                }
            }
            
            if !missingFiles.isEmpty {
                print("WhisperKitService: Missing required file types: \(missingFiles.joined(separator: ", "))")
                return false
            }
            
            if !missingComponents.isEmpty {
                print("WhisperKitService: Missing required components: \(missingComponents.joined(separator: ", "))")
                return false
            }
            
            // If the download reported success and we have all required components, trust that
            // The official WhisperKit download is actually a combined .mlmodelc/.mlpackage format
            // rather than the traditional .bin format for language models
            
            // Since we're using the official download method, we'll try loading the model directly
            return await testModelLoading(modelDirectoryURL: modelDirectoryURL)
        } catch {
            print("WhisperKitService: Error checking model integrity: \(error)")
            return false
        }
    }
    
    // 测试模型加载
    private func testModelLoading(modelDirectoryURL: URL) async -> Bool {
        do {
            // 创建一个临时配置来测试模型
            let modelName = UserSettings.shared.whisperModelSize.rawValue
            let testConfig = WhisperKitConfig(
                modelFolder: modelDirectoryURL.path,
                verbose: true
            )
            
            // 尝试初始化模型但不完全加载
            // 这里只是测试模型文件是否可以被正确读取
            print("WhisperKitService: Testing model loading...")
            
            // 设置超时
            let testTask = Task {
                do {
                    _ = try await WhisperKit(testConfig)
                    return true
                } catch {
                    print("WhisperKitService: Model loading test failed: \(error)")
                    return false
                }
            }
            
            // 等待测试结果，但设置超时
            let result = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    return await testTask.value
                }
                
                group.addTask {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5秒超时
                    testTask.cancel()
                    return false
                }
                
                // 返回第一个完成的任务结果
                return await group.next() ?? false
            }
            
            return result
            
        } catch {
            print("WhisperKitService: Error during model loading test: \(error)")
            return false
        }
    }
    
    // 删除模型文件
    private func deleteModelFiles(at modelDirectoryURL: URL) async throws {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: modelDirectoryURL.path) {
            print("WhisperKitService: Deleting corrupted model files...")
            try fileManager.removeItem(at: modelDirectoryURL)
            print("WhisperKitService: Corrupted model files deleted")
        }
    }
    
    private func loadWhisperKit() {
        Task {
            do {
                isModelLoading = true
                modelLoadingProgress = 0.1
                modelDownloadState = .loading(progress: 0.1)
                
                // 获取模型名称
                let modelName = UserSettings.shared.whisperModelSize.rawValue
                
                // 获取文档目录URL
                guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw NSError(domain: "WhisperKitService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "无法获取文档目录"])
                }
                
                // 构建模型目录路径
                let modelStorageDir = "huggingface/models/argmaxinc/whisperkit-coreml"
                let modelStorageURL = documentsURL.appendingPathComponent(modelStorageDir)
                let modelDirectoryName = modelName
                let modelDirectoryURL = modelStorageURL.appendingPathComponent(modelDirectoryName)
                
                print("WhisperKit config: WhisperKit.WhisperKitConfig")
                print("WhisperKit model: \(modelName)")
                print("WhisperKit model directory: \(modelDirectoryURL.path)")

                // WhisperKit progress updates
                modelLoadingProgress = 0.3
                modelDownloadState = .loading(progress: 0.3)
                
                // Check if model needs downloading by checking if model files exist locally
                let fileManager = FileManager.default
                
                // 验证模型完整性
                let modelValid = await validateModelIntegrity(at: modelDirectoryURL)
                
                if !modelValid {
                    // 模型不存在或已损坏，需要手动下载，设置状态为待下载
                    modelDownloadState = .idle
                    modelError = "Model not found or invalid. Please download it first."
                    isModelLoading = false
                    return
                }
                
                // Now that we have the model, initialize WhisperKit
                modelDownloadState = .loading(progress: 0.5)
                print("WhisperKitService: Initializing WhisperKit...")
                
                // 配置WhisperKit
                let config = WhisperKitConfig(
                    modelFolder: modelDirectoryURL.path,
                    verbose: true
                )
                
                whisperKit = try await WhisperKit(config)
                try await whisperKit?.loadModels()
                
                // 确保模型已初始化成功
                if whisperKit != nil {
                    modelLoadingProgress = 1.0
                    modelIsReady = true
                    modelError = nil
                    modelDownloadState = .ready
                    downloadedModelSize = UserSettings.shared.whisperModelSize
                    
                    print("WhisperKitService: WhisperKit initialized successfully with model: \(modelName)")
                    
                    // Save model path to UserDefaults for persistence verification
                    UserDefaults.standard.set(modelDirectoryURL.path, forKey: "whisperkit_model_path_\(modelName)")
                } else {
                    throw NSError(domain: "WhisperKitService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize WhisperKit model"])
                }
            } catch {
                modelError = "Failed to load WhisperKit model: \(error.localizedDescription)"
                modelDownloadState = .failed(error: error.localizedDescription)
                print("WhisperKitService: Initialization error: \(error)")
            }
            
            isModelLoading = false
            isModelDownloading = false
        }
    }
    
    // Add a new public method for manual download
    func downloadModelManually() {
        Task {
            do {
                guard !isModelLoading && !isModelDownloading else {
                    print("WhisperKitService: Model operation already in progress")
                    return
                }
                
                isModelDownloading = true
                modelDownloadState = .downloading(progress: 0.0)
                
                // 获取模型名称
                let modelName = UserSettings.shared.whisperModelSize.rawValue
                
                // 获取文档目录URL
                guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw NSError(domain: "WhisperKitService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "无法获取文档目录"])
                }
                
                // 构建模型目录路径
                let modelStorageDir = "huggingface/models/argmaxinc/whisperkit-coreml"
                let modelStorageURL = documentsURL.appendingPathComponent(modelStorageDir)
                let modelDirectoryName = modelName
                let modelDirectoryURL = modelStorageURL.appendingPathComponent(modelDirectoryName)
                
                // Check if model needs downloading by checking if model files exist locally
                let fileManager = FileManager.default
                
                // 删除可能存在的损坏文件
                if fileManager.fileExists(atPath: modelDirectoryURL.path) {
                    try fileManager.removeItem(at: modelDirectoryURL)
                    print("WhisperKitService: Removed existing invalid model directory")
                }
                
                // 确保模型目录存在
                if !fileManager.fileExists(atPath: modelStorageURL.path) {
                    try fileManager.createDirectory(at: modelStorageURL, withIntermediateDirectories: true)
                    print("WhisperKitService: Created model storage directory")
                }
                
                // 下载模型
                try await downloadModel(modelName: modelName) { progress in
                    self.downloadProgress = progress
                    self.modelDownloadState = .downloading(progress: progress)
                }
                
                isModelDownloading = false
                downloadProgress = 1.0
                downloadedModelSize = UserSettings.shared.whisperModelSize
                modelDownloadState = .downloadComplete
                
                // Verify the download was successful
                let modelIsValid = await validateModelIntegrity(at: modelDirectoryURL)
                if !modelIsValid {
                    throw NSError(domain: "WhisperKitService", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Model download failed - files are missing or corrupted"])
                }
                
                // Save model path to UserDefaults for persistence verification
                UserDefaults.standard.set(modelDirectoryURL.path, forKey: "whisperkit_model_path_\(modelName)")
                
                // After successful download, load the model
                loadWhisperKit()
                
            } catch {
                modelError = "Failed to download WhisperKit model: \(error.localizedDescription)"
                modelDownloadState = .failed(error: error.localizedDescription)
                print("WhisperKitService: Download error: \(error)")
                isModelDownloading = false
            }
        }
    }
    
    // Helper method to download a model with progress updates
    private func downloadModel(modelName: String, progressCallback: @escaping (Float) -> Void) async throws {
        let fileManager = FileManager.default
        
        // 获取模型大小
        let expectedSizeMB = UserSettings.shared.whisperModelSize.modelSize
        print("开始下载模型: \(modelName)，预期大小: \(expectedSizeMB)MB")
        
        // 获取文档目录URL
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "WhisperKitService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "无法获取文档目录"])
        }
        
        // 创建模型存储目录
        let modelStorageDir = "huggingface/models/argmaxinc/whisperkit-coreml"
        let modelStorageURL = documentsURL.appendingPathComponent(modelStorageDir)
        
        // 创建模型特定目录
        let modelDirectoryName = modelName
        let modelDirectoryURL = modelStorageURL.appendingPathComponent(modelDirectoryName)
        
        // 如果模型目录不存在，创建它
        if !fileManager.fileExists(atPath: modelDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
            } catch {
                throw NSError(domain: "WhisperKitService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "创建模型目录失败: \(error.localizedDescription)"])
            }
        }
        
        // 首先尝试使用WhisperKit的官方下载方法
        print("尝试使用WhisperKit官方下载方法...")
        do {
            let repoName = "argmaxinc/whisperkit-coreml"
            _ = try await WhisperKit.download(variant: modelName, from: repoName, progressCallback: { progress in
                DispatchQueue.main.async {
                    progressCallback(Float(progress.fractionCompleted))
                }
            })
            print("官方下载方法成功")
            return
        } catch {
            print("官方下载方法失败: \(error.localizedDescription)")
        }
    }
    
    // Reload model when user changes model size
    func reloadModel() {
        guard !isModelLoading && !isModelDownloading else {
            print("WhisperKitService: Cannot reload model while another operation is in progress")
            return
        }
        
        // First check if we need to download or if the model is already available
        Task {
            do {
                print("WhisperKitService: Reloading model...")
                // Initialize config to check
                let modelName = UserSettings.shared.whisperModelSize.rawValue
                
                // 获取文档目录URL
                guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw NSError(domain: "WhisperKitService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "无法获取文档目录"])
                }
                
                // 构建模型目录路径 - 使用应用程序支持目录而不是文档目录，以确保持久性
                let modelStorageDir = "huggingface/models/argmaxinc/whisperkit-coreml"
                let modelStorageURL = documentsURL.appendingPathComponent(modelStorageDir)
                let modelDirectoryName = modelName
                let modelDirectoryURL = modelStorageURL.appendingPathComponent(modelDirectoryName)
                
                // 确保模型存储目录存在
                if !FileManager.default.fileExists(atPath: modelStorageURL.path) {
                    try FileManager.default.createDirectory(at: modelStorageURL, withIntermediateDirectories: true)
                    print("WhisperKitService: Created model storage directory at \(modelStorageURL.path)")
                }
                
                // Check if the model already exists and is valid
                if await validateModelIntegrity(at: modelDirectoryURL) {
                    print("WhisperKitService: Model exists and is valid, loading directly")
                    downloadedModelSize = UserSettings.shared.whisperModelSize
                    
                    // Reset and load the model
                    modelIsReady = false
                    whisperKit = nil
                    loadWhisperKit()
                } else {
                    print("WhisperKitService: Model needs to be downloaded manually")
                    // Set state to idle so user knows they need to download
                    modelIsReady = false
                    whisperKit = nil
                    modelDownloadState = .idle
                    modelError = "Model not found or invalid. Please download it first."
                }
            } catch {
                print("WhisperKitService: Error checking model before reload: \(error)")
                modelDownloadState = .idle
                modelError = "Error checking model status: \(error.localizedDescription)"
            }
        }
    }
    
    // Start recording
    func startRecording() async {
        // Check if model is ready, if not, load it first
        if whisperKit == nil || !modelIsReady {
            // Only load if not already loading
            if !isModelLoading {
                print("WhisperKit not ready, checking if model exists...")
                
                // First check if the model exists
                let modelName = UserSettings.shared.whisperModelSize.rawValue
                
                // 获取文档目录URL
                guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("WhisperKitService: Failed to get documents directory")
                    return
                }
                
                // 构建模型目录路径
                let modelStorageDir = "huggingface/models/argmaxinc/whisperkit-coreml"
                let modelStorageURL = documentsURL.appendingPathComponent(modelStorageDir)
                let modelDirectoryURL = modelStorageURL.appendingPathComponent(modelName)
                
                // Check model integrity
                let modelExists = await validateModelIntegrity(at: modelDirectoryURL)
                
                if modelExists {
                    // If model exists, load it
                    print("WhisperKit: Model exists, loading it...")
                    loadWhisperKit()
                    
                    // Wait for model to load with timeout
                    for _ in 0..<50 { // 5 seconds timeout (100ms * 50)
                        if modelIsReady {
                            break
                        }
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    }
                    
                    if !modelIsReady {
                        print("Failed to load WhisperKit model in time")
                        return
                    }
                } else {
                    // If model doesn't exist, notify that download is needed
                    print("WhisperKit: Model doesn't exist, download required")
                    modelDownloadState = .idle
                    modelError = "Model not found. Please download it first."
                    return
                }
            } else {
                print("WhisperKit is currently loading, please wait...")
                return
            }
        }
        
        // Set up recording session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        // Create directory for recordings if needed
        let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDirectory = containerURL.appendingPathComponent("KumarajivaWhisperRecordings", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: recordingsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: recordingsDirectory, 
                                                       withIntermediateDirectories: true,
                                                       attributes: nil)
            } catch {
                print("Failed to create recordings directory: \(error)")
            }
        }
        
        // Create recording file with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "whisper_recording_\(timestamp).wav"
        recordingURL = recordingsDirectory.appendingPathComponent(fileName)
        
        // Configure audio recorder settings (16kHz WAV for WhisperKit)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        // Start audio recorder
        do {
            if let url = recordingURL {
                audioRecorder = try AVAudioRecorder(url: url, settings: settings)
                audioRecorder?.delegate = self
                audioRecorder?.record()
            }
        } catch {
            print("Could not start WhisperKit recording: \(error)")
            return
        }
        
        // Reset state
        recognizedText = ""
        interimResult = ""
        wordResults = []
        isRecording = true
        
        // Start timer to track recording duration
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordingTime += 0.1
            
            // 每2秒进行一次实时识别（可调整）
            if Int(self.recordingTime * 10) % 20 == 0 && self.recordingTime > 1.0 {
                Task {
                    await self.processInterimRecording()
                }
            }
        }
    }
    
    // 实时处理录音进行中的音频
    private func processInterimRecording() async {
        // 确保模型已加载
        if whisperKit == nil || !modelIsReady {
            print("Cannot process interim recording: WhisperKit not ready")
            return
        }
        
        guard let url = recordingURL, let whisperKit = whisperKit, isRecording else { 
            print("Cannot process interim recording: recording URL is nil or not recording")
            return 
        }
        
        do {
            // 创建临时文件
            let tempURL = url.deletingPathExtension().appendingPathExtension("temp.wav")
            try FileManager.default.copyItem(at: url, to: tempURL)
            
            // 在后台处理临时文件
            Task {
                do {
                    isTranscribing = true
                    let result = try await whisperKit.transcribe(audioPath: tempURL.path)
                    
                    if let transcription = result.first {
                        self.interimResult = transcription.text
                        print("Interim transcription: \(transcription.text)")
                    }
                    
                    try? FileManager.default.removeItem(at: tempURL)
                    isTranscribing = false
                } catch {
                    print("Error with interim transcription: \(error)")
                    isTranscribing = false
                }
            }
        } catch {
            print("Error preparing interim audio: \(error)")
        }
    }
    
    // Stop recording and process audio
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        
        print("WhisperKitService: 停止录音")
        audioRecorder?.stop()
        isRecording = false
        
        // Stop and invalidate timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Reset audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to reset audio session: \(error)")
        }
        
        // Process the recording with WhisperKit
        print("WhisperKitService: 开始处理录音")
        await processRecording()
        
        print("WhisperKitService: 录音处理完成，返回URL: \(recordingURL?.path ?? "nil")")
        return recordingURL
    }
    
    // Process the recorded audio file with WhisperKit
    private func processRecording() async {
        guard let url = recordingURL, let whisperKit = whisperKit, modelIsReady else {
            print("Cannot process recording: WhisperKit not ready or recording URL is nil")
            return
        }
        
        do {
            isTranscribing = true
            transcriptionProgress = 0.0
            print("开始处理录音文件: \(url.path)")
            
            // 使用流式识别的回调
            let result = try await whisperKit.transcribe(audioPath: url.path)
            
            // Manually update progress to complete state after transcription is done
            self.transcriptionProgress = 1.0
            
            // WhisperKit 0.12+ returns an array of TranscriptionResult
            if let transcription = result.first {
                self.recognizedText = transcription.text
                print("WhisperKit transcription result: \(transcription.text)")
                
                // 确保interimResult也被清除，避免UI显示冲突
                self.interimResult = ""
            } else {
                print("WhisperKit transcription returned empty result")
            }
            
            isTranscribing = false
            
            // 确保在处理完录音后，状态被正确更新
            print("录音处理完成，识别结果: \(self.recognizedText)")
        } catch {
            print("Error transcribing audio with WhisperKit: \(error)")
            isTranscribing = false
            // 确保在发生错误时，状态也被正确更新
            print("录音处理失败")
        }
    }
    
    // Calculate score by comparing recognized text with the expected text
    func calculateScore(expectedText: String) async -> Int {
        guard !recognizedText.isEmpty else { 
            print("WhisperKit calculateScore: recognizedText is empty, returning 0")
            return 0 
        }
        
        print("WhisperKit calculateScore: 开始计算得分")
        print("WhisperKit calculateScore: 预期文本: \(expectedText)")
        print("WhisperKit calculateScore: 识别文本: \(recognizedText)")
        
        // Update word results for highlighting
        wordResults = analyzeWordMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Extract English text if needed and normalize
        let expectedEnglish = extractEnglishText(expectedText)
        let normalizedExpected = normalizeText(expectedEnglish.isEmpty ? expectedText : expectedEnglish)
        let normalizedRecognized = normalizeText(recognizedText)
        
        print("WhisperKit calculateScore: 提取的英文: \(expectedEnglish)")
        print("WhisperKit calculateScore: 标准化预期文本: \(normalizedExpected)")
        print("WhisperKit calculateScore: 标准化识别文本: \(normalizedRecognized)")
        
        // 改进的单词匹配算法
        let expectedWords = normalizedExpected.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let recognizedWords = normalizedRecognized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        var matchedWords = 0
        var totalWords = expectedWords.count
        
        // 如果没有提取到英文单词，使用更宽松的方法
        if totalWords == 0 {
            totalWords = max(1, recognizedWords.count)
            let expectedText = normalizeText(expectedText)
            
            print("WhisperKit calculateScore: 未提取到英文单词，使用宽松匹配")
            
            // 尝试匹配任何识别出的单词与预期文本
            for word in recognizedWords {
                if expectedText.contains(word) && word.count > 1 {
                    matchedWords += 1
                    print("WhisperKit calculateScore: 匹配词: \(word)")
                }
            }
        } else {
            // 改进的匹配算法：使用模糊匹配
            print("WhisperKit calculateScore: 使用模糊匹配算法")
            for recognizedWord in recognizedWords {
                // 检查是否有相似的单词
                for expectedWord in expectedWords {
                    if isSimilar(recognizedWord, expectedWord) {
                        matchedWords += 1
                        print("WhisperKit calculateScore: 匹配词: \(recognizedWord) 与 \(expectedWord)")
                        break
                    }
                }
            }
        }
        
        // 计算得分为0-100之间的百分比
        let score = Int((Double(matchedWords) / Double(totalWords)) * 100)
        
        // 确保得分在0-100范围内
        let finalScore = min(100, max(0, score))
        print("WhisperKit calculateScore: 匹配词数: \(matchedWords), 总词数: \(totalWords), 得分: \(finalScore)")
        
        return finalScore
    }
    
    // 检查两个单词是否相似（简单的模糊匹配）
    private func isSimilar(_ word1: String, _ word2: String) -> Bool {
        // 完全匹配
        if word1 == word2 {
            return true
        }
        
        // 如果单词长度相差太大，认为不匹配
        if abs(word1.count - word2.count) > 2 {
            return false
        }
        
        // 简单的编辑距离检查（可以使用更复杂的算法如Levenshtein距离）
        // 这里我们只检查单词的开头是否匹配
        let minLength = min(word1.count, word2.count)
        let prefix1 = word1.prefix(minLength)
        let prefix2 = word2.prefix(minLength)
        
        // 如果前缀相似度高，认为单词相似
        let commonLength = zip(prefix1, prefix2).filter { $0 == $1 }.count
        let similarity = Double(commonLength) / Double(minLength)
        
        return similarity > 0.7 // 70%相似度阈值
    }
    
    // Analyze word matching for highlighting
    private func analyzeWordMatching(expectedText: String, recognizedText: String) -> [WordMatchResult] {
        // Extract English text if needed and normalize
        let englishExpectedText = extractEnglishText(expectedText)
        let finalExpectedText = englishExpectedText.isEmpty ? expectedText : englishExpectedText
        
        let normalizedExpected = normalizeText(finalExpectedText)
        let normalizedRecognized = normalizeText(recognizedText)
        
        let expectedWords = normalizedExpected.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let recognizedWords = normalizedRecognized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        // Create a temporary array to build the final results
        var temporaryResults: [WordMatchResult?] = Array(repeating: nil, count: max(expectedWords.count, recognizedWords.count) * 2)
        
        var expectedWordMatched = Array(repeating: false, count: expectedWords.count)
        var currentTempIndex = 0
        
        // Step 1: Process recognized words
        for (recIndex, recognizedWord) in recognizedWords.enumerated() {
            // 检查是否有精确匹配或相似匹配
            var foundMatch = false
            var matchIndex = -1
            
            for (expIndex, expectedWord) in expectedWords.enumerated() {
                if !expectedWordMatched[expIndex] && (expectedWord == recognizedWord || isSimilar(expectedWord, recognizedWord)) {
                    foundMatch = true
                    matchIndex = expIndex
                    break
                }
            }
            
            if foundMatch && matchIndex >= 0 {
                // If it's a matching word
                expectedWordMatched[matchIndex] = true
                
                // Check if there are missing words that need to be inserted first
                for i in 0..<matchIndex {
                    if !expectedWordMatched[i] {
                        temporaryResults[currentTempIndex] = WordMatchResult(
                            word: expectedWords[i],
                            type: .missing,
                            originalIndex: currentTempIndex
                        )
                        expectedWordMatched[i] = true
                        currentTempIndex += 1
                    }
                }
                
                // Add the matching word
                temporaryResults[currentTempIndex] = WordMatchResult(
                    word: recognizedWord,
                    type: .matched,
                    originalIndex: currentTempIndex
                )
                currentTempIndex += 1
            } else {
                // If it's an extra word
                temporaryResults[currentTempIndex] = WordMatchResult(
                    word: recognizedWord,
                    type: .extra,
                    originalIndex: currentTempIndex
                )
                currentTempIndex += 1
            }
        }
        
        // Step 2: Add any remaining missing words
        for (expIndex, expectedWord) in expectedWords.enumerated() {
            if !expectedWordMatched[expIndex] {
                temporaryResults[currentTempIndex] = WordMatchResult(
                    word: expectedWord,
                    type: .missing,
                    originalIndex: currentTempIndex
                )
                currentTempIndex += 1
            }
        }
        
        // Filter out nil values and return results
        let results = temporaryResults.compactMap { $0 }
        return results
    }
    
    // AVAudioRecorderDelegate method
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("WhisperKit recording failed")
        }
    }
    
    // Helper methods
    private func normalizeText(_ text: String) -> String {
        let lowercasedText = text.lowercased()
        
        // Remove punctuation
        let punctuationCharacterSet = CharacterSet.punctuationCharacters
        let textWithoutPunctuation = lowercasedText
            .components(separatedBy: punctuationCharacterSet)
            .joined(separator: " ")
        
        // Normalize whitespace
        let whitespaceCharacterSet = CharacterSet.whitespacesAndNewlines
        let components = textWithoutPunctuation
            .components(separatedBy: whitespaceCharacterSet)
            .filter { !$0.isEmpty }
        
        return components.joined(separator: " ")
    }
    
    // Extract English text from a mixed text
    private func extractEnglishText(_ text: String) -> String {
        // First, try to extract text in parentheses (both English and Chinese)
        let parenthesesRegex = try? NSRegularExpression(pattern: "\\([^\\)]+\\)|（[^）]+）", options: [])
        if let matches = parenthesesRegex?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           !matches.isEmpty {
            var extractedText = ""
            
            // Extract the text inside parentheses
            for match in matches {
                if let range = Range(match.range, in: text) {
                    var content = String(text[range])
                    // Remove the parentheses
                    content = content.trimmingCharacters(in: CharacterSet(charactersIn: "()（）"))
                    extractedText += " " + content
                }
            }
            
            if !extractedText.isEmpty {
                return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Fallback to original method if no parentheses found
        var englishWords: [String] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        
        for word in words {
            // Check if word contains mainly English characters
            let englishCharacterSet = CharacterSet.letters.subtracting(
                CharacterSet(charactersIn: "àáâäæãåāèéêëēėęîïíīįìôöòóœøōõûüùúū")
            )
            let nonEnglishCharacterSet = CharacterSet.letters.subtracting(englishCharacterSet)
            
            // Consider a word English if it contains mainly English characters
            let englishChars = word.unicodeScalars.filter { englishCharacterSet.contains($0) }.count
            let nonEnglishChars = word.unicodeScalars.filter { nonEnglishCharacterSet.contains($0) }.count
            
            if englishChars > nonEnglishChars && word.count > 1 {
                englishWords.append(word)
            }
        }
        
        return englishWords.joined(separator: " ")
    }
}

extension WhisperKit {
    // Helper method to get the model directory URL
    static func getModelDirectoryURL(config: WhisperKitConfig) async throws -> URL {
        // 使用与示例代码相同的目录结构
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 使用与示例代码相同的路径结构
        let modelStorageDir = "huggingface/models/argmaxinc/whisperkit-coreml"
        let modelStorageURL = documentsURL.appendingPathComponent(modelStorageDir)
        
        // 创建模型特定目录
        let modelDirectoryName = config.model!
        let modelDirectoryURL = modelStorageURL.appendingPathComponent(modelDirectoryName)
        
        // 创建目录（如果不存在）
        if !fileManager.fileExists(atPath: modelStorageURL.path) {
            try fileManager.createDirectory(at: modelStorageURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return modelDirectoryURL
    }
} 
