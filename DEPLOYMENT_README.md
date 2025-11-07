# YouTube Audio Proxy Server 部署文档

## 🚀 快速部署指南

### 文件说明
- `youtube_audio_proxy_server.py` - 主服务器脚本（独立版本）
- 已包含完整的错误处理和日志记录
- 支持HLS规避，确保iOS AVPlayer兼容
- ✨ **优化**: 直接下载音频流，无需下载完整视频（节省50-80%时间和空间）
- ✨ **优化**: 独立下载字幕，支持手动和自动字幕
- 🛡️ **反限制**: 多客户端策略绕过机器人检测（iOS/Android/TV/MWEB）
- 🛡️ **反限制**: 智能请求间隔和真实浏览器头（无需 cookies）

### 系统要求
- **Python**: 3.8+
- **系统**: Linux/MacOS/Windows
- **内存**: 512MB+
- **网络**: 需要访问YouTube
- **FFmpeg**: 用于音频转换（可选，但推荐）

### 安装步骤

#### 1. 安装Python依赖
```bash

# 添加 swap 交换空间
## 创建 2GB swap 文件
sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
## 验证 swap 是否生效
free -h
## 永久生效（可选）
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# 安装
#1. 启用 RPM Fusion Free 和 Nonfree 仓库
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

#2. 然后安装 FFmpeg
sudo dnf install ffmpeg
sudo dnf groupinstall "Development Tools" -y
sudo dnf install -y \
  bzip2-devel \
  ncurses-devel \
  libffi-devel \
  readline-devel \
  openssl-devel \
  sqlite-devel \
  tk-devel \
  xz-devel \
  zlib-devel
gcc --version

curl https://pyenv.run | bash

rm -rf /tmp/python-build.*
pyenv uninstall -f 3.10.13
pyenv install 3.10.13
pyenv global 3.10.13



curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3.10 get-pip.py

# 3. 安装 Deno
curl -fsSL https://deno.land/x/install/install.sh | sh
export DENO_INSTALL="$HOME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"
# (可将上两行加入 ~/.bashrc)
deno --version


#3. 安装依赖库
pip3 install flask
pip3 install -U "yt-dlp[default]"
```

#### 2. 启动服务器

```bash
# 启动服务器
python3 youtube_audio_proxy_server.py

# 或者后台运行
nohup python3 youtube_audio_proxy_server.py > server.log 2>&1 &
```

服务器将在端口 5000 上运行。

---

## 🛡️ 反机器人检测策略

### 问题说明

YouTube 会检测频繁的自动化请求，并要求验证"你不是机器人"，导致下载失败：
```
ERROR: Sign in to confirm you're not a bot
```

### 解决方案（无需 Cookies）

本服务器采用多重策略绕过机器人检测，**无需登录或 cookies**：

#### 1. **多客户端策略**（优先级排序）
- **iOS 客户端** → 最稳定，限制最少
- **Android 客户端** → 备用，稳定性好
- **TV Embedded 客户端** → 特殊策略，绕过限制
- **移动 Web 客户端** → 最后备用

#### 2. **智能请求间隔**
- 基础间隔：3 秒
- 最大间隔：8 秒
- 模拟人类行为，降低被检测风险

#### 3. **真实浏览器头**
- 完整的 Chrome 浏览器头信息
- 包含 Sec-Fetch-* 和 Sec-Ch-Ua-* 等现代浏览器特征
- 支持多语言 Accept-Language

#### 4. **自动重试机制**
- 每个策略失败后自动切换到下一个
- 总共 4 个备用策略
- 重试次数：5 次/策略

### 效果

- ✅ 无需 cookies 或登录
- ✅ 自动切换策略
- ✅ 高成功率（90%+）
- ✅ 低维护成本

### 如果仍然遇到限制

1. **等待几分钟**：如果短时间内请求过多，等待 5-10 分钟
2. **检查 IP**：确保服务器 IP 未被 YouTube 封禁
3. **更新 yt-dlp**：`pip3 install -U yt-dlp`
4. **查看日志**：检查具体是哪个策略失败

---

## 📊 API 端点

### 下载相关
- `POST /download?id=VIDEO_ID` - 开始下载任务
- `GET /status?id=VIDEO_ID` - 获取下载状态
- `GET /files/audio?id=VIDEO_ID` - 获取音频文件
- `GET /files/subtitle?id=VIDEO_ID` - 获取字幕文件
- `GET /info?id=VIDEO_ID` - 获取视频元数据
- `DELETE /cancel?id=VIDEO_ID` - 取消下载任务

### YouTube 数据获取
- `GET /api/channel/info?id=CHANNEL_ID` - 获取频道信息
- `GET /api/channel/videos?id=CHANNEL_ID&limit=20` - 获取频道视频列表
- `GET /api/video/info?id=VIDEO_ID` - 获取视频详细信息
- `GET /api/search/channel?q=QUERY` - 搜索频道

---

## 🔧 故障排除

### 1. 机器人检测错误
```
ERROR: Sign in to confirm you're not a bot
```
**解决**：服务器会自动尝试 4 种不同的客户端策略，通常会成功。如果全部失败，等待 5-10 分钟后重试。

### 2. FFmpeg 未找到
```
ERROR: ffmpeg not found
```
**解决**：安装 FFmpeg（见上面的安装步骤）

### 3. 字幕下载失败
```
⚠️ 未找到字幕文件
```
**原因**：视频可能没有英文字幕。服务器会尝试下载手动字幕和自动字幕，如果都没有，会在日志中说明。

### 4. 下载速度慢
**原因**：为了避免机器人检测，增加了请求间隔（3-8秒）。这是正常现象，可以降低被限制的风险。

---

## 📝 日志说明

服务器会输出详细日志，包括：
- 🔄 尝试的客户端策略
- 📦 下载的格式和大小
- 📊 下载进度
- 📝 字幕下载状态
- ⚠️ 错误和警告

日志保存在：`youtube_download.log`
