const { app, BrowserWindow, ipcMain, net, protocol, session } = require('electron');
const path = require('path');
const fs = require('fs');
const isDev = process.env.ELECTRON_IS_DEV !== '0';
const iconv = require('iconv-lite');
const axios = require('axios');

let mainWindow;

// 阿里云盘 API 配置
const CLIENT_ID = '717cbc119af349399f525555efb434e1';
const CLIENT_SECRET = '0743bd65f7384d5c878f564de7d7276a';
const API_BASE = 'https://openapi.alipan.com';

// 令牌存储路径
const TOKEN_STORAGE_PATH = path.join(app.getPath('userData'), 'token_storage.json');

// 令牌有效期 (毫秒) - 设为7天
const TOKEN_VALIDITY_DURATION = 7 * 24 * 60 * 60 * 1000;

// 令牌存储管理
const tokenManager = {
  // 保存令牌到本地文件
  saveToken(token) {
    try {
      const tokenData = {
        access_token: token,
        expiry: Date.now() + TOKEN_VALIDITY_DURATION
      };

      fs.writeFileSync(TOKEN_STORAGE_PATH, JSON.stringify(tokenData), 'utf8');
      console.log('Token saved to file storage');
      return true;
    } catch (error) {
      console.error('Error saving token:', error);
      return false;
    }
  },

  // 读取本地令牌
  getToken() {
    try {
      if (!fs.existsSync(TOKEN_STORAGE_PATH)) {
        console.log('No token storage file found');
        return null;
      }

      const fileContent = fs.readFileSync(TOKEN_STORAGE_PATH, 'utf8');
      const tokenData = JSON.parse(fileContent);

      // 检查令牌是否过期
      if (tokenData.expiry && tokenData.expiry > Date.now()) {
        const remainingHours = Math.floor((tokenData.expiry - Date.now()) / (60 * 60 * 1000));
        console.log(`Found valid token with ${remainingHours} hours remaining`);
        return {
          access_token: tokenData.access_token,
          expiry: tokenData.expiry,
          remaining_hours: remainingHours
        };
      } else {
        console.log('Token has expired');
        this.clearToken();
        return null;
      }
    } catch (error) {
      console.error('Error reading token:', error);
      return null;
    }
  },

  // 清除令牌
  clearToken() {
    try {
      if (fs.existsSync(TOKEN_STORAGE_PATH)) {
        fs.unlinkSync(TOKEN_STORAGE_PATH);
        console.log('Token storage file deleted');
      }
      return true;
    } catch (error) {
      console.error('Error clearing token:', error);
      return false;
    }
  }
};

// 播放历史记录管理
const PLAY_HISTORY_PATH = path.join(app.getPath('userData'), 'play_history.json');
const MAX_HISTORY_ITEMS = 50; // 最多保存的播放记录数

