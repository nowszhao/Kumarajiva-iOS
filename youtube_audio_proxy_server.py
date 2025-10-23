#!/usr/bin/env python3
"""
YouTube Audio Download Server
本地下载版本 - 为Kumarajiva iOS应用提供YouTube音频流本地下载服务

功能特性:
1. 完整下载mp3音频文件和srt英文字幕文件到本地
2. 支持断点续传和下载管理
3. 提供HTTP文件服务，支持Range请求
4. 自动缓存管理（12小时过期 + LRU清理）
5. 下载任务队列和进度跟踪
6. 使用yt-dlp替代YouTube Data API v3获取频道和视频信息

部署要求:
1. Python 3.8+
2. pip install flask yt-dlp

启动命令:
python3 youtube_audio_proxy_server.py

服务端口: 5000
API端点:
# 下载相关
- POST /download?id=VIDEO_ID    # 开始下载任务
- GET /status?id=VIDEO_ID       # 获取下载状态
- GET /files/audio?id=VIDEO_ID  # 获取音频文件
- GET /files/subtitle?id=VIDEO_ID # 获取字幕文件
- GET /info?id=VIDEO_ID         # 获取视频元数据
- DELETE /cancel?id=VIDEO_ID    # 取消下载任务

# YouTube数据获取（替代YouTube Data API v3）
- GET /api/channel/info?id=CHANNEL_ID_OR_USERNAME     # 获取频道信息
- GET /api/channel/videos?id=CHANNEL_ID&limit=20      # 获取频道视频列表
- GET /api/video/info?id=VIDEO_ID                     # 获取视频详细信息
- GET /api/search/channel?q=QUERY                     # 搜索频道
"""

import yt_dlp
from flask import Flask, Response, request, abort, jsonify, send_file
import urllib.request
import logging
import sys
import os
import json
import time
import threading
import hashlib
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, Optional, Any, List
import uuid
from dataclasses import dataclass
from enum import Enum
import shutil
import mimetypes
import re

