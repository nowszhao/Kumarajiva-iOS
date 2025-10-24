# 阿里云盘OAuth授权优化

## 更新日期
2025-10-23

## 问题描述
原有的阿里云盘添加流程使用二维码扫码方式，在手机上使用时存在以下问题：
- 手机无法扫描自己屏幕上的二维码
- 用户体验不佳，需要另一台设备辅助
- 需要后端服务器处理回调

## 解决方案
使用**OAuth 2.0 + PKCE（Proof Key for Code Exchange）**授权流程，这是阿里云盘官方推荐的**公开客户端**（移动端App）授权方式：
- ✅ **无需后端服务器**：PKCE模式不需要保管`client_secret`
- ✅ **自定义URL Scheme**：支持`kumarajiva-ios://`作为回调地址
- ✅ **更高安全性**：通过`code_verifier`和`code_challenge`防止授权码拦截攻击
- ✅ **原生体验**：可调起阿里云盘App或在Safari中完成授权

## 技术实现

### 1. OAuth 2.0 + PKCE 授权流程

#### PKCE 参数生成
```swift
// 1. 生成 Code Verifier（43-128位随机字符串）
let codeVerifier = service.generateCodeVerifier()

// 2. 生成 Code Challenge（SHA256哈希）
let codeChallenge = service.generateCodeChallenge(from: codeVerifier)
```

#### 授权URL构建
```swift
let redirectUri = "kumarajiva-ios://aliyun-oauth-callback"
let state = UUID().uuidString

// 保存 state 和 code_verifier 用于后续验证
UserDefaults.standard.set(state, forKey: "aliyun_oauth_state")
UserDefaults.standard.set(codeVerifier, forKey: "aliyun_code_verifier")

var components = URLComponents(string: "https://openapi.alipan.com/oauth/authorize")!
components.queryItems = [
    URLQueryItem(name: "client_id", value: clientId),
    URLQueryItem(name: "redirect_uri", value: redirectUri),
    URLQueryItem(name: "scope", value: "user:base,file:all:read,file:all:write"),
    URLQueryItem(name: "response_type", value: "code"),
    URLQueryItem(name: "state", value: state),
    URLQueryItem(name: "code_challenge", value: codeChallenge),
    URLQueryItem(name: "code_challenge_method", value: "S256")
]
```

#### 授权流程步骤
1. **用户点击"授权登录"按钮**
2. **App生成PKCE参数**
   - 生成随机的`code_verifier`
   - 计算SHA256哈希得到`code_challenge`
   - 保存`code_verifier`用于后续验证
3. **App构建授权URL并打开**
   - 优先尝试调起阿里云盘App（如果已安装）
   - 否则在Safari浏览器中打开授权页面
4. **用户在阿里云盘/浏览器中确认授权**
5. **授权成功后跳转回App**
   - 回调URL: `kumarajiva-ios://aliyun-oauth-callback?code=xxx&state=xxx`
6. **App验证state和code_verifier**
7. **使用授权码+code_verifier获取Token**
   - 阿里云盘服务器验证`code_verifier`与之前的`code_challenge`匹配
8. **获取用户信息并添加云盘**

### 2. 修改的文件

#### AddAliyunDriveView.swift
**主要变更：**
- ❌ 移除二维码显示相关代码
- ❌ 移除二维码轮询逻辑
- ✅ 添加OAuth授权URL构建
- ✅ 添加OAuth回调处理
- ✅ 添加state验证机制
- ✅ 优化UI，使用渐变按钮

**新增方法：**
```swift
private func startOAuthLogin()
private func handleOAuthCallback(url: URL)
```

#### AliyunDriveService.swift
**主要变更：**
- ✅ 将`clientId`从`private`改为`internal`（PKCE模式不需要`client_secret`）
- ✅ 添加PKCE辅助方法：
  - `generateCodeVerifier()` - 生成随机验证码
  - `generateCodeChallenge(from:)` - 生成SHA256哈希挑战码
- ✅ 修改`getAccessToken`方法支持PKCE：
  - 新增`codeVerifier`参数
  - 使用`code_verifier`替代`client_secret`
  - 添加`redirect_uri`参数

#### Info.plist
**新增配置：**
```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>aliyundrive</string>
    <string>smartdrive</string>
</array>
```

**说明：**
- `aliyundrive`: 阿里云盘App的URL Scheme
- `smartdrive`: 阿里云盘智能助手的URL Scheme
- 允许App检测和打开阿里云盘相关应用

#### Kumarajiva_iOSApp.swift
**主要变更：**
- ✅ 优化`onOpenURL`处理器，区分不同类型的OAuth回调
- ✅ 添加阿里云盘OAuth回调的日志记录

### 3. URL Scheme配置

#### 已注册的URL Scheme
```
kumarajiva-ios://
```

#### OAuth回调URL
- **GitHub OAuth**: `kumarajiva-ios://oauth-callback`
- **阿里云盘OAuth**: `kumarajiva-ios://aliyun-oauth-callback`

### 4. 安全机制

#### PKCE 安全保障
PKCE（Proof Key for Code Exchange）专为公开客户端设计，解决了以下安全问题：

**传统OAuth的问题：**
- 移动端App无法安全保管`client_secret`
- 授权码可能被恶意App拦截

**PKCE的解决方案：**
```
1. App生成随机的 code_verifier
2. 计算 code_challenge = SHA256(code_verifier)
3. 授权时发送 code_challenge
4. 换Token时发送 code_verifier
5. 服务器验证 SHA256(code_verifier) == code_challenge
```

**优势：**
- ✅ 即使授权码被拦截，没有`code_verifier`也无法换取Token
- ✅ 不需要保管`client_secret`
- ✅ 符合OAuth 2.0最佳实践

