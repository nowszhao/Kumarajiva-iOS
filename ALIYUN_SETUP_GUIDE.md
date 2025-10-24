# 阿里云盘OAuth配置指南

## 📋 配置清单

### ✅ 已完成的配置
- [x] iOS App中的URL Scheme配置
- [x] PKCE代码实现
- [x] OAuth回调处理
- [x] 安全验证机制

### ⚠️ 需要在阿里云盘开放平台完成的配置
- [ ] 注册/登录阿里云盘开放平台
- [ ] 创建应用
- [ ] 配置回调地址
- [ ] 获取Client ID

---

## 🚀 快速开始

### 步骤1: 访问阿里云盘开放平台

访问：https://www.alipan.com/drive/open

如果没有账号，使用阿里云盘App扫码登录。

### 步骤2: 创建应用

1. 点击"创建应用"或"应用管理"
2. 填写应用信息：
   ```
   应用名称: Kumarajiva-iOS
   应用类型: 移动应用 / 公开客户端
   应用描述: 英语学习助手，支持阿里云盘字幕播放
   应用图标: (上传App图标)
   ```

### 步骤3: 配置OAuth设置

在应用详情页面，找到"OAuth设置"或"授权配置"：

#### 3.1 授权模式
选择：**授权码模式 + PKCE**

#### 3.2 回调地址配置
添加以下回调地址：

```
kumarajiva-ios://aliyun-oauth-callback
```

**重要提示：**
- ⚠️ 必须完全匹配，包括`://`和路径
- ⚠️ 不要添加`http://`或`https://`前缀
- ✅ 可以添加多个回调地址用于不同环境

**示例配置：**
```
开发环境: kumarajiva-ios://aliyun-oauth-callback
生产环境: kumarajiva-ios://aliyun-oauth-callback
```

#### 3.3 权限范围
勾选以下权限：

- ✅ `user:base` - 获取用户基本信息
- ✅ `file:all:read` - 读取用户云盘文件
- ✅ `file:all:write` - 写入用户云盘文件（可选）

#### 3.4 其他设置
- **Client Secret**: 留空（PKCE模式不需要）
- **Token有效期**: 默认30天
- **刷新Token**: 不支持（公开客户端限制）

### 步骤4: 获取Client ID

配置完成后，在应用详情页面可以看到：

```
Client ID: 717cbc119af349399f525555efb434e1
```

**注意：**
- 当前代码中使用的是测试Client ID
- 生产环境需要替换为你自己的Client ID

### 步骤5: 更新代码中的Client ID

打开 `AliyunDriveService.swift`，找到：

```swift
let clientId = "717cbc119af349399f525555efb434e1"
```

替换为你的Client ID：

```swift
let clientId = "你的Client ID"
```

### 步骤6: 测试授权流程

1. 运行App
2. 进入"订阅"页面
3. 点击"添加阿里云盘"
4. 点击"授权登录阿里云盘"
5. 在浏览器/阿里云盘App中完成授权
6. 自动返回App，云盘添加成功

---

## 🔍 常见问题排查

### 问题1: 点击授权后无法跳转

**可能原因：**
- URL Scheme配置错误
- 回调地址未在开放平台注册

**解决方法：**
1. 检查`Info.plist`中的URL Scheme配置
2. 确认开放平台的回调地址完全匹配

### 问题2: 授权后返回App但提示错误

**可能原因：**
- Client ID不匹配
- 回调地址不匹配
- Code Verifier验证失败

**解决方法：**
1. 检查Client ID是否正确
2. 查看Xcode控制台的错误日志
3. 确认回调地址与开放平台配置一致

### 问题3: 提示"URISyntaxException"

**原因：**
回调地址格式错误，包含非法字符。

**解决方法：**
确保回调地址格式正确：
```
✅ 正确: kumarajiva-ios://aliyun-oauth-callback
❌ 错误: http://localhost:8000/callback
❌ 错误: kumarajiva-ios:/aliyun-oauth-callback (少了一个/)
```

### 问题4: Token获取失败

**可能原因：**
- Code Verifier与Code Challenge不匹配
- 授权码已过期或已使用
- 网络问题

**解决方法：**
1. 检查PKCE实现是否正确
2. 确保授权码只使用一次
3. 检查网络连接

---

## 📱 测试清单

### 功能测试
- [ ] 点击"授权登录"能正常跳转
- [ ] 在Safari中完成授权能返回App
- [ ] 在阿里云盘App中完成授权能返回App（如已安装）
- [ ] State验证正常工作
- [ ] Code Verifier验证正常工作
- [ ] Token能成功获取
- [ ] 云盘能成功添加到列表
- [ ] 能正常浏览云盘文件

### 边界测试
- [ ] 取消授权时的处理
- [ ] 授权失败时的错误提示
- [ ] 网络异常时的处理
- [ ] State不匹配时的安全拦截
- [ ] Code Verifier丢失时的处理

### 安全测试
- [ ] State参数防CSRF
- [ ] Code Verifier不会泄露
- [ ] 授权码只能使用一次
- [ ] Token安全存储在Keychain

---

## 🔐 安全最佳实践

### 1. URL Scheme安全
- 使用唯一的URL Scheme（避免与其他App冲突）
- 验证回调URL的来源
- 检查State参数防止CSRF

### 2. Token管理
- Token存储在Keychain而非UserDefaults
- 不要在日志中打印完整Token
- Token过期后及时清理

### 3. Code Verifier管理
- 每次授权生成新的Code Verifier
- 使用后立即清除
- 不要在网络请求中传输Code Verifier（除了换Token时）

### 4. 用户隐私
- 明确告知用户授权的权限范围
- 提供撤销授权的方式
- 遵守隐私政策和用户协议

---

## 📚 相关文档

- [阿里云盘开放平台](https://www.alipan.com/drive/open)
- [OAuth 2.0 + PKCE文档](https://www.yuque.com/aliyundrive/zpfszx/eam8ls1lmawwwksv)
- [PKCE规范 RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)

---

## 💡 提示

### 开发环境
当前代码使用的是测试Client ID，可以直接用于开发测试。

### 生产环境
上架App Store前，需要：
1. 申请正式的Client ID
2. 通过阿里云盘的应用审核
3. 更新代码中的Client ID
4. 提交新版本到App Store

### 技术支持
如遇到问题，可以：
1. 查看阿里云盘开放平台文档
2. 联系阿里云盘技术支持
3. 在开发者社区提问

---

**最后更新**: 2025-10-23
**文档版本**: 1.0