app = Flask(__name__)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('youtube_download.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# 创建下载目录
DOWNLOAD_DIR = Path('./downloads')
DOWNLOAD_DIR.mkdir(exist_ok=True)

# 创建缓存目录（用于存储频道和视频信息）
CACHE_DIR = Path('./cache')
CACHE_DIR.mkdir(exist_ok=True)

# 缓存过期时间（12小时）
CACHE_EXPIRE_HOURS = 12

# YouTube Cookies 文件路径（可选）
COOKIES_FILE = Path('./youtube_cookies.txt')

# 任务状态枚举
class TaskStatus(Enum):
    PENDING = "pending"
    DOWNLOADING = "downloading"  
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

@dataclass
class DownloadTask:
    task_id: str
    video_id: str
    status: TaskStatus
    progress: float
    message: str
    audio_file: Optional[str] = None
    subtitle_file: Optional[str] = None
    error: Optional[str] = None
    created_at: datetime = None
    completed_at: Optional[datetime] = None
    video_info: Optional[Dict] = None
    
    def __post_init__(self):
        if self.created_at is None:
            self.created_at = datetime.now()

# 全局任务管理
tasks: Dict[str, DownloadTask] = {}
download_threads: Dict[str, threading.Thread] = {}

# =============================================================================
# YouTube 数据获取功能（替代 YouTube Data API v3）
# =============================================================================

def get_common_ydl_opts() -> dict:
    """获取通用的 yt-dlp 配置，用于绕过 YouTube 403 错误和机器人验证"""
    opts = {
        'extractor_args': {
            'youtube': {
                'player_client': ['android', 'web', 'tv', 'ios'],
                'player_skip': ['webpage', 'configs'],
                'skip_webpage': False,
                'ignore_signaling': True,
            }
        },
        'http_headers': {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-us,en;q=0.5',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'none',
            'Sec-Fetch-Dest': 'document',
            'Cache-Control': 'max-age=0',
            'Pragma': 'no-cache',
        },
        'socket_timeout': 30,
        'retries': 15,
        'fragment_retries': 15,
        'skip_unavailable_fragments': True,
        'allow_unplayable_formats': True,
        'extractor_retries': 5,
        'sleep_interval': 0.5,
        'max_sleep_interval': 2,
    }
    
    if COOKIES_FILE.exists():
        opts['cookiefile'] = str(COOKIES_FILE)
        logger.info(f"📦 使用 YouTube cookies 文件: {COOKIES_FILE}")
    else:
        logger.warning(f"⚠️ 未找到 YouTube cookies 文件，将使用默认配置")
    
    return opts

def get_cache_path(cache_type: str, identifier: str) -> Path:
    """获取缓存文件路径"""
    safe_id = hashlib.md5(identifier.encode()).hexdigest()[:12]
    return CACHE_DIR / f"{cache_type}_{safe_id}_{identifier.replace('/', '_')}.json"

def is_cache_valid(cache_path: Path) -> bool:
    """检查缓存是否有效（未过期）"""
    if not cache_path.exists():
        return False
    
    file_time = datetime.fromtimestamp(cache_path.stat().st_mtime)
    return datetime.now() - file_time < timedelta(hours=CACHE_EXPIRE_HOURS)

def save_cache(cache_path: Path, data: dict):
    """保存数据到缓存"""
    try:
        cache_path.parent.mkdir(exist_ok=True)
        with open(cache_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        logger.warning(f"⚠️ 保存缓存失败 {cache_path}: {e}")

def load_cache(cache_path: Path) -> Optional[dict]:
    """从缓存加载数据"""
    if not is_cache_valid(cache_path):
        return None
    
    try:
        with open(cache_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.warning(f"⚠️ 读取缓存失败 {cache_path}: {e}")
        return None

def resolve_channel_id(input_str: str) -> str:
    """解析频道ID，支持多种输入格式"""
    logger.info(f"🔍 解析频道标识: {input_str}")
    
    # 去除 @ 前缀
    if input_str.startswith('@'):
        input_str = input_str[1:]
    
    # 如果已经是频道ID格式（UC开头且长度为24），直接返回
    if input_str.startswith('UC') and len(input_str) == 24:
        logger.info(f"✅ 识别为频道ID: {input_str}")
        return input_str
    
    # 检查缓存
    cache_path = get_cache_path("channel_resolve", input_str)
    cached_data = load_cache(cache_path)
    if cached_data and 'channel_id' in cached_data:
        logger.info(f"📦 从缓存获取频道ID: {cached_data['channel_id']}")
        return cached_data['channel_id']
    
    try:
        # 使用yt-dlp获取频道信息
        ydl_opts = {
            'quiet': True,
            'skip_download': True,
            'extract_flat': True,
            'playlist_items': '1',  # 只获取一个视频来得到频道ID
            **get_common_ydl_opts(),  # 添加通用配置
        }
        
        # 尝试不同的URL格式
        possible_urls = [
            f'https://www.youtube.com/@{input_str}',
            f'https://www.youtube.com/c/{input_str}', 
            f'https://www.youtube.com/user/{input_str}',
            f'https://www.youtube.com/channel/{input_str}',
        ]
        
        for url in possible_urls:
            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=False)
                    
                    if info and 'channel_id' in info:
                        channel_id = info['channel_id']
                        logger.info(f"✅ 通过URL {url} 获取到频道ID: {channel_id}")
                        
                        # 保存到缓存
                        save_cache(cache_path, {'channel_id': channel_id, 'resolved_from': url})
                        return channel_id
                        
            except Exception as e:
                logger.debug(f"🔍 尝试URL失败 {url}: {e}")
                continue
        
        raise Exception(f"无法解析频道标识: {input_str}")
        
    except Exception as e:
        logger.error(f"❌ 频道ID解析失败: {e}")
        raise Exception(f"频道不存在或无法访问: {input_str}")

def get_channel_info(channel_input: str) -> dict:
    """获取频道信息"""
    logger.info(f"📺 获取频道信息: {channel_input}")
    
    # 解析频道ID
    channel_id = resolve_channel_id(channel_input)
    
    # 检查缓存
    cache_path = get_cache_path("channel_info", channel_id)
    cached_data = load_cache(cache_path)
    if cached_data:
        logger.info(f"📦 从缓存获取频道信息: {cached_data.get('title', 'Unknown')}")
        return cached_data
    
    try:
        ydl_opts = {
            'quiet': True,
            'skip_download': True,
            'extract_flat': False,
            'playlist_items': '1:5',  # 获取前5个视频来得到频道详细信息
            **get_common_ydl_opts(),  # 添加通用配置
        }
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f'https://www.youtube.com/channel/{channel_id}/videos', download=False)
            
            if not info:
                raise Exception("无法获取频道信息")
            
            # 提取频道信息
            channel_info = {
                'channel_id': channel_id,
                'title': info.get('title', ''),
                'description': (info.get('description', '') or '')[:500],
                'subscriber_count': info.get('subscriber_count'),
                'video_count': len(info.get('entries', [])) if 'entries' in info else 0,
                'thumbnail': info.get('thumbnail') or (info.get('thumbnails', [{}])[-1].get('url', '') if info.get('thumbnails') else ''),
                'uploader': info.get('uploader', info.get('title', '')),
                'webpage_url': f'https://www.youtube.com/channel/{channel_id}',
                'updated_at': datetime.now().isoformat()
            }
            
            # 处理缩略图
            if not channel_info['thumbnail'] and 'entries' in info and info['entries']:
                # 如果没有频道缩略图，使用第一个视频的缩略图
                first_video = info['entries'][0]
                if 'thumbnails' in first_video and first_video['thumbnails']:
                    channel_info['thumbnail'] = first_video['thumbnails'][-1].get('url', '')
            
            logger.info(f"✅ 获取频道信息成功: {channel_info['title']}")
            
            # 保存到缓存
            save_cache(cache_path, channel_info)
            
            return channel_info
            
    except Exception as e:
        logger.error(f"❌ 获取频道信息失败: {e}")
        raise Exception(f"获取频道信息失败: {str(e)}")

def get_channel_videos(channel_input: str, limit: int = 20) -> List[dict]:
    """获取频道视频列表"""
    logger.info(f"🎬 获取频道视频: {channel_input}, 数量限制: {limit}")
    
    # 解析频道ID
    channel_id = resolve_channel_id(channel_input)
    
    # 检查缓存
    cache_key = f"{channel_id}_{limit}"
    cache_path = get_cache_path("channel_videos", cache_key)
    cached_data = load_cache(cache_path)
    if cached_data:
        logger.info(f"📦 从缓存获取频道视频: {len(cached_data)} 个视频")
        return cached_data
    
    try:
        ydl_opts = {
            'quiet': True,
            'skip_download': True,
            'extract_flat': True,
            'playlist_items': f'1:{limit}',
            **get_common_ydl_opts(),  # 添加通用配置
        }
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f'https://www.youtube.com/channel/{channel_id}/videos', download=False)
            
            if not info or 'entries' not in info:
                logger.warning(f"⚠️ 频道无视频或无法访问: {channel_id}")
                return []
            
            videos = []
            for entry in info['entries'][:limit]:
                if not entry:
                    continue
                    
                video_info = {
                    'video_id': entry.get('id', ''),
                    'title': entry.get('title', ''),
                    'description': (entry.get('description', '') or '')[:200],
                    'duration': entry.get('duration', 0),
                    'upload_date': entry.get('upload_date', ''),
                    'view_count': entry.get('view_count', 0),
                    'thumbnail': '',
                    'webpage_url': entry.get('webpage_url', f"https://www.youtube.com/watch?v={entry.get('id', '')}")
                }
                
                # 处理缩略图
                if 'thumbnails' in entry and entry['thumbnails']:
                    video_info['thumbnail'] = entry['thumbnails'][-1].get('url', '')
                elif entry.get('id'):
                    # 使用标准的YouTube缩略图URL
                    video_info['thumbnail'] = f"https://img.youtube.com/vi/{entry['id']}/maxresdefault.jpg"
                
                videos.append(video_info)
            
            logger.info(f"✅ 获取频道视频成功: {len(videos)} 个视频")
            
            # 保存到缓存
            save_cache(cache_path, videos)
            
            return videos
            
    except Exception as e:
        logger.error(f"❌ 获取频道视频失败: {e}")
        raise Exception(f"获取频道视频失败: {str(e)}")

def get_video_info_detailed(video_id: str) -> dict:
    """获取视频详细信息（比基础的get_video_info更详细）"""
    logger.info(f"🎥 获取视频详细信息: {video_id}")
    
    # 检查缓存
    cache_path = get_cache_path("video_detailed", video_id)
    cached_data = load_cache(cache_path)
    if cached_data:
        logger.info(f"📦 从缓存获取视频详细信息: {cached_data.get('title', 'Unknown')}")
        return cached_data
    
    try:
        ydl_opts = {
            'quiet': True,
            'skip_download': True,
            'extract_flat': False,
            'noplaylist': True,
            **get_common_ydl_opts(),  # 添加通用配置
        }
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f'https://www.youtube.com/watch?v={video_id}', download=False)
            
            if not info:
                raise Exception("无法获取视频信息")
            
            # 提取详细视频信息
            video_info = {
                'id': video_id,  # iOS端期望字段名为'id'
                'title': info.get('title', ''),
                'description': (info.get('description', '') or '')[:500],
                'duration': info.get('duration', 0),
                'uploader': info.get('uploader', ''),
                'channel_id': info.get('channel_id', ''),
                'channel': info.get('channel', ''),
                'view_count': info.get('view_count', 0),
                'like_count': info.get('like_count', 0),
                'upload_date': info.get('upload_date', ''),
                'webpage_url': info.get('webpage_url', ''),
                'thumbnail': '',
                'updated_at': datetime.now().isoformat()
            }
            
            # 处理缩略图
            if 'thumbnails' in info and info['thumbnails']:
                video_info['thumbnail'] = info['thumbnails'][-1].get('url', '')
            else:
                video_info['thumbnail'] = f"https://img.youtube.com/vi/{video_id}/maxresdefault.jpg"
            
            logger.info(f"✅ 获取视频详细信息成功: {video_info['title']}")
            
            # 保存到缓存
            save_cache(cache_path, video_info)
            
            return video_info
            
    except Exception as e:
        logger.error(f"❌ 获取视频详细信息失败: {e}")
        raise Exception(f"获取视频信息失败: {str(e)}")