const playHistoryManager = {
  // 获取播放历史
  getPlayHistory() {
    try {
      if (!fs.existsSync(PLAY_HISTORY_PATH)) {
        return [];
      }
      
      const fileContent = fs.readFileSync(PLAY_HISTORY_PATH, 'utf8');
      const history = JSON.parse(fileContent);
      return Array.isArray(history) ? history : [];
    } catch (error) {
      console.error('Error reading play history:', error);
      return [];
    }
  },
  
  // 添加或更新播放记录
  savePlayHistory(videoInfo) {
    try {
      if (!videoInfo || !videoInfo.file_id) {
        return false;
      }
      
      let history = this.getPlayHistory();
      
      // 查找是否已存在该视频的播放记录
      const existingIndex = history.findIndex(item => item.file_id === videoInfo.file_id);
      
      if (existingIndex >= 0) {
        // 更新已有记录
        history[existingIndex] = {
          ...history[existingIndex],
          ...videoInfo,
          last_played_at: Date.now()
        };
      } else {
        // 添加新记录
        history.unshift({
          ...videoInfo,
          last_played_at: Date.now()
        });
        
        // 限制记录数量
        if (history.length > MAX_HISTORY_ITEMS) {
          history = history.slice(0, MAX_HISTORY_ITEMS);
        }
      }
      
      // 保存到文件
      fs.writeFileSync(PLAY_HISTORY_PATH, JSON.stringify(history), 'utf8');
      console.log('Play history saved successfully');
      return true;
    } catch (error) {
      console.error('Error saving play history:', error);
      return false;
    }
  },
  
  // 更新播放进度
  updatePlayProgress(fileId, playCursor) {
    try {
      if (!fileId || !playCursor) {
        return false;
      }
      
      const history = this.getPlayHistory();
      const existingIndex = history.findIndex(item => item.file_id === fileId);
      
      if (existingIndex >= 0) {
        history[existingIndex].play_cursor = playCursor;
        history[existingIndex].last_played_at = Date.now();
        
        // 保存到文件
        fs.writeFileSync(PLAY_HISTORY_PATH, JSON.stringify(history), 'utf8');
        console.log(`Play progress updated for ${fileId}: ${playCursor}`);
        return true;
      }
      
      return false;
    } catch (error) {
      console.error('Error updating play progress:', error);
      return false;
    }
  },
  
  // 清除播放历史
  clearPlayHistory() {
    try {
      if (fs.existsSync(PLAY_HISTORY_PATH)) {
        fs.unlinkSync(PLAY_HISTORY_PATH);
        console.log('Play history cleared');
      }
      return true;
    } catch (error) {
      console.error('Error clearing play history:', error);
      return false;
    }
  }
};

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 1000,
    minHeight: 700,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
      // 关键设置：禁用同源策略和允许不安全内容（仅用于桌面应用）
      webSecurity: false,
      allowRunningInsecureContent: true,
      // 添加以下设置以提高视频播放稳定性
      backgroundThrottling: false,
      enableWebSQL: false,  // 禁用已弃用的WebSQL
      enableBlinkFeatures: 'MediaSource',
      // 启用硬件加速但配置得更保守
      disableBlinkFeatures: 'Accelerated2dCanvas', // 避免2D Canvas硬件加速可能导致的问题
      // 以下选项可能会帮助解决渲染器崩溃问题
      enableRemoteModule: false, // 禁用已弃用的remote模块
      safeDialogs: true,
      spellcheck: false // 关闭拼写检查以减少资源使用
    },
    titleBarStyle: 'hiddenInset',
    frame: false, // 移除默认窗口边框
    backgroundColor: '#f6fbfa',
    show: false, // 初始不显示，等待ready-to-show事件
    // 更稳定的 GPU 渲染设置
    autoHideMenuBar: true,
    // 添加图标设置，确保在开发环境也使用自定义图标
    icon: path.join(__dirname, '../src/assets/logo.png')
  });

  // 窗口准备好后最大化显示
  mainWindow.once('ready-to-show', () => {
    mainWindow.maximize();
    mainWindow.show();
  });

  // Load the appropriate URL based on environment
  if (isDev) {
    // In development mode
    console.log('Running in development mode');
    mainWindow.loadURL('http://localhost:5173');
    mainWindow.webContents.openDevTools();
  } else {
    // In production mode
    console.log('Running in production mode');
    const indexPath = path.join(__dirname, '../dist/index.html');
    console.log('Loading from path:', indexPath);
    if (fs.existsSync(indexPath)) {
      mainWindow.loadFile(indexPath);
    } else {
      console.error('Production build not found:', indexPath);
    }
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// API 代理函数
function makeRequest(method, url, data = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const request = net.request({
      method,
      url,
      headers: {
        'Content-Type': 'application/json',
        ...headers
      }
    });

    request.on('response', (response) => {
      let responseData = '';
      
      response.on('data', (chunk) => {
        responseData += chunk.toString();
      });
      
      response.on('end', () => {
        try {
          const parsedData = JSON.parse(responseData);
          resolve({
            status: response.statusCode,
            data: parsedData
          });
        } catch (error) {
          reject({
            status: response.statusCode,
            error: 'Failed to parse response data',
            raw: responseData
          });
        }
      });
    });

    request.on('error', (error) => {
      reject({
        error: error.message
      });
    });

    if (data) {
      const postData = typeof data === 'string' 
        ? data 
        : JSON.stringify(data);
      request.write(postData);
    }

    request.end();
  });
}

// 设置 IPC 处理程序，用于 API 请求
ipcMain.handle('api-request', async (event, { method, url, data, headers }) => {
  try {
    const response = await makeRequest(method, url, data, headers);
    return response;
  } catch (error) {
    console.error('API request error:', error);
    return { error: true, message: error.message || 'Unknown error' };
  }
});

// 渲染器优化处理
ipcMain.handle('optimize-renderer', async (event) => {
  try {
    if (!mainWindow || !mainWindow.webContents) {
      return { success: false, message: 'No window available' };
    }
    
    // 强制执行垃圾回收
    mainWindow.webContents.forcefullyCrashRenderer = false;
    
    // 释放不必要的内存
    if (global.gc) {
      global.gc();
    }
    
    return { success: true };
  } catch (error) {
    console.error('Renderer optimization error:', error);
    return { error: true, message: error.message || 'Unknown error' };
  }
});

