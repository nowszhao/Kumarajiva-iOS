# 智能解析功能实现文档

## 功能概述

智能解析功能是一个基于LLM的单词深度学习工具，通过AI分析提供：
- 词根拆分和联想记忆法
- 多个场景记忆示例
- 同义词精准辨析
- 完整的音标和释义信息

## 功能特性

### 1. 智能缓存机制
- 解析结果自动保存到本地存储
- 下次访问直接加载缓存，无需重复请求
- 支持强制刷新（重新解析）

### 2. 四种交互状态
- **未解析**: 显示解析按钮，等待用户主动触发
- **解析中**: 显示加载动画和进度提示
- **已解析**: 展示完整解析结果的卡片式布局
- **解析失败**: 显示错误信息和重试按钮

### 3. 现代化UI设计
- 卡片式布局，符合iOS设计规范
- 渐变按钮和阴影效果
- 响应式布局，适配不同屏幕
- 清晰的信息层次和视觉引导

## 技术架构

### 数据模型层
```swift
- WordAnalysis: 主要数据模型
- BasicInfo: 基本信息（音标、释义）
- PhoneticNotation: 音标信息
- SceneMemory: 场景记忆
- SynonymGuidance: 同义词指导
- AnalysisState: 解析状态枚举
```

### 服务层
```swift
- WordAnalysisService: 数据持久化服务
- LLMService: LLM接口调用服务
```

### 视图模型层
```swift
- SpeechPracticeViewModel: 扩展支持智能解析
  - analysisState: 当前解析状态
  - fetchWordAnalysis(): 获取解析结果
  - parseAnalysisResponse(): 解析LLM响应
```

### 视图层
```swift
- IntelligentAnalysisTabView: 主容器视图
- NotAnalyzedView: 未解析状态视图
- AnalyzingView: 解析中状态视图
- AnalysisResultView: 解析结果视图
- AnalysisErrorView: 错误状态视图
- AnalysisCardView: 通用卡片组件
```

## LLM提示词格式

系统使用标准化的提示词格式，确保返回结构化的JSON数据：

```
根据人类记忆原理和人性，我立马记住这个单词且终身难忘。
1、举例：ubiquitous
2、按照 Json 格式输出：
{
    "word": "ubiquitous",
    "basic_info": {
        "phonetic_notation": {
            "British": "/juːˈbɪkwɪtəs/",
            "American": "/juːˈbɪkwɪtəs/"
        },
        "annotation": "adj. 普遍存在的；无处不在的"
    },
    "split_association_method": "...",
    "scene_memory": [...],
    "synonym_precise_guidance": [...]
}

新单词：{word}
```

## 使用流程

1. **进入智能解析页面**: 在跟读练习页面点击"智能解析"tab
2. **触发解析**: 点击"开始解析"按钮
3. **等待结果**: 系统调用LLM接口并解析响应
4. **查看结果**: 以卡片形式展示解析内容
5. **重新解析**: 如需更新结果，点击"重新解析"按钮

## 错误处理

- **网络错误**: 显示网络连接问题提示
- **解析错误**: 显示JSON格式错误提示
- **服务错误**: 显示服务不可用提示
- **超时错误**: 显示请求超时提示

## 性能优化

- **本地缓存**: 避免重复请求相同单词
- **异步处理**: 不阻塞主线程
- **内存管理**: 及时释放不需要的资源
- **状态管理**: 清晰的状态转换逻辑

## 扩展性设计

- **模块化架构**: 各组件职责单一，易于维护
- **配置化提示词**: 可根据需要调整LLM提示词
- **插件化UI**: 卡片组件可复用于其他场景
- **数据迁移**: 支持未来的数据格式升级

## 注意事项

1. 首次使用需要网络连接
2. 解析结果会占用本地存储空间
3. LLM服务需要有效的API配置
4. 建议在WiFi环境下使用以节省流量 