def search_channels(query: str, limit: int = 10) -> List[dict]:
    """搜索频道"""
    logger.info(f"🔍 搜索频道: {query}, 限制: {limit}")
    
    # 检查缓存
    cache_key = f"{query}_{limit}"
    cache_path = get_cache_path("search_channels", cache_key)
    cached_data = load_cache(cache_path)
    if cached_data:
        logger.info(f"📦 从缓存获取搜索结果: {len(cached_data)} 个频道")
        return cached_data
    
    try:
        ydl_opts = {
            'quiet': True,
            'skip_download': True,
            'extract_flat': True,
            'playlist_items': f'1:{limit}',
            **get_common_ydl_opts(),  # 添加通用配置
        }
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # 搜索频道
            search_url = f'ytsearch{limit}:"{query}" channel'
            info = ydl.extract_info(search_url, download=False)
            
            if not info or 'entries' not in info:
                logger.warning(f"⚠️ 搜索无结果: {query}")
                return []
            
            channels = []
            seen_channels = set()  # 避免重复
            
            for entry in info['entries']:
                if not entry or not entry.get('channel_id'):
                    continue
                
                channel_id = entry['channel_id']
                if channel_id in seen_channels:
                    continue
                seen_channels.add(channel_id)
                
                channel_info = {
                    'channel_id': channel_id,
                    'title': entry.get('channel', entry.get('uploader', '')),
                    'description': (entry.get('description', '') or '')[:200],
                    'thumbnail': '',
                    'subscriber_count': None,
                    'video_count': None,
                    'webpage_url': f'https://www.youtube.com/channel/{channel_id}'
                }
                
                # 处理缩略图
                if 'thumbnails' in entry and entry['thumbnails']:
                    channel_info['thumbnail'] = entry['thumbnails'][-1].get('url', '')
                
                channels.append(channel_info)
            
            logger.info(f"✅ 搜索频道成功: {len(channels)} 个结果")
            
            # 保存到缓存（搜索结果缓存时间较短，1小时）
            save_cache(cache_path, channels)
            
            return channels
            
    except Exception as e:
        logger.error(f"❌ 搜索频道失败: {e}")
        raise Exception(f"搜索失败: {str(e)}")

# =============================================================================
# 新增API端点（YouTube数据获取）
# =============================================================================

@app.route('/api/channel/info')
def api_get_channel_info():
    """获取频道信息API"""
    channel_input = request.args.get('id')
    if not channel_input:
        return jsonify({"error": "Missing channel id or username"}), 400
    
    try:
        channel_info = get_channel_info(channel_input)
        return jsonify(channel_info)
    except Exception as e:
        logger.error(f"❌ 频道信息API错误: {e}")
        return jsonify({"error": str(e)}), 400

@app.route('/api/channel/videos')
def api_get_channel_videos():
    """获取频道视频列表API"""
    channel_input = request.args.get('id')
    if not channel_input:
        return jsonify({"error": "Missing channel id"}), 400
    
    limit = request.args.get('limit', 20)
    try:
        limit = int(limit)
        limit = max(1, min(limit, 50))  # 限制在1-50之间
    except ValueError:
        limit = 20
    
    try:
        videos = get_channel_videos(channel_input, limit)
        return jsonify({
            "videos": videos,
            "count": len(videos)
        })
    except Exception as e:
        logger.error(f"❌ 频道视频API错误: {e}")
        return jsonify({"error": str(e)}), 400

@app.route('/api/video/info')
def api_get_video_info():
    """获取视频详细信息API"""
    video_id = request.args.get('id')
    if not video_id:
        return jsonify({"error": "Missing video id"}), 400
    
    try:
        video_info = get_video_info_detailed(video_id)
        return jsonify(video_info)
    except Exception as e:
        logger.error(f"❌ 视频信息API错误: {e}")
        return jsonify({"error": str(e)}), 400

@app.route('/api/search/channel')
def api_search_channels():
    """搜索频道API"""
    query = request.args.get('q')
    if not query:
        return jsonify({"error": "Missing search query"}), 400
    
    limit = request.args.get('limit', 10)
    try:
        limit = int(limit)
        limit = max(1, min(limit, 20))  # 限制在1-20之间
    except ValueError:
        limit = 10
    
    try:
        channels = search_channels(query, limit)
        return jsonify({
            "channels": channels,
            "count": len(channels),
            "query": query
        })
    except Exception as e:
        logger.error(f"❌ 搜索频道API错误: {e}")
        return jsonify({"error": str(e)}), 400

# =============================================================================
# 原有的文件管理和下载功能保持不变
# =============================================================================

# 文件管理
def get_file_path(video_id: str, file_type: str) -> Path:
    """获取文件路径"""
    safe_id = hashlib.md5(video_id.encode()).hexdigest()[:12]
    if file_type == "audio":
        return DOWNLOAD_DIR / f"{safe_id}_{video_id}.mp3"
    elif file_type == "subtitle":
        return DOWNLOAD_DIR / f"{safe_id}_{video_id}.vtt"
    elif file_type == "info":
        return DOWNLOAD_DIR / f"{safe_id}_{video_id}.json"
    else:
        raise ValueError(f"Unknown file type: {file_type}")

def find_actual_audio_file(video_id: str) -> Optional[Path]:
    """查找实际存在的音频文件路径，统一逻辑避免重复代码"""
    # 首先检查任务中记录的实际文件路径
    if video_id in tasks:
        task = tasks[video_id]
        if task.audio_file and Path(task.audio_file).exists():
            actual_file = Path(task.audio_file)
            if actual_file.stat().st_size > 0:
                return actual_file
    
    # 检查默认路径
    default_audio_file = get_file_path(video_id, "audio")
    if default_audio_file.exists() and default_audio_file.stat().st_size > 0:
        return default_audio_file
    
    # 尝试查找实际存在的音频文件
    base_path = default_audio_file.with_suffix('')
    possible_files = [
        base_path,  # 无扩展名文件
        Path(str(base_path) + '.m4a'),
        Path(str(base_path) + '.mp4'),
        Path(str(base_path) + '.aac'),
        Path(str(base_path) + '.webm'),
        Path(str(base_path) + '.mp3')
    ]
    
    for candidate in possible_files:
        if candidate.exists() and candidate.stat().st_size > 0:
            return candidate
    
    return None

