# YouTube Audio Proxy Server 部署文档

## 🚀 快速部署指南

### 文件说明
- `youtube_audio_proxy_server.py` - 主服务器脚本（独立版本）
- 已包含完整的错误处理和日志记录
- 支持HLS规避，确保iOS AVPlayer兼容

### 系统要求
- **Python**: 3.8+ 
- **系统**: Linux/MacOS/Windows
- **内存**: 512MB+
- **网络**: 需要访问YouTube
- **FFmpeg**: 用于音频转换（可选，但推荐）

### 安装步骤

#### 1. 安装Python依赖
```bash
pip install flask yt-dlp
```

#### 2. 上传脚本到服务器
将 `youtube_audio_proxy_server.py` 上传到服务器

#### 3. 启动服务
```bash
# 前台运行（测试用）
python3 youtube_audio_proxy_server.py

# 后台运行（生产环境）
nohup python3 youtube_audio_proxy_server.py > youtube_proxy.log 2>&1 &

# 使用systemd管理（推荐）
sudo systemctl start youtube-proxy
```

### 🔧 Systemd 服务配置（推荐）

创建服务文件 `/etc/systemd/system/youtube-proxy.service`:

```ini
[Unit]
Description=YouTube Audio Proxy Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/path/to/your/script
ExecStart=/usr/bin/python3 /path/to/your/script/youtube_audio_proxy_server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

启用并启动服务：
```bash
sudo systemctl daemon-reload
sudo systemctl enable youtube-proxy
sudo systemctl start youtube-proxy
sudo systemctl status youtube-proxy
```

### 🔐 YouTube Cookies 配置（重要）

如果遇到 `Sign in to confirm you're not a bot` 错误，需要配置 YouTube cookies：

#### 快速配置步骤

1. **导出 Cookies**
   - 在浏览器中访问 https://www.youtube.com 并登录
   - 使用浏览器扩展导出 cookies（推荐 Chrome 的 "Get cookies.txt"）
   - 保存为 `cookies.txt`

2. **放置 Cookies 文件**
   ```bash
   # 将 cookies.txt 放在项目根目录，重命名为 youtube_cookies.txt
   cp cookies.txt /path/to/youtube_cookies.txt
   ```

3. **重启服务**
   ```bash
   sudo systemctl restart youtube-proxy
   ```

4. **验证配置**
   ```bash
   curl http://YOUR_SERVER:5000/api/cookies/status
   ```

详细说明请参考 [YOUTUBE_COOKIES_SETUP.md](./YOUTUBE_COOKIES_SETUP.md)

### 📡 API 端点

| 端点 | 方法 | 说明 | 示例 |
|------|------|------|------|
| `/audio` | GET | 获取音频流 | `/audio?id=eUNYgabsP1M` |
| `/info` | GET | 获取视频信息 | `/info?id=eUNYgabsP1M` |
| `/api/cookies/status` | GET | 检查 cookies 配置状态 | `/api/cookies/status` |
| `/api/cookies/diagnose` | GET | 诊断 cookies 问题 | `/api/cookies/diagnose` |
| `/api/test/youtube/<video_id>` | GET | 测试 YouTube 连接 | `/api/test/youtube/dQw4w9WgXcQ` |
| `/health` | GET | 健康检查 | `/health` |
| `/` | GET | 服务信息 | `/` |

### 🔍 测试部署

#### 1. 健康检查
```bash
curl http://YOUR_SERVER:5000/health
```

#### 2. 测试视频信息获取
```bash
curl "http://YOUR_SERVER:5000/info?id=eUNYgabsP1M"
```

#### 3. 测试音频流
```bash
curl -I "http://YOUR_SERVER:5000/audio?id=eUNYgabsP1M"
```

### 📱 iOS应用配置

更新iOS代码中的服务器地址：

```swift
// 在 YouTubeAudioExtractor.swift 中
private let baseURL = "http://YOUR_SERVER:5000"

// 在 PodcastPlayerService.swift 中  
guard let url = URL(string: "http://YOUR_SERVER:5000/info?id=\(videoId)") else {
```

### 📊 日志监控

日志文件位置：
- **标准输出**: `youtube_proxy.log`
- **错误日志**: 同上
- **Systemd日志**: `sudo journalctl -u youtube-proxy -f`

重要日志标识：
- `🎵` - 音频请求
- `ℹ️` - 信息请求
- `✅` - 成功操作
- `❌` - 错误信息
- `📊` - 流量统计

### 🛡️ 安全配置

#### 1. 防火墙配置
```bash
# 开放5000端口
sudo ufw allow 5000
```

#### 2. 反向代理配置（Nginx）
```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 重要：支持Range请求
        proxy_set_header Range $http_range;
        proxy_set_header If-Range $http_if_range;
        proxy_no_cache $http_range $http_if_range;
        proxy_cache_bypass $http_range $http_if_range;
    }
}
```

### 🔧 故障排除

#### 常见问题

1. **依赖安装失败**
   ```bash
   pip install --upgrade pip
   pip install flask yt-dlp
   ```

2. **端口被占用**
   ```bash
   # 查找占用进程
   sudo lsof -i :5000
   # 杀死进程
   sudo kill -9 PID
   ```

3. **YouTube访问受限 / HTTP 403 错误**
   
   这是最常见的问题。快速诊断和修复：
   
   ```bash
   # 运行诊断脚本
   bash diagnose_403.sh
   
   # 或使用 Python 诊断工具
   python3 auto_fix_403.py
   ```
   
   **常见原因和解决方案**：
   - **Cookies 已过期**: 重新导出新的 Cookies 到 `./youtube_cookies.txt`
   - **IP 被限制**: 等待 1-2 小时后重试，或使用 VPN
   - **Cookies 格式错误**: 确保使用 Netscape 格式导出
   - **yt-dlp 版本过旧**: 运行 `pip install --upgrade yt-dlp`
   
   详细说明请参考 [HTTP_403_ADVANCED_FIX.md](./HTTP_403_ADVANCED_FIX.md)

4. **yt-dlp版本过旧**
   ```bash
   pip install --upgrade yt-dlp
   ```

### 📈 性能优化

1. **启用多线程**：脚本已配置 `threaded=True`
2. **增加工作进程**：使用 Gunicorn
   ```bash
   pip install gunicorn
   gunicorn -w 4 -b 0.0.0.0:5000 youtube_audio_proxy_server:app
   ```

### ✅ 部署检查清单

- [ ] Python 3.8+ 已安装
- [ ] 依赖包已安装 (flask, yt-dlp)
- [ ] 脚本已上传到服务器
- [ ] 端口5000已开放
- [ ] 服务已启动并运行
- [ ] 健康检查通过
- [ ] 测试视频信息API成功
- [ ] iOS应用配置已更新
- [ ] 日志监控已配置

### 📞 技术支持

如遇问题，请检查：
1. 服务器日志 `youtube_proxy.log`
2. 系统日志 `journalctl -u youtube-proxy`
3. 网络连接状态
4. YouTube API访问状态

---

**注意**: 请确保服务器有足够的带宽来处理音频流代理，建议至少10Mbps上行带宽。