// 阿里云盘 API 接口
ipcMain.handle('get-qrcode', async () => {
  try {
    const response = await makeRequest('POST', `${API_BASE}/oauth/authorize/qrcode`, {
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      scopes: [
        'user:base',
        'file:all:read',
        'file:all:write',
        'album:shared:read',
        'file:share:write'
      ],
      width: 300,
      height: 300
    });
    return response.data;
  } catch (error) {
    console.error('QR Code generation error:', error);
    return { error: true, message: 'Failed to generate QR code' };
  }
});

ipcMain.handle('check-qrcode-status', async (event, { sid }) => {
  try {
    const response = await makeRequest('GET', `${API_BASE}/oauth/qrcode/${sid}/status`);
    return response.data;
  } catch (error) {
    console.error('QR Code status check error:', error);
    return { error: true, message: 'Failed to check QR code status' };
  }
});

ipcMain.handle('get-access-token', async (event, { authCode }) => {
  try {
    const response = await makeRequest('POST', `${API_BASE}/oauth/access_token`, {
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      grant_type: 'authorization_code',
      code: authCode
    });
    
    // 保存令牌到文件存储
    if (response.data && response.data.access_token) {
      tokenManager.saveToken(response.data.access_token);
    }
    
    return response.data;
  } catch (error) {
    console.error('Access token error:', error);
    return { error: true, message: 'Failed to get access token' };
  }
});

// 新增：获取存储的令牌
ipcMain.handle('get-stored-token', async () => {
  try {
    const tokenData = tokenManager.getToken();
    if (tokenData) {
      return {
        access_token: tokenData.access_token,
        remaining_hours: tokenData.remaining_hours
      };
    } else {
      return { error: true, message: 'No valid token found' };
    }
  } catch (error) {
    console.error('Get stored token error:', error);
    return { error: true, message: 'Failed to get stored token' };
  }
});

// 新增：清除令牌
ipcMain.handle('clear-token', async () => {
  try {
    const success = tokenManager.clearToken();
    return { success };
  } catch (error) {
    console.error('Clear token error:', error);
    return { error: true, message: 'Failed to clear token' };
  }
});

ipcMain.handle('get-drive-info', async (event, { accessToken }) => {
  try {
    const response = await makeRequest('POST', `${API_BASE}/adrive/v1.0/user/getDriveInfo`, 
      {}, 
      { 'Authorization': `Bearer ${accessToken}` }
    );
    return response.data;
  } catch (error) {
    console.error('Drive info error:', error);
    return { error: true, message: 'Failed to get drive info' };
  }
});

ipcMain.handle('load-file-list', async (event, { accessToken, driveId, folderId }) => {
  try {
    const response = await makeRequest('POST', `${API_BASE}/adrive/v1.0/openFile/list`, 
      {
        drive_id: driveId,
        parent_file_id: folderId,
        order_by: 'name',
        order_direction: 'ASC'
      }, 
      { 'Authorization': `Bearer ${accessToken}` }
    );
    return response.data;
  } catch (error) {
    console.error('File list error:', error);
    return { error: true, message: 'Failed to load file list' };
  }
});

ipcMain.handle('search-files', async (event, { accessToken, driveId, query }) => {
  try {
    const response = await makeRequest('POST', `${API_BASE}/adrive/v1.0/openFile/search`, 
      {
        limit: 50,
        query: `name match \"${query}\"`,
        drive_id: driveId
      }, 
      { 'Authorization': `Bearer ${accessToken}` }
    );
    return response.data;
  } catch (error) {
    console.error('Search error:', error);
    return { error: true, message: 'Failed to search files' };
  }
});

ipcMain.handle('get-video-url', async (event, { accessToken, driveId, fileId }) => {
  try {
    const response = await makeRequest('POST', `${API_BASE}/adrive/v1.0/openFile/getVideoPreviewPlayInfo`, 
      {
        drive_id: driveId,
        file_id: fileId,
        category: 'live_transcoding',
        with_play_cursor: true
      }, 
      { 'Authorization': `Bearer ${accessToken}` }
    );
    return response.data;
  } catch (error) {
    console.error('Video URL error:', error);
    return { error: true, message: 'Failed to get video URL' };
  }
});