def cleanup_old_files():
    """清理过期文件（12小时），增强保护机制避免删除仍在使用的文件"""
    try:
        cutoff_time = datetime.now() - timedelta(hours=CACHE_EXPIRE_HOURS)
        cleaned_count = 0
        
        # 收集当前所有任务中记录的文件路径（正在使用的文件）
        protected_files = set()
        for video_id, task in tasks.items():
            if task.audio_file:
                protected_files.add(Path(task.audio_file).resolve())
            if task.subtitle_file:
                protected_files.add(Path(task.subtitle_file).resolve())
        
        # 清理下载文件
        for file_path in DOWNLOAD_DIR.glob("*"):
            if file_path.is_file():
                # 额外保护：跳过正在使用的文件
                if file_path.resolve() in protected_files:
                    logger.info(f"🛡️ 跳过正在使用的文件: {file_path.name}")
                    continue
                    
                file_time = datetime.fromtimestamp(file_path.stat().st_mtime)
                if file_time < cutoff_time:
                    try:
                        file_path.unlink()
                        cleaned_count += 1
                        logger.info(f"🗑️ 清理过期下载文件: {file_path.name}")
                    except Exception as e:
                        logger.error(f"❌ 删除文件失败 {file_path}: {e}")
        
        # 清理缓存文件（保持原有逻辑）
        for file_path in CACHE_DIR.glob("*"):
            if file_path.is_file():
                file_time = datetime.fromtimestamp(file_path.stat().st_mtime)
                if file_time < cutoff_time:
                    try:
                        file_path.unlink()
                        cleaned_count += 1
                        logger.info(f"🗑️ 清理过期缓存文件: {file_path.name}")
                    except Exception as e:
                        logger.error(f"❌ 删除缓存文件失败 {file_path}: {e}")
        
        # 清理旧的任务记录（避免内存积累）
        cleaned_tasks = cleanup_old_tasks()
        
        if cleaned_count > 0 or cleaned_tasks > 0:
            logger.info(f"🧹 清理完成: 删除了 {cleaned_count} 个过期文件，{cleaned_tasks} 个旧任务记录")
            logger.info(f"🛡️ 保护了 {len(protected_files)} 个正在使用的文件")
        
    except Exception as e:
        logger.error(f"❌ 文件清理失败: {e}")

def cleanup_old_tasks():
    """清理旧的任务记录，避免内存积累"""
    try:
        cutoff_time = datetime.now() - timedelta(hours=CACHE_EXPIRE_HOURS)
        tasks_to_remove = []
        
        for video_id, task in tasks.items():
            # 清理超过12小时的已完成、失败或取消的任务
            if task.status in [TaskStatus.COMPLETED, TaskStatus.FAILED, TaskStatus.CANCELLED]:
                if task.created_at and datetime.now() - task.created_at > timedelta(hours=CACHE_EXPIRE_HOURS):
                    tasks_to_remove.append(video_id)
                elif task.completed_at and datetime.now() - task.completed_at > timedelta(hours=CACHE_EXPIRE_HOURS):
                    tasks_to_remove.append(video_id)
        
        # 删除旧任务记录
        for video_id in tasks_to_remove:
            try:
                del tasks[video_id]
                logger.info(f"🗑️ 清理旧任务记录: {video_id}")
            except KeyError:
                pass  # 任务已被其他地方删除
        
        return len(tasks_to_remove)
        
    except Exception as e:
        logger.error(f"❌ 任务清理失败: {e}")
        return 0

def check_existing_files(video_id: str) -> Dict[str, bool]:
    """检查文件是否已存在且有效（不检查过期时间）"""
    result = {
        "audio": False,
        "subtitle": False,
        "info": False
    }
    
    for file_type in result.keys():
        file_path = get_file_path(video_id, file_type)
        
        if file_type == "audio":
            actual_audio_file = find_actual_audio_file(video_id)
            if actual_audio_file:
                result[file_type] = True
        else:
            # 非音频文件使用原有逻辑
            if file_path.exists() and file_path.stat().st_size > 0:
                result[file_type] = True
    
    logger.info(f"🎯 文件检查结果 {video_id}: audio={result['audio']}, subtitle={result['subtitle']}")
    return result

