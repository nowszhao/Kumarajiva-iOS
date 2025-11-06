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
# 启用 RPM Fusion Free 和 Nonfree 仓库
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 然后安装 FFmpeg
sudo dnf install ffmpeg

# 安装依赖库
pip3.8 install flask yt-dlp yt-dlp
pip3.8 install --upgrade yt-dlp

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
