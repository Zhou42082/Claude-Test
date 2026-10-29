# 在云端运行演示（本地不需要 Docker）

两种方式都只运行**演示模式**（假设备 + 演示工具），不接触你家里的真实设备。

| | Render | GitHub Codespaces |
| --- | --- | --- |
| 账号 | 用 GitHub 账号登录 render.com | 只需要 GitHub 账号 |
| 网址 | 固定的 `https://xxx.onrender.com`，手机随时打开 | 每次启动 Codespace 时生成 |
| 一直在线 | 15 分钟没人访问会休眠，再打开约 1 分钟唤醒 | 30 分钟没操作自动停止，需手动重新启动 |
| 费用 | 免费套餐 | 个人账号每月有免费额度 |
| 适合 | 手机上反复测试、发给别人试用 | 临时看一下 |

## 方式一：Render（推荐）

1. 打开 [render.com](https://render.com)，用 GitHub 账号注册登录。
2. 控制台右上角 **New → Blueprint**，连接 GitHub 仓库 `Zhou42082/Claude-Test`。
   仓库是私有的话，在 GitHub 授权页里允许 Render 访问这个仓库。
3. **Branch** 选 `claude/happy-tesla-4wh7up`（以后合并到 main 就选 main）。Render 会读取仓库根目录的 `render.yaml`。
4. 提示填写 `GATEWAY_TOKEN` 时，填一个你自己定的令牌（比如一串随机字母数字），点 **Apply** 开始部署。
5. 首次构建约 5～10 分钟（要编译网页版 App）。完成后在服务页面顶部能看到网址，形如 `https://smarthome-demo-xxxx.onrender.com`。
6. 手机浏览器（iPhone 用 Safari）打开这个网址，网关地址会自动填好，令牌填第 4 步设置的值。
   Android APK 里网关地址也填这个 https 网址。

注意：

- 网址是公开的。知道令牌的人可以操作演示设备（都是假设备），所以令牌不要用 `devtoken` 这类容易猜的值。演示门锁 PIN 是 `2468`。
- 免费实例没有持久磁盘：休眠或重新部署后，告警记录清空，演示设备回到初始状态。
- 以后往这个分支推送代码，Render 会自动重新部署。
- 服务器在新加坡。国内访问 onrender.com 可能较慢，打不开时换个网络再试。

## 方式二：GitHub Codespaces

1. 打开仓库页面，切到分支 `claude/happy-tesla-4wh7up`。
2. 点绿色的 **Code** 按钮 → **Codespaces** → **Create codespace on claude/happy-tesla-4wh7up**。
3. 等它启动。启动后会自动构建并运行演示网关（`.devcontainer/devcontainer.json`），首次约 5 分钟。想看进度，在终端执行：
   ```bash
   docker compose -f docker-compose.demo.yml logs -f
   ```
4. 下方 **端口（Ports）** 面板出现 `8000 智能家居演示`，点地球图标在浏览器打开，令牌 `devtoken`。
5. 用手机打开：在端口面板右键 8000 → **端口可见性（Port Visibility）→ Public**，复制「转发地址」（形如 `https://xxx-8000.app.github.dev`）到手机浏览器。
   不设为 Public 也能打开，但手机浏览器需要先登录 GitHub。

用完在 [github.com/codespaces](https://github.com/codespaces) 停止或删除，避免用掉免费额度。

## 其他云平台

`Dockerfile` 会读取平台提供的 `PORT` 环境变量，所以 Railway、Zeabur、Koyeb 等支持 Dockerfile 的平台也能直接部署：选择本仓库，设置环境变量 `GATEWAY_TOKEN`（自定令牌）和 `GATEWAY_ADAPTERS=mock`，需要演示开锁时再加 `GATEWAY_UNLOCK_PIN`。

## 接真实设备时

云端只适合演示。接真实设备时，网关和 Home Assistant 要跑在家里（NAS、迷你主机、树莓派等），这样才能通过局域网控制设备；要从外网访问，按 `docs/architecture.md` 第 7 节配置远程访问。