#### State参数验证
```swift
// 生成并保存state
let state = UUID().uuidString
UserDefaults.standard.set(state, forKey: "aliyun_oauth_state")

// 验证回调中的state
guard let state = components?.queryItems?.first(where: { $0.name == "state" })?.value,
      let savedState = UserDefaults.standard.string(forKey: "aliyun_oauth_state"),
      state == savedState else {
    // State验证失败
    return
}

// 清除已使用的state
UserDefaults.standard.removeObject(forKey: "aliyun_oauth_state")
```

**作用：**
- 防止CSRF攻击
- 确保回调来自本次授权请求

## UI优化

### 新UI设计
- 🎨 简洁的授权页面
- 🔵 渐变蓝色按钮，带阴影效果
- ➡️ 箭头图标，表示跳转操作
- 📱 清晰的说明文字

### 用户体验改进
1. **一键授权**：点击按钮即可跳转
2. **自动返回**：授权完成后自动返回App
3. **错误提示**：清晰的错误信息和重试机制
4. **加载状态**：显示"正在跳转..."状态

## 测试要点

### 功能测试
- [ ] 点击"授权登录"按钮能正常跳转
- [ ] 在浏览器中完成授权后能返回App
- [ ] State验证正常工作
- [ ] 授权码能成功换取Token
- [ ] 云盘能成功添加到列表

### 边界测试
- [ ] 取消授权时的处理
- [ ] 授权失败时的错误提示
- [ ] 网络异常时的处理
- [ ] State不匹配时的安全拦截

### 兼容性测试
- [ ] iOS 15+系统兼容性
- [ ] 已安装阿里云盘App的情况
- [ ] 未安装阿里云盘App的情况

## 注意事项

### 1. 阿里云盘开放平台配置 ⚠️ 重要

#### 配置步骤
1. 访问[阿里云盘开放平台](https://www.alipan.com/drive/open)
2. 创建应用或编辑现有应用
3. 配置以下信息：

**基本信息：**
- **应用名称**: Kumarajiva-iOS
- **应用类型**: 选择"移动应用"或"公开客户端"

**OAuth配置：**
- **回调地址**: `kumarajiva-ios://aliyun-oauth-callback`
  - ⚠️ 必须完全匹配，包括scheme、host和path
  - 支持添加多个回调地址（开发/生产环境）
- **授权模式**: 选择"授权码模式 + PKCE"
- **权限范围**: 
  - `user:base` - 用户基本信息
  - `file:all:read` - 读取文件
  - `file:all:write` - 写入文件

**重要提示：**
- ✅ 使用PKCE模式**不需要配置**`client_secret`
- ✅ 回调地址支持自定义URL Scheme
- ⚠️ 回调地址必须在平台上预先注册

### 2. URL Scheme冲突
确保`kumarajiva-ios`这个URL Scheme没有被其他App使用：
- 建议使用反向域名格式（如`com.yourcompany.appname`）
- 在App Store Connect中注册URL Scheme

### 3. Token有效期
- **AccessToken有效期**: 30天
- **RefreshToken**: PKCE公开客户端模式**不支持**Token刷新
- **到期处理**: Token过期后需要用户重新授权

### 4. 生产环境
当前使用的Client ID是测试环境的，生产环境需要：
- ✅ 申请正式的Client ID（无需Client Secret）
- ✅ 配置正确的回调地址
- ✅ 通过阿里云盘的应用审核
- ✅ 在App Store上架前完成审核

## 后续优化建议

### 1. 深度链接优化
- 尝试直接调起阿里云盘App进行授权
- 检测阿里云盘App是否已安装

### 2. Token管理
- 实现Token自动刷新机制
- 添加Token过期提醒

### 3. 多账号支持
- 支持添加多个阿里云盘账号
- 账号切换功能

### 4. 错误处理
- 更详细的错误分类
- 针对性的错误提示和解决方案

## 参考文档
- [阿里云盘开放平台](https://www.alipan.com/drive/open)
- [阿里云盘OAuth 2.0 + PKCE文档](https://www.yuque.com/aliyundrive/zpfszx/eam8ls1lmawwwksv)
- [OAuth 2.0 PKCE规范](https://oauth.net/2/pkce/)
- [RFC 7636 - PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [iOS URL Scheme配置](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)

## FAQ

### Q1: 为什么要使用PKCE而不是传统OAuth？
**A:** 移动端App是"公开客户端"，无法安全保管`client_secret`。PKCE通过动态生成的`code_verifier`替代固定的`client_secret`，即使授权码被拦截也无法换取Token。

### Q2: 回调地址必须是HTTPS吗？
**A:** 不需要。阿里云盘支持自定义URL Scheme（如`kumarajiva-ios://`）作为回调地址，这是移动端App的标准做法。

### Q3: 如何在阿里云盘开放平台配置回调地址？
**A:** 
1. 登录开放平台
2. 进入应用管理
3. 在OAuth设置中添加回调地址：`kumarajiva-ios://aliyun-oauth-callback`
4. 保存配置

### Q4: Token过期后怎么办？
**A:** PKCE公开客户端模式不支持Token刷新，过期后需要用户重新授权。建议在Token即将过期时提示用户。

### Q5: 可以同时支持多个回调地址吗？
**A:** 可以。在开放平台可以配置多个回调地址，用于开发、测试、生产等不同环境。

### Q6: 授权时会跳转到哪里？
**A:** 
- 如果用户已安装阿里云盘App，会调起App进行授权
- 否则会在Safari浏览器中打开授权页面
- 授权完成后自动返回你的App