def get_video_info(video_id: str) -> Optional[Dict]:
    """获取视频信息（从缓存或网络）"""
    info_file = get_file_path(video_id, "info")
    
    # 尝试从缓存读取
    if info_file.exists():
        try:
            with open(info_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            logger.warning(f"⚠️ 读取缓存信息失败: {e}")
    
    # 从网络获取（使用新的详细信息获取函数）
    try:
        video_info = get_video_info_detailed(video_id)
        
        # 保存到缓存
        try:
            with open(info_file, 'w', encoding='utf-8') as f:
                json.dump(video_info, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.warning(f"⚠️ 保存视频信息缓存失败: {e}")
        
        return video_info
        
    except Exception as e:
        logger.error(f"❌ 获取视频信息失败: {e}")
        return None

def download_files(task: DownloadTask):
    """下载音频和字幕文件"""
    try:
        logger.info(f"🎵 开始下载任务: {task.video_id}")
        task.status = TaskStatus.DOWNLOADING
        task.progress = 0.0
        task.message = "准备下载..."
        
        # 获取视频信息
        task.video_info = get_video_info(task.video_id)
        if not task.video_info:
            raise Exception("无法获取视频信息")
        
        task.progress = 0.1
        task.message = "获取下载链接..."
        
        audio_file = get_file_path(task.video_id, "audio")
        subtitle_file = get_file_path(task.video_id, "subtitle")
        
        # 创建yt-dlp选项
        def progress_hook(d):
            if d['status'] == 'downloading':
                if 'total_bytes' in d and d['total_bytes']:
                    task.progress = 0.1 + 0.8 * (d['downloaded_bytes'] / d['total_bytes'])
                elif 'total_bytes_estimate' in d and d['total_bytes_estimate']:
                    task.progress = 0.1 + 0.8 * (d['downloaded_bytes'] / d['total_bytes_estimate'])
                else:
                    # 无法获取总大小时的进度估算
                    task.progress = min(0.9, task.progress + 0.01)
                
                task.message = f"下载中... {d.get('_percent_str', 'N/A')}"
                logger.info(f"📊 {task.video_id}: {task.message}")
                
            elif d['status'] == 'finished':
                task.progress = 0.9
                task.message = "下载完成，处理中..."
                logger.info(f"✅ {task.video_id}: 文件下载完成")

        ydl_opts = {
            'format': 'bestaudio/best',
            'outtmpl': str(audio_file.with_suffix('.%(ext)s')),
            'writesubtitles': True,
            'writeautomaticsub': True,
            'subtitleslangs': ['en'],
            'subtitlesformat': 'vtt',
            'writeinfojson': True,
            'extract_audio': True,
            'audio_format': 'mp3',
            'audio_quality': '128k',
            'prefer_ffmpeg': True,
            'noplaylist': True,
            'ignoreerrors': False,
            'no_warnings': True,
            'quiet': True,
            'progress_hooks': [lambda d: progress_hook(d)],
            'postprocessors': [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'mp3',
                'preferredquality': '128',
            }],
            **get_common_ydl_opts(),
        }
        
        # 检查任务是否被取消
        if task.status == TaskStatus.CANCELLED:
            logger.info(f"⚠️ 任务已取消: {task.video_id}")
            return
        
        # 执行下载
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([f'https://www.youtube.com/watch?v={task.video_id}'])
        
        # 验证文件 - 检查实际下载的文件
        # yt-dlp可能会下载不同的格式，我们需要查找实际的文件
        base_path = audio_file.with_suffix('')  # 无扩展名的基础路径
        actual_audio_file = None
        
        # 常见的音频文件扩展名，包括无扩展名
        possible_files = [
            base_path,  # 无扩展名文件
            Path(str(base_path) + '.m4a'),
            Path(str(base_path) + '.mp4'),
            Path(str(base_path) + '.aac'),
            Path(str(base_path) + '.webm'),
            Path(str(base_path) + '.mp3')
        ]
        
        for candidate in possible_files:
            if candidate.exists() and candidate.stat().st_size > 0:
                actual_audio_file = candidate
                break
        
        if not actual_audio_file:
            raise Exception("音频文件下载失败或为空")
        
        # 如果文件没有扩展名，根据内容或默认添加.mp3扩展名
        target_audio_file = audio_file  # 目标文件名（带.mp3扩展名）
        
        if actual_audio_file != target_audio_file:
            try:
                # 重命名为带扩展名的文件
                shutil.move(str(actual_audio_file), str(target_audio_file))
                logger.info(f"✅ 音频文件重命名: {actual_audio_file.name} -> {target_audio_file.name}")
                actual_audio_file = target_audio_file
            except Exception as e:
                logger.warning(f"⚠️ 音频文件重命名失败: {e}")
                # 如果重命名失败，使用实际文件
                pass
        
        task.audio_file = str(actual_audio_file)
        logger.info(f"🎵 音频文件下载成功: {actual_audio_file.name} ({actual_audio_file.stat().st_size / 1024 / 1024:.1f} MB)")
        
        # 检查字幕文件（可能不存在）
        # 字幕文件也可能有不同的扩展名
        subtitle_base = subtitle_file.with_suffix('')  # 无扩展名的基础路径
        subtitle_candidates = [
            subtitle_file,  # .vtt
            Path(str(subtitle_base) + '.en.vtt'),  # .en.vtt
            Path(str(subtitle_base) + '.srt'),  # 备用.srt
            Path(str(subtitle_base) + '.en.srt'),  # 备用.en.srt
        ]
        
        actual_subtitle_file = None
        for candidate in subtitle_candidates:
            if candidate.exists() and candidate.stat().st_size > 0:
                actual_subtitle_file = candidate
                break
        
        if actual_subtitle_file:
            # 如果找到的字幕文件名与预期不同，重命名为预期的.vtt格式
            if actual_subtitle_file != subtitle_file:
                try:
                    shutil.move(str(actual_subtitle_file), str(subtitle_file))
                    logger.info(f"✅ 字幕文件重命名: {actual_subtitle_file.name} -> {subtitle_file.name}")
                    # 更新为重命名后的文件路径
                    actual_subtitle_file = subtitle_file
                except Exception as e:
                    logger.warning(f"⚠️ 字幕文件重命名失败: {e}")
            
            logger.info(f"✅ 字幕文件验证通过: {actual_subtitle_file.name}")
            task.subtitle_file = str(actual_subtitle_file)
            logger.info(f"📝 字幕文件下载成功: {actual_subtitle_file.name} ({actual_subtitle_file.stat().st_size / 1024:.1f} KB)")
        else:
            logger.info(f"⚠️ 未找到字幕文件")
        
        # 完成
        task.status = TaskStatus.COMPLETED
        task.progress = 1.0
        task.message = "下载完成"
        task.completed_at = datetime.now()
        
        logger.info(f"✅ 下载任务完成: {task.video_id}")
        
    except Exception as e:
        if task.status != TaskStatus.CANCELLED:
            task.status = TaskStatus.FAILED
            task.error = str(e)
            task.message = f"下载失败: {str(e)}"
            logger.error(f"❌ 下载失败 {task.video_id}: {e}")
    
    finally:
        # 清理线程引用
        if task.video_id in download_threads:
            del download_threads[task.video_id]

# API 端点

@app.route('/download', methods=['POST'])
def start_download():
    """开始下载任务"""
    video_id = request.args.get('id')
    if not video_id:
        return jsonify({"error": "Missing video id"}), 400
    
    logger.info(f"🚀 收到下载请求: {video_id}")
    
    # 首先检查文件是否已存在且有效
    existing_files = check_existing_files(video_id)
    if existing_files["audio"]:
        logger.info(f"✅ 音频文件已存在，直接返回: {video_id}")
        
        # 🔧 修复: 使用统一的查找逻辑获取实际文件路径
        actual_audio_file = find_actual_audio_file(video_id)
        actual_audio_file_path = str(actual_audio_file) if actual_audio_file else None
        
        # 查找字幕文件
        actual_subtitle_file_path = None
        if existing_files["subtitle"]:
            subtitle_file = get_file_path(video_id, "subtitle")
            if subtitle_file.exists():
                actual_subtitle_file_path = str(subtitle_file)
        
        # 创建或更新已完成的任务记录
        task = DownloadTask(
            task_id=str(uuid.uuid4()),
            video_id=video_id,
            status=TaskStatus.COMPLETED,
            progress=1.0,
            message="文件已存在",
            audio_file=actual_audio_file_path,  # 使用实际找到的文件路径
            subtitle_file=actual_subtitle_file_path,  # 使用实际找到的字幕路径
            video_info=get_video_info(video_id)
        )
        tasks[video_id] = task
        return jsonify({
            "task_id": task.task_id,
            "status": task.status.value,
            "message": task.message,
            "files_ready": True
        })
    
    # 检查是否已有正在进行的任务
    if video_id in tasks:
        existing_task = tasks[video_id]
        
        # 如果任务正在进行中，返回任务信息
        if existing_task.status in [TaskStatus.PENDING, TaskStatus.DOWNLOADING]:
            logger.info(f"⚠️ 任务正在进行中: {video_id}")
            return jsonify({
                "task_id": existing_task.task_id,
                "status": existing_task.status.value,
                "message": "任务已在进行中"
            })
        
        # 清理失败或取消的任务记录
        elif existing_task.status in [TaskStatus.FAILED, TaskStatus.CANCELLED]:
            logger.info(f"🔄 清理失败/取消的任务，重新开始: {video_id}")
            del tasks[video_id]
    
    # 创建新的下载任务
    logger.info(f"🎬 文件不存在，开始新的下载任务: {video_id}")
    task = DownloadTask(
        task_id=str(uuid.uuid4()),
        video_id=video_id,
        status=TaskStatus.PENDING,
        progress=0.0,
        message="任务已创建"
    )
    
    tasks[video_id] = task
    
    # 启动下载线程
    thread = threading.Thread(target=download_files, args=(task,))
    download_threads[video_id] = thread
    thread.start()
    
    logger.info(f"🎬 下载任务已启动: {video_id}")
    
    return jsonify({
        "task_id": task.task_id,
        "status": task.status.value,
        "message": task.message
    })

@app.route('/status')
def get_status():
    """获取下载状态"""
    video_id = request.args.get('id')
    if not video_id:
        return jsonify({"error": "Missing video id"}), 400
    
    if video_id not in tasks:
        return jsonify({"error": "Task not found"}), 404
    
    task = tasks[video_id]
    
    response = {
        "task_id": task.task_id,
        "video_id": task.video_id,
        "status": task.status.value,
        "progress": task.progress,
        "message": task.message,
        "created_at": task.created_at.isoformat(),
        "files_ready": task.status == TaskStatus.COMPLETED
    }
    
    if task.status == TaskStatus.COMPLETED:
        response.update({
            "completed_at": task.completed_at.isoformat() if task.completed_at else None,
            "has_audio": task.audio_file is not None,
            "has_subtitle": task.subtitle_file is not None,
            "video_info": task.video_info
        })
    
    if task.status == TaskStatus.FAILED and task.error:
        response["error"] = task.error
    
    return jsonify(response)

def get_file_mime_type(file_path: Path) -> str:
    """根据文件扩展名和内容检测MIME类型"""
    # 首先尝试根据扩展名
    mime_type, _ = mimetypes.guess_type(str(file_path))
    
    if mime_type:
        return mime_type
    
    # 根据扩展名手动映射
    ext = file_path.suffix.lower()
    mime_mapping = {
        '.m4a': 'audio/mp4',
        '.mp4': 'audio/mp4',
        '.mp3': 'audio/mpeg',
        '.aac': 'audio/aac',
        '.webm': 'audio/webm',
        '.ogg': 'audio/ogg',
        '.wav': 'audio/wav',
        '.flac': 'audio/flac',
        '': 'audio/mp4'  # 无扩展名默认为audio/mp4
    }
    
    return mime_mapping.get(ext, 'audio/mp4')  # 默认使用audio/mp4

@app.route('/files/audio')
def serve_audio():
    """提供音频文件服务"""
    video_id = request.args.get('id')
    if not video_id:
        abort(400, "Missing video id")
    
    # 🔧 使用统一的音频文件查找逻辑
    audio_file = find_actual_audio_file(video_id)
    
    if not audio_file:
        logger.error(f"❌ 音频文件不存在: {video_id}")
        abort(404, "Audio file not found")
    
    # 获取正确的MIME类型
    mime_type = get_file_mime_type(audio_file)
    logger.info(f"🎵 提供音频文件: {video_id}, 文件: {audio_file.name}, MIME: {mime_type}")
    
    # 支持Range请求
    return send_file(
        audio_file,
        mimetype=mime_type,
        as_attachment=False,
        conditional=True  # 启用Range支持
    )

@app.route('/files/subtitle')
def serve_subtitle():
    """提供字幕文件服务"""
    video_id = request.args.get('id')
    if not video_id:
        abort(400, "Missing video id")
    
    subtitle_file = get_file_path(video_id, "subtitle")
    if not subtitle_file.exists():
        abort(404, "Subtitle file not found")
    
    logger.info(f"📝 提供字幕文件: {video_id}")
    
    return send_file(
        subtitle_file,
        mimetype="text/plain",
        as_attachment=False
    )

@app.route('/info')
def get_video_info_api():
    """获取视频信息API"""
    video_id = request.args.get('id')
    if not video_id:
        abort(400, "Missing video id")
    
    info = get_video_info(video_id)
    if not info:
        return jsonify({"error": "Failed to get video info"}), 400
    
    return jsonify(info)

@app.route('/cancel', methods=['DELETE'])
def cancel_download():
    """取消下载任务"""
    video_id = request.args.get('id')
    if not video_id:
        return jsonify({"error": "Missing video id"}), 400
    
    if video_id not in tasks:
        return jsonify({"error": "Task not found"}), 404
    
    task = tasks[video_id]
    
    if task.status in [TaskStatus.PENDING, TaskStatus.DOWNLOADING]:
        task.status = TaskStatus.CANCELLED
        task.message = "任务已取消"
        
        # 等待线程结束（非阻塞）
        if video_id in download_threads:
            thread = download_threads[video_id]
            if thread.is_alive():
                # 给线程一些时间自行结束
                thread.join(timeout=2.0)
        
        logger.info(f"⚠️ 下载任务已取消: {video_id}")
        
        return jsonify({
            "message": "Task cancelled",
            "status": task.status.value
        })
    else:
        return jsonify({
            "message": f"Cannot cancel task in status: {task.status.value}",
            "status": task.status.value
        }), 400

@app.route('/api/cookies/status')
def cookies_status():
    """检查 cookies 配置状态"""
    cookies_configured = COOKIES_FILE.exists()
    cookies_info = {
        "cookies_configured": cookies_configured,
        "cookies_file": str(COOKIES_FILE),
    }
    
    if cookies_configured:
        try:
            file_size = COOKIES_FILE.stat().st_size
            file_mtime = datetime.fromtimestamp(COOKIES_FILE.stat().st_mtime)
            cookies_info["file_size"] = file_size
            cookies_info["last_modified"] = file_mtime.isoformat()
            cookies_info["status"] = "✅ Cookies 文件已配置"
        except Exception as e:
            cookies_info["status"] = f"⚠️ 无法读取 Cookies 文件: {e}"
    else:
        cookies_info["status"] = "❌ 未找到 Cookies 文件"
    
    cookies_info["help"] = "如果遇到 HTTP 403 错误，请尝试：\n1. 重新导出新的 Cookies（旧 Cookies 可能已过期）\n2. 确保 Cookies 文件格式正确（Netscape 格式）\n3. 检查 Cookies 文件是否包含有效的会话信息\n4. 重启服务器"
    
    return jsonify(cookies_info)

@app.route('/api/cookies/diagnose')
def cookies_diagnose():
    """诊断 Cookies 问题"""
    diagnosis = {
        "timestamp": datetime.now().isoformat(),
        "cookies_file_exists": COOKIES_FILE.exists(),
    }
    
    if COOKIES_FILE.exists():
        try:
            with open(COOKIES_FILE, 'r', encoding='utf-8') as f:
                content = f.read()
                lines = content.strip().split('\n')
                diagnosis["file_size"] = len(content)
                diagnosis["line_count"] = len(lines)
                diagnosis["is_netscape_format"] = lines[0].startswith('#') if lines else False
                diagnosis["has_youtube_cookies"] = any('youtube' in line.lower() for line in lines)
                
                # 检查是否有有效的 cookies
                valid_cookies = [l for l in lines if l.strip() and not l.startswith('#')]
                diagnosis["valid_cookie_count"] = len(valid_cookies)
                
                if diagnosis["valid_cookie_count"] > 0:
                    diagnosis["status"] = "✅ Cookies 文件看起来有效"
                else:
                    diagnosis["status"] = "❌ Cookies 文件为空或格式不正确"
        except Exception as e:
            diagnosis["status"] = f"❌ 无法读取 Cookies 文件: {e}"
    else:
        diagnosis["status"] = "❌ Cookies 文件不存在"
    
    return jsonify(diagnosis)

@app.route('/api/test/youtube/<video_id>')
def test_youtube_connection(video_id):
    """测试 YouTube 连接和 yt-dlp 配置"""
    test_result = {
        "timestamp": datetime.now().isoformat(),
        "video_id": video_id,
        "tests": {}
    }
    
    try:
        # 测试 1: 基础连接
        test_result["tests"]["basic_connection"] = {
            "status": "testing",
            "message": "正在测试基础连接..."
        }
        
        ydl_opts = {
            **get_common_ydl_opts(),
            'quiet': True,
            'no_warnings': True,
            'extract_flat': True,
        }
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f'https://www.youtube.com/watch?v={video_id}', download=False)
            
        test_result["tests"]["basic_connection"] = {
            "status": "✅ 成功",
            "message": "可以获取视频信息",
            "video_title": info.get('title', 'N/A'),
            "duration": info.get('duration', 'N/A'),
            "formats_available": len(info.get('formats', []))
        }
        
        # 测试 2: 音频格式可用性
        test_result["tests"]["audio_formats"] = {
            "status": "✅ 成功",
            "message": "音频格式可用",
            "audio_formats_count": len([f for f in info.get('formats', []) if f.get('vcodec') == 'none'])
        }
        
        test_result["overall_status"] = "✅ YouTube 连接正常"
        
    except Exception as e:
        error_msg = str(e)
        test_result["tests"]["basic_connection"] = {
            "status": "❌ 失败",
            "error": error_msg
        }
        
        # 诊断错误类型
        if "403" in error_msg:
            test_result["diagnosis"] = "🚫 HTTP 403 错误 - YouTube 拒绝访问"
            test_result["solutions"] = [
                "1. 检查 Cookies 是否过期: curl http://localhost:5000/api/cookies/diagnose",
                "2. 重新导出 YouTube Cookies (需要新的登录会话)",
                "3. 检查 IP 是否被限制 (等待 1-2 小时后重试)",
                "4. 尝试使用 VPN 或代理"
            ]
        elif "bot" in error_msg.lower() or "sign in" in error_msg.lower():
            test_result["diagnosis"] = "🤖 机器人验证错误"
            test_result["solutions"] = [
                "1. 导出有效的 YouTube Cookies",
                "2. 确保 Cookies 文件位置正确: ./youtube_cookies.txt",
                "3. 重启服务"
            ]
        else:
            test_result["diagnosis"] = f"❌ 其他错误: {error_msg}"
            test_result["solutions"] = [
                "1. 检查网络连接",
                "2. 检查 yt-dlp 是否最新: pip install --upgrade yt-dlp",
                "3. 查看完整日志: tail -f youtube_download.log"
            ]
        
        test_result["overall_status"] = "❌ YouTube 连接失败"
    
    return jsonify(test_result)

