from __future__ import annotations

import os
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Settings:
    # App 访问网关用的令牌。生产环境务必设置为足够长的随机串。
    token: str = field(default_factory=lambda: os.environ.get("GATEWAY_TOKEN", ""))
    # 启用的适配器，逗号分隔：mock, ha
    adapters: tuple[str, ...] = field(
        default_factory=lambda: tuple(
            a.strip() for a in os.environ.get("GATEWAY_ADAPTERS", "mock").split(",") if a.strip()
        )
    )
    ha_url: str = field(default_factory=lambda: os.environ.get("HA_URL", "http://localhost:8123"))
    # HA 长期访问令牌：HA 个人资料 -> 安全 -> 长期访问令牌
    ha_token: str = field(default_factory=lambda: os.environ.get("HA_TOKEN", ""))
    # 远程开锁 PIN（4 位以上数字）。不设置则禁止通过 App 开锁，只能上锁。
    unlock_pin: str = field(default_factory=lambda: os.environ.get("GATEWAY_UNLOCK_PIN", ""))
    # 数据目录（告警记录等）。不设置则只保存在内存中，重启后清空。
    data_dir: str = field(default_factory=lambda: os.environ.get("GATEWAY_DATA_DIR", ""))
    # Flutter 网页版的构建产物目录，设置后网关在 / 提供网页版 App
    web_dir: str = field(default_factory=lambda: os.environ.get("GATEWAY_WEB_DIR", ""))
