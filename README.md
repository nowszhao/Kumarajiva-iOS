# Kumarajiva-iOS

[![iOS](https://img.shields.io/badge/iOS-15.0+-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-3.0+-green.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Kumarajiva 是一款智能英语学习应用，通过间隔重复和记忆技巧帮助用户有效地记忆和复习英语词汇。采用现代 iOS 开发技术栈，提供流畅的用户体验和强大的学习功能。

|  |  |  | 
| :---: | :---: | :---: | 
| ![image](./images/screen1.jpg) | ![image](./images/screen2.jpg) | ![image](./images/screen3.jpg) | 
| ![image](./images/screen4.jpg) | ![image](./images/screen5.jpg) |  | 

## ✨ 项目特色

### 🧠 智能学习算法
- **间隔重复算法**: 科学的记忆曲线，优化复习时机
- **个性化推荐**: 基于学习历史智能调整学习内容
- **自适应难度**: 根据用户表现动态调整题目难度

### 🎵 多模态音频体验
- **双TTS引擎**: 有道TTS + Microsoft Edge TTS
- **智能语音**: 支持中英文混合发音
- **播放控制**: 可调节速度(0.5x-2.0x)、循环播放、锁屏控制
- **批量播放**: 高效的音频复习模式

### 🎤 语音练习系统
- **WhisperKit集成**: 本地语音识别，保护隐私
- **智能评分**: 发音准确度实时评估
- **录音回放**: 对比学习，持续改进
- **进度追踪**: 语音练习历史记录

### 🔐 安全认证系统
- **GitHub OAuth**: 便捷的第三方登录
- **JWT Token**: 现代化的认证机制
- **Keychain存储**: iOS原生安全存储
- **自动刷新**: 无感知的Token续期

## 🏗️ 技术架构

### 核心技术栈
```
Frontend: SwiftUI + MVVM
Backend: Node.js API (Fastify)
Database: SQLite3
Authentication: GitHub OAuth + JWT
Audio: AVFoundation + TTS Services
Speech: WhisperKit + Custom Scoring
Storage: Keychain + UserDefaults
```

### 项目结构
```
Kumarajiva-iOS/
├── Models/              # 数据模型层
│   ├── Word.swift       # 单词数据模型
│   ├── Quiz.swift       # 测验数据模型
│   ├── History.swift    # 历史记录模型
│   └── ...
├── Views/               # SwiftUI 视图层
│   ├── ReviewView.swift # 复习界面
│   ├── HistoryView.swift# 历史记录界面
│   ├── QuizView.swift   # 测验界面
│   └── ...
├── ViewModels/          # MVVM 业务逻辑层
│   ├── ReviewViewModel.swift
│   ├── HistoryViewModel.swift
│   └── ...
├── Services/            # 服务层
│   ├── APIService.swift      # API通信服务
│   ├── AuthService.swift     # 认证服务
│   ├── AudioService.swift    # 音频播放服务
│   ├── EdgeTTSService.swift  # Edge TTS服务
│   ├── WhisperKitService.swift # 语音识别服务
│   └── ...
└── Utils/               # 工具类
    └── PronounceURLGenerator.swift
```

### 核心服务说明

#### 🔌 APIService
- RESTful API 通信
- 自动认证头注入
- 错误处理和重试机制
- 请求/响应日志记录

#### 🔐 AuthService
- GitHub OAuth 流程管理
- JWT Token 生命周期管理
- Keychain 安全存储
- 自动登录状态检查

#### 🎵 AudioService
- 多TTS服务集成
- 播放队列管理
- 锁屏媒体控制
- 播放速度控制

#### 🎤 WhisperKitService
- 本地语音识别
- 发音评分算法
- 词汇匹配分析
- 实时反馈系统

## 主要功能

### 1. 智能复习系统
- 个性化测验系统的每日词汇复习
- 采用间隔重复算法，确保最佳学习效果
- 交互式测验界面，即时反馈
- 追踪每次复习的学习进度

### 2. 记忆增强
- 为每个单词提供记忆技巧和情境例句
- 支持单词和记忆提示的语音发音
- 多种学习模式加强记忆：
  - 仅单词发音
  - 仅记忆方法
  - 单词和记忆方法结合
  - 最高分语音播放

### 3. 全面的历史记录
- 详细的学习历史和复习统计
- 多种筛选选项：
  - 新学单词
  - 已掌握单词
  - 复习中的单词
  - 答错的单词
- 可视化进度展示，包含正确率
- 批量音频播放，提高复习效率

### 4. 语音练习功能
- WhisperKit 本地语音识别
- 智能发音评分系统
- 录音历史管理
- 最高分记录追踪
- 可视化发音分析

### 5. 个人进度面板
- 学习数据总览
- 进度追踪：
  - 新学单词数
  - 复习中的单词数
  - 已掌握的单词数
  - 总词汇量
- 学习统计图表
- 成就系统

## 🛠️ 开发环境

### 技术要求
- **iOS**: 15.0 或更高版本
- **Xcode**: 14.0 或更高版本
- **Swift**: 5.7 或更高版本
- **设备**: iPhone 和 iPad 支持
- **网络**: 需要网络连接用于数据同步

### 依赖库
- **WhisperKit**: 本地语音识别
- **AVFoundation**: 音频播放和录制
- **SwiftUI**: 用户界面框架
- **Foundation**: 基础框架

## 🚀 快速开始

### 安装步骤

1. **克隆代码仓库**
```bash
git clone https://github.com/yourusername/Kumarajiva-iOS.git
cd Kumarajiva-iOS
```

2. **配置后端服务**
```bash
# 启动后端API服务 (详见 API Docs/)
cd api
npm install
node src/app.js
```

3. **打开项目**
```bash
open Kumarajiva-iOS.xcodeproj
```

4. **配置项目**
- 在 Xcode 中选择开发团队
- 配置 Bundle Identifier
- 确保后端API服务正常运行

5. **构建并运行**
- 选择目标设备或模拟器
- 按 `Cmd + R` 运行项目

### 配置说明

#### API 服务配置
在 `APIService.swift` 中配置后端服务地址：
```swift
private let baseURL = "http://your-api-server:3000/api"
```

#### OAuth 配置
确保 `Info.plist` 中配置了正确的 URL Scheme：
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>kumarajiva-ios</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>kumarajiva-ios</string>
        </array>
    </dict>
</array>
```

## 📱 使用指南

### 1. **首次使用**
   - 使用 GitHub 账号登录
   - 完成初始设置
   - 开始第一次学习

### 2. **每日复习**
   - 在"今日回顾"标签页进行每日复习
   - 完成每个单词的测验
   - 查看本次学习进度和正确率

### 3. **历史记录**
   - 进入"历史记录"标签页
   - 按不同类别筛选单词
   - 使用批量播放功能进行音频复习
   - 查看每个单词的详细统计数据

### 4. **语音练习**
   - 选择单词进行语音练习
   - 长按录音按钮开始录制
   - 查看发音评分和建议
   - 回放录音进行对比学习

### 5. **个人资料与设置**
   - 在"我的"标签页查看学习统计
   - 自定义播放设置
   - 调整TTS服务和播放速度
   - 追踪总体学习进度

## 🔧 开发指南

### 代码规范
- 遵循 Swift 官方编码规范
- 使用 MVVM 架构模式
- 保持代码注释的完整性
- 单元测试覆盖核心功能

### 贡献指南
1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

### 调试技巧
- 使用 Xcode 内置调试工具
- 查看控制台日志输出
- 利用断点调试功能
- 使用 Instruments 进行性能分析

## 📊 性能优化

### 内存管理
- 合理使用 `weak` 和 `unowned` 引用
- 及时释放不需要的资源
- 避免循环引用

### 网络优化
- 实现请求缓存机制
- 使用适当的超时设置
- 处理网络错误和重试

### 用户体验
- 实现流畅的动画效果
- 优化启动时间
- 提供离线功能支持

## 🤝 贡献

欢迎贡献代码、报告问题或提出建议！请查看 [贡献指南](CONTRIBUTING.md) 了解详细信息。

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详细信息。

## 🙏 致谢

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - 本地语音识别
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) - 现代化UI框架
- [AVFoundation](https://developer.apple.com/av-foundation/) - 音频处理框架

## 📞 联系方式

- 项目主页: [GitHub Repository](https://github.com/yourusername/Kumarajiva-iOS)
- 问题反馈: [Issues](https://github.com/yourusername/Kumarajiva-iOS/issues)
- 邮箱: your.email@example.com

---

⭐️ 如果这个项目对您有帮助，请给我们一个星标！


