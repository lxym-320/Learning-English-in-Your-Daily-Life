# Contributing

感谢参与 Context Lens。提交改动前请：

1. 不要提交 DeepSeek 私钥、Supabase service role key、用户数据或签名证书。
2. 保持核心流程简单：选词 → 理解 → 选择收藏 → 复习。
3. macOS 改动运行 `./macos/ContextLens/build.sh`。
4. Android 改动运行 `cd android && ./gradlew assembleDebug`。
5. 数据库改动必须新增幂等 migration，并保持 Row Level Security。
6. UI 文案优先使用普通学习者能理解的中文。

Bug 报告请注明系统版本、发生应用、复现步骤和“诊断当前选词”的结果，但不要粘贴 API 密钥。