// 添加获取最近播放列表的函数
ipcMain.handle('get-recent-play-list', async (event, { accessToken }) => {
  try {
    const response = await makeRequest('POST', `${API_BASE}/adrive/v1.1/openFile/video/recentList`, 
      {
        video_thumbnail_width: 300 // 设置缩略图宽度
      }, 
      { 'Authorization': `Bearer ${accessToken}` }
    );
    return response.data;
  } catch (error) {
    console.error('Recent play list error:', error);
    return { error: true, message: 'Failed to get recent play list' };
  }
});

// 添加获取字幕文件的函数
ipcMain.handle('get-subtitle-content', async (event, { accessToken, driveId, fileId }) => {
  try {
    console.log(`获取字幕文件下载URL: 文件ID=${fileId}`);
    // 首先获取下载URL
    const response = await makeRequest('POST', `${API_BASE}/adrive/v1.0/openFile/getDownloadUrl`, 
      {
        drive_id: driveId,
        file_id: fileId
      }, 
      { 'Authorization': `Bearer ${accessToken}` }
    );
    
    if (response.data && response.data.url) {
      // 保存下载URL
      const downloadUrl = response.data.url;
      console.log(`获取到字幕下载URL: ${downloadUrl.substring(0, 50)}...`);
      
      // 下载字幕文件内容 - 使用二进制方式下载，以便后续处理编码
      const request = net.request({
        method: 'GET',
        url: downloadUrl
      });
      
      return new Promise((resolve, reject) => {
        const chunks = []; // 用于收集二进制数据
        
        request.on('response', (response) => {
          console.log(`字幕文件响应状态码: ${response.statusCode}`);
          
          response.on('data', (chunk) => {
            chunks.push(chunk); // 收集原始二进制数据
          });
          
          response.on('end', () => {
            try {
              // 将所有块合并成一个完整的Buffer
              const buffer = Buffer.concat(chunks);
              
              // 检测可能的编码（实现简单的编码检测）
              let encoding = 'utf-8'; // 默认编码
              let decodedContent = '';
              
              // 检查BOM标记，确定编码
              if (buffer.length >= 3 && buffer[0] === 0xEF && buffer[1] === 0xBB && buffer[2] === 0xBF) {
                // UTF-8 with BOM
                encoding = 'utf-8';
                decodedContent = buffer.toString('utf-8', 3); // 跳过BOM标记
              } else if (buffer.length >= 2 && buffer[0] === 0xFF && buffer[1] === 0xFE) {
                // UTF-16LE
                encoding = 'utf-16le';
                decodedContent = buffer.toString('utf-16le', 2);
              } else if (buffer.length >= 2 && buffer[0] === 0xFE && buffer[1] === 0xFF) {
                // UTF-16BE
                encoding = 'utf-16be';
                decodedContent = buffer.toString('utf-16be', 2);
              } else {
                // 尝试使用UTF-8解码
                try {
                  decodedContent = buffer.toString('utf-8');
                  // 检查UTF-8解码是否成功（如果包含中文应该解码正确）
                  if (decodedContent.includes('')) {
                    // UTF-8解码可能有问题，尝试其他编码
                    console.log('UTF-8解码可能有问题，尝试其他编码');
                    
                    // 尝试常见的中文编码: GB18030（包含GB2312和GBK）
                    try {
                      decodedContent = iconv.decode(buffer, 'gb18030');
                      encoding = 'gb18030';
                      console.log('使用GB18030编码解码成功');
                    } catch (e) {
                      console.error('GB18030解码失败:', e);
                      
                      // 尝试BIG5编码（繁体中文）
                      try {
                        decodedContent = iconv.decode(buffer, 'big5');
                        encoding = 'big5';
                        console.log('使用BIG5编码解码成功');
                      } catch (e2) {
                        console.error('BIG5解码失败:', e2);
                        // 如果所有尝试都失败，回退到UTF-8
                        decodedContent = buffer.toString('utf-8');
                        encoding = 'utf-8';
                      }
                    }
                  }
                } catch (e) {
                  console.error('UTF-8解码失败:', e);
                  // 尝试使用GB18030
                  decodedContent = iconv.decode(buffer, 'gb18030');
                  encoding = 'gb18030';
                }
              }
              
              console.log(`字幕文件编码检测为 ${encoding}`);
              console.log(`字幕文件内容预览: ${decodedContent.substring(0, 100).replace(/\n/g, ' ')}...`);
              
              resolve({
                content: decodedContent,
                encoding: encoding,
                url: downloadUrl
              });
            } catch (error) {
              console.error('字幕内容处理错误:', error);
              reject({ error: true, message: '字幕文件编码转换失败: ' + error.message });
            }
          });
          
          response.on('error', (error) => {
            console.error('Subtitle content download error:', error);
            reject({ error: true, message: 'Failed to download subtitle file content' });
          });
        });
        
        request.on('error', (error) => {
          console.error('Subtitle request error:', error);
          reject({ error: true, message: 'Failed to request subtitle file' });
        });
        
        request.end();
      });
    } else {
      throw new Error('Failed to get subtitle download URL');
    }
  } catch (error) {
    console.error('Subtitle download error:', error);
    return { error: true, message: 'Failed to download subtitle file' };
  }
});

