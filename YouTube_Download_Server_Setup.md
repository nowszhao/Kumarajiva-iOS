# YouTube Audio Download Server 部署指南

## 📋 概述

本文档介绍如何部署和配置新的YouTube音频下载服务，从代理模式升级到本地下载模式。

### 🆕 新功能特性

- ✅ 完整下载m4a音频文件和srt英文字幕文件到本地
- ✅ 支持断点续传和下载任务管理
- ✅ 提供HTTP文件服务，支持Range请求
- ✅ 自动缓存管理（12小时过期清理）
- ✅ 下载任务队列和进度跟踪
- ✅ SRT字幕解析和适配现有播放器

### 🔄 架构变化

| 功能 | 旧版本（代理模式） | 新版本（下载模式） |
|------|-------------------|-------------------|
| 音频获取 | 实时代理YouTube流 | 完整下载到本地 |
| 字幕支持 | 不支持 | 支持SRT英文字幕 |
| 断点续传 | 不支持 | 支持 |
| 缓存管理 | 无 | 12小时自动清理 |
| 播放体验 | 依赖网络稳定性 | 本地文件播放 |

## 🚀 后端服务部署

### 1. 环境要求

```bash
# Python 3.8+
python3 --version

# 安装依赖
pip install flask yt-dlp
```

### 2. 服务器配置

```bash
# 创建服务目录
mkdir -p /opt/youtube-download-server
cd /opt/youtube-download-server

# 下载服务脚本
# 将更新后的 youtube_audio_proxy_server.py 放置在此目录

# 创建下载目录
mkdir downloads
chmod 755 downloads

# 确保有足够的磁盘空间（建议至少10GB）
df -h
```

### 3. 启动服务

```bash
# 直接启动（测试用）
python3 youtube_audio_proxy_server.py

# 后台运行（生产环境）
nohup python3 youtube_audio_proxy_server.py > server.log 2>&1 &

# 检查服务状态
curl http://localhost:5000/health
```

### 4. 系统服务配置（可选）

创建systemd服务文件：

```bash
# /etc/systemd/system/youtube-download.service
[Unit]
Description=YouTube Audio Download Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/youtube-download-server
ExecStart=/usr/bin/python3 youtube_audio_proxy_server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

启用服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable youtube-download.service
sudo systemctl start youtube-download.service
sudo systemctl status youtube-download.service
```

### 5. 防火墙配置

```bash
# Ubuntu/Debian
sudo ufw allow 5000

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=5000/tcp
sudo firewall-cmd --reload
```

## 📱 iOS客户端更新

### 1. 新增文件

以下文件已添加到项目：

- `Kumarajiva-iOS/Services/SRTParser.swift` - SRT字幕解析器
- 更新的 `Kumarajiva-iOS/Services/YouTubeAudioExtractor.swift` - 新版API适配

### 2. 主要代码变更

#### YouTubeAudioExtractor.swift
- 从代理模式切换到下载模式
- 新增下载任务管理和状态轮询
- 集成SRT字幕解析
- 支持取消和超时处理

#### PodcastPlayerService.swift
- 更新URL识别逻辑：`/audio` → `/files/audio`
- 优化User-Agent：`1.0` → `2.0`

#### VideoPlayerView.swift
- 适配新的下载API
- 集成SRT字幕显示
- 添加下载状态指示器

### 3. API端点变更

| 功能 | 旧端点 | 新端点 |
|------|--------|--------|
| 获取音频 | `GET /audio?id=VIDEO_ID` | `GET /files/audio?id=VIDEO_ID` |
| 获取字幕 | 不支持 | `GET /files/subtitle?id=VIDEO_ID` |
| 开始下载 | 不适用 | `POST /download?id=VIDEO_ID` |
| 下载状态 | 不适用 | `GET /status?id=VIDEO_ID` |
| 取消下载 | 不适用 | `DELETE /cancel?id=VIDEO_ID` |
| 视频信息 | `GET /info?id=VIDEO_ID` | `GET /info?id=VIDEO_ID` |

## 🔧 配置参数

### 后端服务配置

