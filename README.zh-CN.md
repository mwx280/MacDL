# MacDL

一个常驻菜单栏的原生 macOS 下载管理器。

多线程下载、断点续传、限速、剪切板下载、系统通知——全部沙盒化，不依赖任何第三方引擎。

## 功能

- **多线程下载** — 把文件拆成分块，最多 8 个连接同时下载
- **暂停 / 续传** — 先下载到 `.macdl` 暂存文件，用 HTTP `Range` 头续传；重启后也能接着下
- **限速** — 字节级令牌桶，可按任务或全局设置
- **从剪切板下载** — 复制链接，点菜单栏「从剪切板下载」即可
- **优先下载** — 右键把某个任务设为优先，其余任务自动暂停、完成后自动恢复
- **通知** — 开始 / 完成 / 失败，优先任务重试耗尽后另有专门提醒
- **沙盒** — 自定义下载目录用安全作用域书签持久化，重启后仍可访问
- **菜单栏应用** — 开机自启、关窗后隐藏 Dock 图标、后台启动
- **本地化** — 简体中文、English

## 系统要求

- macOS 26 或更高
- Xcode 26 或更高（从源码构建）

## 构建

```sh
open MacDL.xcodeproj   # 然后 ⌘R
# 或
xcodebuild -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

## 测试

```sh
# 引擎包测试
cd MacDLCore && swift test

# App 测试（串行，避免并行测试宿主下 Observation registrar 的偶发崩溃）
xcodebuild test -project MacDL.xcodeproj -scheme MacDL \
  -destination 'platform=macOS' -parallel-testing-enabled NO
```

## 架构

```
MacDLCore/   Swift Package —— 下载引擎
             （基于 URLSession 的分块引擎、令牌桶限速、续传逻辑）
MacDL/       App —— SwiftUI 菜单栏界面、持久化、通知、沙盒访问
```

引擎是独立的 Swift Package，不依赖 AppKit，可单独回归测试（`swift test`），
也方便在其他项目里复用。

## 下载原理

1. 引擎先发一个小 `Range` 探测请求，得知文件总大小和服务器是否支持 Range（`206`）。
2. 把文件拆成多个分块并发下载。
3. 服务器不支持 Range 时退化为单连接下载。
4. 暂停时保留已下载数据；续传发送有界的 `Range` 头，避免重复下载。
5. 完成后把 `.macdl` 暂存文件重命名为真实文件名。

## 许可证

[MIT](LICENSE)
