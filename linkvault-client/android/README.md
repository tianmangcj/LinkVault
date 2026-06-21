# Android 平台

此目录包含 Flutter Android runner。正常开发时业务代码放在 `lib/`，Android 目录只保留平台配置、Gradle 配置和原生入口。

如需重新生成 Android runner，可在 `linkvault-client` 目录执行：

```powershell
flutter create --platforms=android --project-name linkvault_client --org com.linkvault .
```
