#!/usr/bin/env python3
"""
测试 YouTube 下载修复 - 使用 iOS/Mobile Web 客户端
"""

import yt_dlp

def test_ios_client():
    """测试 iOS 客户端是否能绕过机器人检测"""
    video_id = "8BfL3wzzyoc"
    
    print(f"🔍 测试视频: {video_id}")
    print(f"🌐 使用 iOS/Mobile Web 客户端")
    
    ydl_opts = {
        'quiet': False,
        'skip_download': True,
        'extract_flat': False,
        'noplaylist': True,
        'extractor_args': {
            'youtube': {
                'player_client': ['ios', 'mweb'],
                'player_skip': ['webpage'],
            }
        },
    }
    
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            print(f"\n📥 开始获取视频信息...")
            info = ydl.extract_info(f'https://www.youtube.com/watch?v={video_id}', download=False)
            
            print(f"\n✅ 成功！视频信息:")
            print(f"   标题: {info.get('title', 'N/A')}")
            print(f"   时长: {info.get('duration', 0)} 秒")
            print(f"   频道: {info.get('uploader', 'N/A')}")
            print(f"   观看数: {info.get('view_count', 0):,}")
            
            # 检查可用格式
            if 'formats' in info:
                audio_formats = [f for f in info['formats'] if f.get('acodec') != 'none']
                print(f"   可用音频格式: {len(audio_formats)} 个")
            
            return True
            
    except Exception as e:
        print(f"\n❌ 失败: {e}")
        return False

if __name__ == '__main__':
    print("=" * 60)
    print("YouTube 下载修复测试")
    print("=" * 60)
    
    success = test_ios_client()
    
    print("\n" + "=" * 60)
    if success:
        print("✅ 测试通过！iOS 客户端可以正常工作")
        print("\n💡 建议:")
        print("   1. 重启 youtube_audio_proxy_server.py")
        print("   2. 使用 iOS 应用重新测试下载")
    else:
        print("❌ 测试失败！")
        print("\n💡 可能的解决方案:")
        print("   1. 更新 yt-dlp: pip3 install -U yt-dlp")
        print("   2. 检查网络连接")
        print("   3. 等待一段时间后重试（可能是临时限制）")
    print("=" * 60)
