# ProxySwitch

一款轻量的 **macOS 原生菜单栏网络联动工具**（Swift 单文件实现、零第三方依赖、事件驱动），专门解决多网络环境下反复手动切代理、开关 Clash 的麻烦。

---

## 目录

- [它解决什么问题](#它解决什么问题)
- [核心功能与互斥机制](#核心功能与互斥机制)
- [直接下载使用（免编译）](#直接下载使用免编译)
- [从源码构建](#从源码构建)
- [菜单栏与设置项详解](#菜单栏与设置项详解)
- [典型使用场景示例](#典型使用场景示例)
- [工作原理与注意事项](#工作原理与注意事项)
- [License](#license)

---

## 它解决什么问题

日常使用 Mac 经常会在几种网络之间切换：

1. **连手机热点**：手机开启 Clash 并打开「允许来自局域网的连接」后，希望 Mac 连上热点时自动把系统代理指向手机网关（例如 `10.23.216.132:7890`），断开或换网后自动释放。
2. **在宿舍 / 家里 / 公司 Wi-Fi**：希望开启本机 **Clash Verge**（TUN 模式 + `rule` 规则代理）。
3. **在校园网 / 公共 Wi-Fi**：需要彻底关闭代理和虚拟网卡（关闭 Clash TUN + 切为 `direct` 直连 + 关掉系统代理），避免干扰校园网认证或被终端准入检测。

`ProxySwitch` 基于 macOS 系统级 `SCDynamicStore` 事件监听当前网卡 IP 变化（不做轮询），在网络切换的瞬间自动完成上述动作。

---

## 核心功能与互斥机制

### 1. 两大独立功能（支持互斥自动切换）

| 功能 | 触发逻辑 | 执行动作 |
| :--- | :--- | :--- |
| **手机代理（热点转发）** | 本机 IP 命中「手机热点网段前缀」 | 自动设置 macOS Web/HTTPS（可选 SOCKS）系统代理到手机 Clash；离开热点自动关闭 |
| **本机 Clash Verge 控制** | 本机 IP 命中「Clash 启用网段前缀」 | 仅连上指定网段才开启本机 Clash（TUN 模式 / `rule` 模式 / 可选 `127.0.0.1:7897` 本地代理）；处于其他网络时自动关闭 |

### 2. 互斥规则（防冲突）

因为「**把流量转给手机 Clash**」和「**用本机 Clash 接管流量**」在路由上会互相打架，两者的**自动模式严格互斥**（三选一单选）：

- **关闭自动（仅手动）**：不自动修改任何开关，仅通过菜单栏手动点按控制。
- **自动：手机代理**：切到此模式时，会自动关掉未选中的本机 Clash（关闭 `TUN`、切回 `direct` 直连、清理 `127.0.0.1` 系统代理），然后按热点网段自动接管系统代理。
- **自动：本机 Clash**：切到此模式时，会自动关掉未选中的手机代理（清理外部系统代理），然后按指定 Wi-Fi 网段自动开启或关闭本机 Clash。

### 3. 其他特性

- **动态识别网卡**：按系统服务名（默认 `Wi-Fi`）自动匹配硬件接口（如 `en0` / `en1`），不再写死 `en0`。
- **无需定位权限**：通过本机 IP 网段前缀识别网络，不读取 Wi-Fi SSID，不需要申请定位权限，也支持逗号分隔多个网段前缀。
- **实时状态刷新**：每次点开菜单栏图标前都会实时拉取当前 IP、系统代理以及 Clash 内核状态。
- **手动保护机制**：在同一 IP 下手动修改代理或 Clash 状态后，自动逻辑会暂时退让，直到下次切换网络重新触发。

---

## 直接下载使用（免编译）

仓库内提供了打包好的 **macOS Universal Binary（同时兼容 Apple Silicon M 系列与 Intel Mac，macOS 13+）**：

- 仓库直链：[dist/ProxySwitch-macos-universal.zip](dist/ProxySwitch-macos-universal.zip)
- 或前往本仓库 **Releases** 页面下载最新压缩包。

### 安装步骤

1. 下载并解压 `ProxySwitch-macos-universal.zip`，得到 `ProxySwitch.app`。
2. 将 `ProxySwitch.app` 拖入 **「应用程序」**（`/Applications`）文件夹。
3. **首次运行放行**：由于未购买 Apple 开发者公证证书，首次打开如被 Gatekeeper 拦截，可**右键点击 `ProxySwitch.app` → 打开**，或在终端执行：
   ```bash
   xattr -dr com.apple.quarantine /Applications/ProxySwitch.app
   open /Applications/ProxySwitch.app
   ```
4. **开机自启（推荐）**：前往 **系统设置 → 通用 → 登录项**，将 `ProxySwitch.app` 添加到「登录时打开」。

---

## 从源码构建

需要 **macOS 13+** 与 **Xcode Command Line Tools**（`xcode-select --install`）：

```bash
git clone https://github.com/baimochen/ProxySwitch.git
cd ProxySwitch
./build.sh
open ProxySwitch.app
```

`build.sh` 会自动编译 `arm64` 与 `x86_64` 双架构并用 `lipo` 合并为 Universal Binary，完成后输出：
- `ProxySwitch.app`（本地可直接运行的应用包）
- `dist/ProxySwitch-macos-universal.zip`（用于分发的压缩包）

---

## 菜单栏与设置项详解

### 菜单栏结构

- **顶部状态区**：实时显示当前网卡名与 IP、所属网段标签、手机代理开关与地址、本机 Clash 的 `TUN` / 本地代理 / 出站模式状态。
- **自动模式（互斥）**：三选一单选（`关闭自动` / `自动：手机代理` / `自动：本机 Clash`）。
- **手机代理（热点转发）**：手动「开启手机代理」「关闭手机代理」。
- **本机 Clash 控制**：
  - 「一键开启本机 Clash（TUN + 规则）」 / 「一键关闭本机 Clash（关 TUN + 直连）」
  - 「TUN 模式」独立开关
  - 「本地系统代理（`127.0.0.1:7897`）」独立开关
  - 「出站模式」子菜单（`rule` / `direct` / `global`）
  - 「打开 Clash Verge…」快捷入口

### 设置面板说明

| 分组 | 配置项 | 说明与示例 |
| :--- | :--- | :--- |
| **自动模式** | 自动模式三选一 | 互斥选择关闭 / 自动手机代理 / 自动本机 Clash |
| **手机代理** | 手机热点网段前缀 | 用逗号分隔多个前缀，例：`10.23.216., 172.20.10.` |
| | 手机代理 IP / 端口 | 手机热点开启 Clash 后的网关 IP 与端口，例：`10.23.216.132` / `7890` |
| | SOCKS 端口 | 可选同时开启 SOCKS 代理，默认 `7891` |
| | 热点名称（展示用） | 仅用于菜单内显示，不参与网络匹配 |
| | 开启时关闭 PAC | 勾选后设置代理会自动关闭系统 PAC 自动配置 |
| **本机 Clash** | Clash 启用网段前缀 | **仅连上这些网段才开启本机 Clash**，逗号分隔，例：`192.168.1., 192.168.31.` |
| | 本机 Clash 端口 | Clash Verge 的 Mixed/HTTP 端口，默认 `7897` |
| | Clash Socket 路径 | 默认自动定位 `/var/run/clash-verge-service/users/<uid>/verge-mihomo.sock` |
| | 控制选项 | 可分别勾选是否联动 `TUN 模式`、`出站模式（rule/direct）`、`本地系统代理` |
| **通用** | 网络服务名 | 系统设置 → 网络中的服务名，默认 `Wi-Fi` |
| | 菜单栏图标 | 可选钥匙、Wi-Fi、地球、盾牌、闪电等 SF Symbols 图标 |

---

## 典型使用场景示例

### 场景 A：外出连手机热点（让 Mac 走手机 Clash）
1. 手机打开个人热点，并在手机 Clash 中开启「允许来自局域网的连接」。
2. 在 `ProxySwitch` 设置中填好手机热点网段前缀（如 `10.23.216.`）和手机代理 IP:端口（如 `10.23.216.132:7890`）。
3. 将自动模式选为 **「自动：手机代理」**。
4. 以后每次 Mac 连上手机热点，系统代理自动接管；切回其他 Wi-Fi 自动还原直连。

### 场景 B：宿舍/家里自动开本机 Clash，去校园网自动全关
1. 在 `ProxySwitch` 设置的「Clash 启用网段前缀」中填入信任 Wi-Fi 的网段（如 `192.168.1., 192.168.31.`）。
2. 勾选 `控制 TUN 模式`、`控制出站模式`，如需系统代理也可勾选 `同时控制本机 Clash 系统代理`。
3. 将自动模式选为 **「自动：本机 Clash」**。
4. 回到宿舍/家里连上对应 Wi-Fi，自动打开 Clash TUN 与 `rule` 模式；进入校园网或其他公共 Wi-Fi 时自动关闭 TUN 并切为 `direct` 直连。

---

## 工作原理与注意事项

1. **事件驱动监听**：通过 macOS `SystemConfiguration` 框架的 `SCDynamicStore` 监听 `State:/Network/Global/IPv4` 与对应接口变化，并对短时间内的多次 IP 波动做 `0.6s` 防抖合并。
2. **Clash Verge 通信机制**：通过 Clash Verge 内核暴露的本地 Unix Socket（`verge-mihomo.sock`）发送 `GET` / `PATCH /configs` 请求控制内核。
   - **已知限制**：通过内核 Socket 开关 **TUN 模式** 会在系统内核层立即生效（实时创建/销毁 `utun` 虚拟网卡与 DNS 劫持），但 Clash Verge 桌面端的图形界面按钮及 `verge.yaml` 不会反向同步刷新（重启 Clash Verge 会恢复其 `verge.yaml` 默认设置）。
3. **子进程超时保护**：所有 `networksetup` / `ipconfig` / `curl` 调用均在独立串行后台队列执行并带超时保护，不会阻塞菜单栏主线程。

---

## License

MIT
