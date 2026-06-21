# LinkVault Client 1.0

LinkVault Client 1.0 是 LinkVault 1.0 的 Flutter 客户端。当前只保留并维护 Android 与 Windows runner，iOS、macOS、Linux 和 Web 暂无上线计划，已从仓库中移除。

## 目录结构

- `lib/app`：应用入口、路由、主题和依赖组装。
- `lib/core`：API 配置、网络客户端、平台能力和传输恢复逻辑。
- `lib/features`：按业务拆分的页面与交互，包括登录注册、文件库、传输任务、回收站和个人中心。
- `lib/shared`：跨页面复用的组件、反馈提示和输入约束。
- `assets/images`：应用图标与登录背景图。
- `config/server.json`：默认服务端地址配置。
- `android`：Flutter Android runner 与原生配置。
- `windows`：Flutter Windows runner 与原生配置。
- `test`：Flutter 单元测试与组件测试。

## 服务端地址配置

客户端会优先读取外部配置，再回退到打包内置的 `config/server.json`，最后使用编译期默认值 `http://localhost:8080/api/v1`。

读取顺序：

1. 当前工作目录的 `config/server.json`
2. 当前工作目录的 `server.json`
3. 可执行文件同级目录的 `config/server.json`
4. 可执行文件同级目录的 `server.json`
5. 打包进应用的 `config/server.json`

配置示例：

```json
{
  "scheme": "http",
  "host": "localhost",
  "port": 8080,
  "apiPath": "/api/v1"
}
```

也可以直接使用完整地址：

```json
{
  "baseUrl": "http://localhost:8080/api/v1"
}
```

## 本地运行

先启动 `linkvault-server`，再在本目录安装依赖：

```powershell
flutter pub get
```

运行 Windows 客户端：

```powershell
flutter run -d windows
```

运行 Android 客户端：

```powershell
flutter emulators --launch <emulator-id>
flutter run -d android
```

## 测试与打包

```powershell
flutter test
flutter build apk --release
flutter build windows --release
```

Windows 可执行文件生成在：

```text
build/windows/x64/runner/Release/LinkVault.exe
```

## 重新生成 runner

如果 Android 或 Windows runner 目录缺失，可在本目录重新生成。该命令会重建平台工程文件，执行前请先确认没有未保存的平台配置改动。

```powershell
flutter create --platforms=android,windows --project-name linkvault_client --org com.linkvault .
```
