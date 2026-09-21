# Release checklist

## 必须完成后才能称为正式版

- [ ] 选择并添加正式软件许可证
- [ ] 配置项目联系邮箱、隐私政策 URL 和账户删除渠道
- [ ] 使用 Apple Developer ID 签名并完成 notarization
- [ ] 使用 Android release keystore 签名 APK/AAB，并安全保存密钥
- [ ] 在干净的 Mac 用户账户验证首次授权、选词、翻译、收藏和复习
- [ ] 在 Chrome、Safari、PDF、Word、微信输入场景验证不干扰输入
- [ ] 在 Android 真机验证登录、同步、离线缓存和无网提示
- [ ] 验证 Supabase RLS：用户 A 无法读取或修改用户 B 数据
- [ ] 增加云端数据导出、账户与数据删除功能
- [ ] 明确 DeepSeek、Supabase、Free Dictionary API 的条款与数据区域
- [ ] 移除日志、测试账户和任何私钥

## GitHub Beta 发布

- [ ] 更新 `CHANGELOG.md` 和版本号
- [ ] CI 构建通过
- [ ] 创建 tag，例如 `v0.2.0-beta`
- [ ] 上传 Mac ZIP 和 Android APK 到 GitHub Release，而不是提交进 Git
- [ ] 在 Release Notes 中列出已知限制：临时签名、权限可能需重新授权、词典为英英释义