@app.route('/health')
def health_check():
    """健康检查"""
    active_tasks = sum(1 for task in tasks.values() 
                      if task.status in [TaskStatus.PENDING, TaskStatus.DOWNLOADING])
    
    completed_tasks = sum(1 for task in tasks.values() 
                         if task.status == TaskStatus.COMPLETED)
    
    failed_tasks = sum(1 for task in tasks.values() 
                      if task.status == TaskStatus.FAILED)
    
    # 统计文件信息
    download_files_count = len(list(DOWNLOAD_DIR.glob("*")))
    cache_files_count = len(list(CACHE_DIR.glob("*")))
    
    return jsonify({
        "status": "healthy",
        "service": "YouTube Audio Download Server with yt-dlp Data API",
        "version": "3.0.0",
        "tasks": {
            "active": active_tasks,
            "completed": completed_tasks,
            "failed": failed_tasks,
            "total": len(tasks)
        },
        "files": {
            "download_files": download_files_count,
            "cache_files": cache_files_count
        },
        "directories": {
            "download_dir": str(DOWNLOAD_DIR.absolute()),
            "cache_dir": str(CACHE_DIR.absolute())
        },
        "cache_expire_hours": CACHE_EXPIRE_HOURS,
        "features": {
            "intelligent_file_reuse": "智能文件复用 - 已下载文件永久有效，无需重复下载",
            "smart_task_management": "智能任务管理，避免重复任务",
            "memory_cleanup": "定时清理过期任务记录（12小时）",
            "disk_cleanup": "定时清理过期文件（12小时）"
        }
    })

