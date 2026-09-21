# Context Lens · 语境镜

Context Lens 是一个以“真实阅读语境”为核心的英语学习工具。它不是另一个需要手动录入的背单词软件：在 Mac 的网页、PDF、文档等界面选中英文，即可查看语境翻译并只收藏真正想学的词；随后通过间隔复习在 Mac 和 Android 上巩固。

> 当前版本：**0.2.0 Beta**。Mac 负责选词、AI 语境分析与学习；Android 负责同步复习和免费查词。

## 核心体验

1. 在其他 Mac 应用中拖动或双击选择英文，不写入剪贴板。
2. 鼠标附近出现“翻译”按钮，DeepSeek 结合当前句子解释含义。
3. AI 提取音标、语境义、常见释义和复习提示；用户自行勾选要收藏的词。
4. 单词进入独立复习计划，可选择“英文答中文”或“中文答英文”。
5. 登录 Supabase 账户后，在 Mac 和 Android 之间同步收藏和进度。

## 已实现

### macOS 14+

- 系统级英文选区检测（辅助功能 API，不模拟复制）
- DeepSeek 语境翻译、好词提取和学习提示
- 选择性收藏，不强制保存全部 AI 推荐
- 学习概览、可搜索单词字典和独立复习训练
- 每个单词单独安排复习；评分后自动进入下一词
- Supabase 邮箱账户与云端同步
- 选词诊断工具和明确的权限状态

### Android 8+

- Supabase 账户登录与词库读取
- 同步复习
- 免费在线英英词典查询和本地缓存
- 移动端不调用 DeepSeek，不需要 AI API 密钥

## 产品边界

- DeepSeek API 密钥由用户自行提供，只保存在 Mac 本机。
- 选中文本只在用户点击“翻译”后发送给 DeepSeek。
- Android 免费词典使用 [Free Dictionary API](https://dictionaryapi.dev/)；其结果为英英释义。
- Beta 安装包使用临时签名。公开分发前必须完成 Apple Developer ID 签名、公证和 Android release keystore 签名。

完整说明见 [隐私说明](PRIVACY.md)、[开发配置](DEVELOPMENT_SETUP.md) 和 [发布检查清单](RELEASE_CHECKLIST.md)。

## 项目结构

```text
macos/ContextLens/        macOS SwiftUI 菜单栏应用
android/                  Android Jetpack Compose 应用
app/                      Web 产品演示与后续账户门户
supabase/migrations/      数据库与 RLS 迁移
shared/                   多端共享配置
releases/                 本地生成的发布产物（不提交 Git）
```

## 本地开发

### macOS

```bash
./macos/ContextLens/build.sh
```

生成：`macos/ContextLens/build/Context Lens.app`

### Android

用 Android Studio 打开 `android/`，等待 Gradle 同步后运行 `app`；或执行：

```bash
cd android
./gradlew assembleDebug
```

### Supabase

依次执行 `supabase/migrations/001_context_lens.sql` 和 `002_word_meanings.sql`。数据库已启用 Row Level Security，每个登录用户只能访问自己的学习数据。

### Web 演示

```bash
npm install
npm test
```

## 路线图

- `0.2`：打磨 Mac 选词、双向复习、Android 同步复习
- `0.3`：稳定签名、离线词典、同步拉取与冲突处理、学习统计
- `1.0`：正式安装包、隐私政策页面、崩溃反馈和商店发布素材

## 贡献与反馈

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 私下报告，不要公开提交包含 API 密钥、账户或学习内容的 issue。

## 许可证

目前尚未授予开源许可证。公开仓库可用于查看和测试；在仓库所有者选择许可证前，不默认授予复制、修改或再分发权利。