```python
# 在 youtube_audio_proxy_server.py 中可调整的参数

# 缓存过期时间（小时）
CACHE_EXPIRE_HOURS = 12

# 下载目录
DOWNLOAD_DIR = Path('./downloads')

# 最大轮询时间（秒）
MAX_POLLING_TIME = 600  # 10分钟

# 轮询间隔（秒）
POLLING_INTERVAL = 2.0
```

### iOS客户端配置

```swift
// 在 YouTubeAudioExtractor.swift 中可调整的参数

// 后端服务地址
private let backendBaseURL = "http://107.148.21.15:5000"

// 轮询超时时间
let maxPollingTime: TimeInterval = 600 // 10分钟

// 轮询间隔
let pollingInterval: TimeInterval = 2.0 // 2秒
```

## 📊 监控和日志

### 1. 后端日志

```bash
# 查看实时日志
tail -f /opt/youtube-download-server/youtube_download.log

# 查看服务状态
curl http://localhost:5000/health

# 查看活动任务数量
curl http://localhost:5000/health | jq '.active_tasks'
```

### 2. 磁盘空间监控

```bash
# 检查下载目录大小
du -sh /opt/youtube-download-server/downloads

# 设置定时清理（可选）
# 添加到 crontab
0 */6 * * * find /opt/youtube-download-server/downloads -mtime +0.5 -delete
```

### 3. iOS客户端日志

在Xcode中查看控制台输出，关键日志标签：
- `🎵 [YouTubeExtractor]` - 提取器相关日志
- `📝 [SRTParser]` - SRT解析相关日志
- `🎧 [Player]` - 播放器相关日志
- `📺 [VideoPlayer]` - 视频播放相关日志

## ⚠️ 注意事项

### 1. 性能考虑

- 后端服务器建议至少2GB内存
- 确保有足够的磁盘空间（每个视频5-50MB）
- 网络带宽建议至少10Mbps上行

### 2. 安全考虑

- 仅允许信任的IP访问服务端口
- 定期更新yt-dlp版本：`pip install --upgrade yt-dlp`
- 监控下载目录，防止磁盘满

### 3. 用户体验

- 首次下载需要等待时间，建议有下载进度提示
- 网络不稳定时下载可能失败，支持重试
- SRT字幕可能不是所有视频都有

## 🔄 回滚计划

如果新版本出现问题，可以快速回滚：

### 后端回滚

```bash
# 停止新服务
sudo systemctl stop youtube-download.service

# 恢复旧版本文件
cp youtube_audio_proxy_server.py.backup youtube_audio_proxy_server.py

# 重启服务
python3 youtube_audio_proxy_server.py
```

### iOS客户端回滚

1. 恢复 `YouTubeAudioExtractor.swift` 到旧版本
2. 移除 `SRTParser.swift`
3. 恢复播放器代码中的URL识别逻辑

## 🧪 测试验证

### 1. 后端服务测试

```bash
# 健康检查
curl http://localhost:5000/health

# 测试视频信息获取
curl "http://localhost:5000/info?id=dQw4w9WgXcQ"

# 测试下载任务
curl -X POST "http://localhost:5000/download?id=dQw4w9WgXcQ"

# 检查下载状态
curl "http://localhost:5000/status?id=dQw4w9WgXcQ"

# 测试文件服务
curl -I "http://localhost:5000/files/audio?id=dQw4w9WgXcQ"
```

### 2. iOS客户端测试

1. 选择一个YouTube视频进行播放测试
2. 检查下载进度显示是否正常
3. 验证音频播放功能
4. 检查SRT字幕是否正确显示
5. 测试快进、快退等播放控制

## 🆘 故障排除

### 常见问题

1. **下载失败**
   - 检查yt-dlp版本是否最新
   - 验证YouTube URL是否有效
   - 检查网络连接

2. **音频播放不流畅**
   - 确认文件完整下载
   - 检查iOS设备网络连接
   - 验证Range请求支持

3. **字幕不显示**
   - 检查视频是否有英文字幕
   - 验证SRT文件下载成功
   - 查看SRT解析日志

### 联系支持

如有问题，请提供：
- 后端服务日志
- iOS应用日志
- 具体的YouTube视频链接
- 错误复现步骤 