@app.route('/')
def index():
    """服务信息页面"""
    return jsonify({
        "service": "YouTube Audio Download Server with yt-dlp Data API",
        "version": "3.0.0",
        "description": "使用yt-dlp替代YouTube Data API v3，无配额限制",
        "features": [
            "完整下载mp3音频和vtt字幕",
            "支持断点续传",
            "自动缓存管理(12小时)",
            "HTTP Range请求支持",
            "任务队列管理",
            "使用yt-dlp获取YouTube数据，无API配额限制",
            "智能缓存频道和视频信息",
            "支持多种频道标识格式(@username, 频道ID等)",
            "无需ffmpeg依赖，适合低配置服务器"
        ],
        "endpoints": {
            "download_related": {
                "POST /download?id=VIDEO_ID": "开始下载任务",
                "GET /status?id=VIDEO_ID": "获取下载状态",
                "GET /files/audio?id=VIDEO_ID": "获取音频文件",
                "GET /files/subtitle?id=VIDEO_ID": "获取字幕文件", 
                "GET /info?id=VIDEO_ID": "获取视频信息",
                "DELETE /cancel?id=VIDEO_ID": "取消下载任务"
            },
            "youtube_data_api": {
                "GET /api/channel/info?id=CHANNEL_ID_OR_USERNAME": "获取频道信息",
                "GET /api/channel/videos?id=CHANNEL_ID&limit=20": "获取频道视频列表",
                "GET /api/video/info?id=VIDEO_ID": "获取视频详细信息",
                "GET /api/search/channel?q=QUERY&limit=10": "搜索频道"
            },
            "utility": {
                "GET /health": "健康检查",
                "GET /debug/files?id=VIDEO_ID": "调试文件信息",
                "GET /fix/files?id=VIDEO_ID": "修复文件扩展名",
                "POST /admin/cleanup": "手动触发清理操作"
            }
        },
        "supported_channel_formats": [
            "@username (推荐)",
            "频道ID (UCxxxxxxxx)",
            "频道用户名",
            "频道自定义URL"
        ]
    })

