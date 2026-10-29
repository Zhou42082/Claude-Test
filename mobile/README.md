# 智能家居 App（Flutter）

通过统一网关控制小米 / 华为 / 涂鸦设备。架构与接口见仓库根目录的 `docs/architecture.md`。

```
lib/
  models/device.dart            设备模型（与网关保持一致）
  services/gateway_client.dart  REST / WebSocket 客户端
  state/device_store.dart       设备状态、断线自动重连、命令下发
  state/settings_store.dart     网关地址与令牌
  screens/                      首页、设置页
  widgets/                      设备卡片、控制面板
```

```bash
flutter run
```

```bash
flutter test
```
