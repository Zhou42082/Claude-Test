# 智能家居统一控制平台

一个移动 App 统一控制 **小米（米家）**、**华为（智慧生活）**、**涂鸦（智能生活）** 三个生态的设备。

```
Flutter App  ──REST / WebSocket──▶  统一网关 (FastAPI)  ──▶  Home Assistant  ──▶  小米 / 涂鸦 / Matter 设备
```

- `mobile/` — Flutter App：按房间、按平台浏览设备，开关 / 调光 / 色温 / 空调 / 窗帘 / 风扇控制，实时状态推送
- `backend/` — 统一网关：把各平台设备转换成统一模型，对 App 提供 REST 和 WebSocket 接口
- `docs/architecture.md` — 架构设计、**各平台接入可行性（华为需要重点看）**、接口说明、路线图

## 快速体验（演示数据，不需要真实设备）

启动网关：

```bash
cd backend && pip install -e ".[dev]"
```

```bash
GATEWAY_TOKEN=devtoken GATEWAY_ADAPTERS=mock uvicorn gateway.main:app --factory --host 0.0.0.0 --port 8000
```

运行 App（需要 Flutter 3.44 或更高版本）：

```bash
cd mobile && flutter run
```

首次打开填写网关地址（如 `http://<电脑局域网IP>:8000`，Android 模拟器用 `http://10.0.2.2:8000`）和令牌 `devtoken`。

## 接入真实设备

1. 复制 `.env.example` 为 `.env`，设置 `GATEWAY_TOKEN`。
2. `docker compose up -d homeassistant matter-server`，浏览器打开 `http://<服务器IP>:8123` 完成 HA 初始化。
3. 在 HA 中添加集成：
   - 小米：通过 HACS 或手动安装 [Xiaomi Home](https://github.com/XiaoMi/ha_xiaomi_home)，用小米账号登录；
   - 涂鸦：设置 → 设备与服务 → 添加 `Tuya`，用「智能生活」App 扫码；
   - 华为：通过 HACS 安装社区集成 [Huawei SmartHome](https://github.com/xiasi0/ha-huawei-smarthome)，用华为账号登录（非官方，不可商用，先核对设备是否在其支持列表中）；支持 Matter 的设备也可用 `Matter` 集成配对。详见 `docs/architecture.md` 第 2 节。
4. 在 HA 中给设备分配区域（即 App 中的房间），生成长期访问令牌填入 `.env` 的 `HA_TOKEN`。
5. `docker compose up -d gateway`。

## 测试

```bash
cd backend && pytest
```

```bash
cd mobile && flutter test
```