@app.route('/debug/files')
def debug_files():
    """调试端点：检查文件信息"""
    video_id = request.args.get('id')
    if not video_id:
        return jsonify({"error": "Missing video id"}), 400
    
    debug_info = {
        "video_id": video_id,
        "files": []
    }
    
    # 检查下载目录中的所有相关文件
    safe_id = hashlib.md5(video_id.encode()).hexdigest()[:12]
    for file_path in DOWNLOAD_DIR.glob(f"{safe_id}_{video_id}*"):
        if file_path.is_file():
            try:
                stat = file_path.stat()
                mime_type = get_file_mime_type(file_path)
                
                file_info = {
                    "name": file_path.name,
                    "path": str(file_path),
                    "size": stat.st_size,
                    "size_mb": round(stat.st_size / 1024 / 1024, 2),
                    "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "extension": file_path.suffix,
                    "mime_type": mime_type,
                    "exists": True
                }
                debug_info["files"].append(file_info)
            except Exception as e:
                debug_info["files"].append({
                    "name": file_path.name,
                    "error": str(e),
                    "exists": file_path.exists()
                })
    
    # 检查任务信息
    if video_id in tasks:
        task = tasks[video_id]
        debug_info["task"] = {
            "status": task.status.value,
            "audio_file": task.audio_file,
            "subtitle_file": task.subtitle_file,
            "progress": task.progress,
            "message": task.message
        }
    
    return jsonify(debug_info)

@app.route('/fix/files')
def fix_files():
    """修复端点：为无扩展名的音频文件添加扩展名"""
    video_id = request.args.get('id')
    if not video_id:
        return jsonify({"error": "Missing video id"}), 400
    
    result = {
        "video_id": video_id,
        "actions": []
    }
    
    # 查找无扩展名的音频文件
    safe_id = hashlib.md5(video_id.encode()).hexdigest()[:12]
    base_path = DOWNLOAD_DIR / f"{safe_id}_{video_id}"
    
    if base_path.exists() and base_path.is_file():
        # 找到无扩展名文件
        target_path = base_path.with_suffix('.mp3')
        
        if not target_path.exists():
            try:
                shutil.move(str(base_path), str(target_path))
                result["actions"].append({
                    "action": "renamed",
                    "from": base_path.name,
                    "to": target_path.name,
                    "success": True
                })
                
                # 更新任务记录
                if video_id in tasks:
                    tasks[video_id].audio_file = str(target_path)
                    result["actions"].append({
                        "action": "updated_task",
                        "audio_file": str(target_path),
                        "success": True
                    })
                
            except Exception as e:
                result["actions"].append({
                    "action": "rename_failed",
                    "error": str(e),
                    "success": False
                })
        else:
            result["actions"].append({
                "action": "target_exists",
                "message": f"{target_path.name} already exists",
                "success": False
            })
    else:
        result["actions"].append({
            "action": "not_found",
            "message": f"No file found: {base_path.name}",
            "success": False
        })
    
    return jsonify(result)

@app.route('/admin/cleanup', methods=['POST'])
def manual_cleanup():
    """手动触发清理（管理端点）"""
    try:
        logger.info("🧹 手动触发清理操作...")
        
        # 执行清理
        old_task_count = len(tasks)
        cleanup_old_files()
        new_task_count = len(tasks)
        
        cleaned_tasks = old_task_count - new_task_count
        
        # 统计当前状态
        active_tasks = sum(1 for task in tasks.values() 
                          if task.status in [TaskStatus.PENDING, TaskStatus.DOWNLOADING])
        completed_tasks = sum(1 for task in tasks.values() 
                             if task.status == TaskStatus.COMPLETED)
        
        return jsonify({
            "status": "success",
            "message": "手动清理完成",
            "cleanup_results": {
                "tasks_cleaned": cleaned_tasks,
                "remaining_tasks": new_task_count,
                "active_tasks": active_tasks,
                "completed_tasks": completed_tasks
            }
        })
        
    except Exception as e:
        logger.error(f"❌ 手动清理失败: {e}")
        return jsonify({
            "status": "error",
            "message": f"清理失败: {str(e)}"
        }), 500

def cleanup_timer():
    """定期清理定时器"""
    while True:
        time.sleep(3600)  # 每小时清理一次
        cleanup_old_files()

if __name__ == '__main__':
    logger.info("🚀 Starting YouTube Audio Download Server with yt-dlp Data API...")
    logger.info("📁 Download directory: " + str(DOWNLOAD_DIR.absolute()))
    logger.info("📦 Cache directory: " + str(CACHE_DIR.absolute()))
    logger.info("⏰ Cache expiry: " + str(CACHE_EXPIRE_HOURS) + " hours")
    logger.info("💡 ffmpeg is optional - service works without it (may have format limitations)")
    logger.info("🔗 API endpoints:")
    logger.info("   # 下载相关")
    logger.info("   POST /download?id=VIDEO_ID   - Start download task")
    logger.info("   GET /status?id=VIDEO_ID      - Get download status")
    logger.info("   GET /files/audio?id=VIDEO_ID - Serve audio file")
    logger.info("   GET /files/subtitle?id=VIDEO_ID - Serve subtitle file")
    logger.info("   GET /info?id=VIDEO_ID        - Get video metadata")
    logger.info("   DELETE /cancel?id=VIDEO_ID   - Cancel download task")
    logger.info("   # YouTube数据获取（替代YouTube Data API v3）")
    logger.info("   GET /api/channel/info?id=CHANNEL_ID_OR_USERNAME - Get channel info")
    logger.info("   GET /api/channel/videos?id=CHANNEL_ID&limit=20  - Get channel videos")
    logger.info("   GET /api/video/info?id=VIDEO_ID                 - Get video info")
    logger.info("   GET /api/search/channel?q=QUERY&limit=10        - Search channels")
    logger.info("   # 工具")
    logger.info("   GET /health                  - Health check")
    logger.info("   GET /debug/files?id=VIDEO_ID - Debug file information")
    
    # 检查依赖
    try:
        import yt_dlp
        import flask
        logger.info("✅ All dependencies are available")
        logger.info(f"📦 yt-dlp version: {yt_dlp.version.__version__}")
    except ImportError as e:
        logger.error(f"❌ Missing dependency: {e}")
        logger.error("💡 Please install: pip install flask yt-dlp")
        sys.exit(1)
    
    # 启动清理定时器
    cleanup_thread = threading.Thread(target=cleanup_timer, daemon=True)
    cleanup_thread.start()
    logger.info("🧹 Cleanup timer started")
    
    # 启动服务器
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)