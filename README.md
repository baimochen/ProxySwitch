# ProxySwitch

macOS 菜单栏网络联动工具，提供**两种互斥的自动切换模式**及完整的手动快捷控制：

1. **手机代理（热点转发）**：手机开启 Clash 并打开「允许来自局域网的连接」后，电脑连上手机热点即自动将系统代理指向手机 Clash，离开热点自动关闭
2. **本机 Clash Verge 控制**：仅在连上指定 Wi-Fi 网段时自动开启本机 Clash（TUN 模式 / `rule` 规则模式 / 可选本地系统代理 `127.0.0.1:7897`），处于校园网等其他网络时自动关闭

> 两种自动模式互斥，同一时间只会启用其中一种（也可选择「关闭自动」，仅用菜单手动控制）。

## 功能

- **事件驱动**：基于 `SCDynamicStore` 监听系统网络配置变化，不做轮询
- **动态识别网卡**：自动按服务名（如 `Wi-Fi`）查找对应的设备接口（不写死 `en0`）
- **互斥自动模式**：
  - `关闭自动（仅手动）`
  - `自动：手机代理（连热点转手机 Clash）`
  - `自动：本机 Clash（仅连指定 Wi-Fi 开启）`
- **手机代理快捷操作**：菜单一键「开启手机代理 / 关闭手机代理」
- **本机 Clash 快捷操作**：通过 Clash Verge 内核本地 Unix Socket（`/var/run/clash-verge-service/users/<uid>/verge-mihomo.sock`）直接控制，菜单支持「一键开启本机 Clash」「一键关闭本机 Clash」「TUN 模式」「本地系统代理（`127.0.0.1:7897`）」「出站模式（`rule`/`direct`/`global`）」及「打开 Clash Verge…」

## 构建

需要 macOS 13+ 和 Xcode Command Line Tools。

```bash
./build.sh
open ProxySwitch.app
```

首次运行后建议把 `ProxySwitch.app` 拖进「应用程序」，并在 系统设置 → 通用 → 登录项 中添加到开机启动。

## 已知限制

- 判断依据是本机 IP 网段前缀（支持逗号分隔多个前缀），不是 SSID（无需定位权限，也更可靠）。
- 通过内核 Unix Socket 切换 Clash **TUN 模式** 会立即在内核生效（创建/销毁 `utun` 网卡），但 Clash Verge 图形界面上的 TUN 开关按钮不会被动同步刷新。

## License

MIT