// 添加视频流代理功能
ipcMain.handle('proxy-video-stream', async (event, url) => {
  // 直接返回原始URL，使用内置网络模块绕过CORS
  return { proxyUrl: url };
});

// 获取播放历史记录
ipcMain.handle('get-play-history', async () => {
  try {
    const history = playHistoryManager.getPlayHistory();
    return { success: true, items: history };
  } catch (error) {
    console.error('Get play history error:', error);
    return { error: true, message: 'Failed to get play history' };
  }
});

// 保存播放记录
ipcMain.handle('save-play-history', async (event, videoInfo) => {
  try {
    const success = playHistoryManager.savePlayHistory(videoInfo);
    return { success };
  } catch (error) {
    console.error('Save play history error:', error);
    return { error: true, message: 'Failed to save play history' };
  }
});

// 更新播放进度
ipcMain.handle('update-play-progress', async (event, { fileId, playCursor }) => {
  try {
    const success = playHistoryManager.updatePlayProgress(fileId, playCursor);
    return { success };
  } catch (error) {
    console.error('Update play progress error:', error);
    return { error: true, message: 'Failed to update play progress' };
  }
});

// 清除播放历史
ipcMain.handle('clear-play-history', async () => {
  try {
    const success = playHistoryManager.clearPlayHistory();
    return { success };
  } catch (error) {
    console.error('Clear play history error:', error);
    return { error: true, message: 'Failed to clear play history' };
  }
});

// 添加窗口控制事件监听
ipcMain.on('window-control', (event, command) => {
  if (!mainWindow) return;
  
  switch (command) {
    case 'minimize':
      mainWindow.minimize();
      break;
    case 'maximize':
      if (mainWindow.isMaximized()) {
        mainWindow.unmaximize();
      } else {
        mainWindow.maximize();
      }
      break;
    case 'close':
      mainWindow.close();
      break;
  }
});

app.whenReady().then(() => {
  console.log('应用程序准备就绪');
  console.log('当前工作目录:', process.cwd());
  console.log('应用程序目录:', app.getAppPath());
  console.log('平台:', process.platform);
  
  // 设置应用名称，这可能会影响macOS如何处理图标
  app.setName('Kumarajiva');
  
  // 确保硬件加速开启
  app.commandLine.appendSwitch('ignore-gpu-blacklist', 'true');
  app.commandLine.appendSwitch('disable-gpu-vsync');
  app.commandLine.appendSwitch('enable-zero-copy');
  app.commandLine.appendSwitch('enable-gpu-rasterization');
  app.commandLine.appendSwitch('enable-native-gpu-memory-buffers');
  
  // 为macOS设置Dock图标
  if (process.platform === 'darwin') {
    // 尝试多种图标格式
    let iconPath = path.join(__dirname, '../src/assets/logo.png');
    
    // 如果.icns文件不存在，回退到PNG
    if (!fs.existsSync(iconPath)) {
      iconPath = path.join(__dirname, '../src/assets/logo.png');
    }
    
    console.log('Setting dock icon with path:', iconPath);
    console.log('图标文件是否存在:', fs.existsSync(iconPath));
    
    try {
      app.dock.setIcon(iconPath);
      console.log('成功设置dock图标');
    } catch (error) {
      console.error('设置dock图标失败:', error);
    }
  }
  
  // 拦截所有网络请求来解决CORS问题
  session.defaultSession.webRequest.onBeforeSendHeaders((details, callback) => {
    // 确保所有请求都有Referer和Origin头
    details.requestHeaders['Referer'] = 'https://www.aliyundrive.com/';
    details.requestHeaders['Origin'] = 'https://www.aliyundrive.com';
    callback({ requestHeaders: details.requestHeaders });
  });

  // 拦截响应头，修改CORS相关的头信息
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
    const { responseHeaders } = details;
    
    // 添加允许的CORS头
    if (!responseHeaders['Access-Control-Allow-Origin']) {
      responseHeaders['Access-Control-Allow-Origin'] = ['*'];
    }
    
    callback({ responseHeaders });
  });

  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
}); 