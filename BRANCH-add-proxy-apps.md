# `add-proxy-apps` 分支说明

本分支 = **上游主线（`qwe-qaq/Actions-OpenWrt-AN758X` 的 `main`）+ 代理插件链 + 自用定制**。

`main` 分支与上游**完全一致**（无任何自有改动），所有定制只落在本分支。

- 基线提交：`1bdb291`（= 上游 `main`）
- 与 `main` 的差异：**18 个文件，+1015 / −23**
- 2026-11-01 追加代理/组网插件（**homeproxy + zerotier**，passwall2 同日移出）后，又动了 17 个文件，详见第五节

---

## 一、和 `main` 的差异一览

| 文件 | 变更 | 一句话说明 |
|---|---|---|
| `configs/*.config`（12 个机型） | +60 左右 ×12 | 统一补 `kmod-nft-queue` / `libstdcpp` / `kmod-dummy`，再追加 `frpc` / `gecoosac` / homeproxy / zerotier / pw2 内核前置 |
| `configs/an7581.config`、`an7583.config`（SoC 基座镜像） | +40 左右 ×2 | 同上补三项 + 第 25/26 段（代理插件与 pw2 内核前置，CI 用的是上游源码里那份，插件不重复加） |
| `configs/h3c_hm2004-du.config` | +71 / −12 | 同上三项 + `frpc` / `gecoosac`，并**关闭 FTTR 下行** |
| `diy-part1.sh` | +115 / −17 | 新增 `ADD_GECOOSAC`（含失败降级）；`ADD_FLUENT=true`；`ADD_FTTR` 默认 false |
| `.github/workflows/build-ponwrt.yml` | +105 / −4 | `private_repo` 默认 none；libstdcpp 硬校验；dl 清理防误删；收集 apk |

`main` 里**没有**的任何改动，本分支也**没有**；反过来本分支不修改上游的任何既有行为（除了下面明确列出的 4 处默认值）。

---

## 二、config 改动

### 1. 全部 14 个机型都加了这三项

```kconfig
CONFIG_PACKAGE_kmod-nft-queue=y    # NFQUEUE 队列
CONFIG_PACKAGE_libstdcpp=y         # C++ 运行时（apk 产物名 libstdcpp6）
CONFIG_PACKAGE_kmod-dummy=y        # dummy 空网卡
```

**为什么加 `kmod-nft-queue`**：homeproxy 系的透明代理依赖 NFQUEUE。ssr-plus 用不到它，但两者共存无害。

**为什么加 `libstdcpp`（重点）**：ImmortalWrt SNAPSHOT 的 apk 仓库里**没有 `libstdcpp6` 这个包**，而 `nmap` / `nping` 的 depends 里硬写着它。于是任何依赖 `nping` 的插件（典型：`luci-app-ssr-plus`）都装不上，报：

```
libstdcpp6 (no such package): required by: nping-7.991-r1[libstdcpp6]
```

编进固件后，apk 侧把 `libstdcpp6` 视为「已安装」，`nping` / `ssr-plus` 就能直接从源安装。

> ⚠ **符号名必须写 `libstdcpp`，不能写 `libstdcpp6`。**
> apk 的产物名 = 包名 + `ABI_VERSION`（`include/feeds.mk` 的 `FormatABISuffix`），
> `libstdcpp` 的 `ABI_VERSION:=6`，所以编出来自然叫 `libstdcpp6-<gcc版本>-rX.apk`。
> 在 config 里写 `CONFIG_PACKAGE_libstdcpp6` 会被 `defconfig` 当无效符号**静默剔除**。

**为什么加 `kmod-dummy`**：占位空网卡，分流测试 / 多实例场景要用。

### 2. 全部机型都加了 frpc + 集客 AC

```kconfig
CONFIG_PACKAGE_frpc=y
CONFIG_PACKAGE_luci-app-frpc=y
CONFIG_PACKAGE_luci-i18n-frpc-zh-cn=y
CONFIG_PACKAGE_gecoosac=y
CONFIG_PACKAGE_luci-app-gecoosac=y
CONFIG_PACKAGE_luci-i18n-gecoosac-zh-cn=y
```

- **frpc**：来自 immortalwrt 的 luci feed，只需勾选。
- **gecoosac**（集客 AC 控制器）：来自第三方仓库 `laipeng668/luci-app-gecoosac`，由 `diy-part1.sh` 拉取。后端 `gecoosac` 通过 `PROVIDES:=gecoosac-files gecoosac-common` 满足前端的全部依赖，不需要额外包，也不会和官方 feeds 冲突。后端还是**预编译二进制**（`PKG_ARCH:=ac_linux_arm64`，从该仓库 Release 下载），AN758x 是 aarch64，架构对得上。

**为什么只改 `configs/<机型>.config`**：这三项原来是只给 `h3c_hm2004-du` 加的（2026-10-30 提升为全机型）。机型 config 是唯一被 `cat` 追加进 `.config` 的那一层；`configs/an7581.config` / `an7583.config` 在本仓库只是上游 defconfig 的镜像，CI 用的是 `pbs05/ponwrt` **源码树里**的那份，改这边的副本不生效，所以不重复加。

**注意 `diy-part1.sh` 的 `ADD_GECOOSAC` 不能关**：关掉后源码拉不下来，而机型 config 里仍写着 `luci-app-gecoosac=y`，`defconfig` 会把它当无效符号**静默剔除**——不报错，但固件里就是没有，很难察觉。

### 3. `h3c_hm2004-du.config` 关闭 FTTR 下行

5 个包 + 3 个 Cargo feature 开关全部改为 `is not set`：

| 分组 | 包 |
|---|---|
| 后端三件套 | `kmod-h3c-fmcs`、`h3c-fmcs-firmware`、`h3c-fttr-tools` |
| 界面与中文包 | `luci-app-fttr`、`luci-i18n-fttr-zh-cn` |
| Cargo feature | `CONFIG_FTTR_DEVICE_HL202`、`CONFIG_FTTR_DEVICE_HWTC`、`CONFIG_FTTR_ACS` |

**为什么关**：
1. 后端三件套来自 `qwe-qaq/openwrt-fttr`（私有仓库，本 fork 无读权限，HTTP 404）；
2. 界面 `luci-app-fttr` 虽然来自公开仓库 `LazuliKao/luci-app-fttr`，但它在 `diy-part1.sh` 里与后端共用 `ADD_FTTR` 总开关，且 `LUCI_DEPENDS` 硬依赖 `+h3c-fttr-tools`——后端不在时，界面单独编出来也是废的。

**为什么不能直接删行**：上游基座 `configs/an7581.config` 里**预置了这 5 个包的 `=y`**。工作流的加载顺序是「先 `cp` 基座，再 `cat` 机型 config 追加」，后写覆盖先写。只有显式 `is not set` 才盖得住。

> ⚠ `# CONFIG_PACKAGE_xxx is not set` **本身就是 kconfig 指令**，前面不能再叠一个 `#`。
> 写成 `# CONFIG_PACKAGE_xxx is not set   # 说明文字` 会变成纯注释，等于没写。

**重新启用 FTTR 的 4 步**：
1. Secrets 里配 `PRIVATE_REPO_TOKEN`（对 `qwe-qaq/openwrt-fttr` 有 Contents 读权限）
2. 本文件把上面几行改回 `=y`
3. `diy-part1.sh` 的 `ADD_FTTR` 改为 `true`
4. 触发构建时 `private_repo` 下拉选 `qwe-qaq/openwrt-fttr`

---

## 三、`diy-part1.sh` 改动

| 项 | `main` | 本分支 | 原因 |
|---|---|---|---|
| `ADD_FLUENT` | `false` | **`true`** | 用 Fluent 2 主题 |
| `ADD_GECOOSAC` | 无此项 | **新增，`true`** | 集客 AC 控制器；拉取/下载失败只跳过不中断 |
| `ADD_FTTR` | `true` | **`false`** | 私有仓库无权限，匿名 clone 必然 404 并 `exit 1` |

### `ADD_GECOOSAC` 的实现要点

`laipeng668/luci-app-gecoosac` 这个仓库**根目录没有 Makefile**，两个包分别在子目录：

```
luci-app-gecoosac/   前端
gecoosac/            后端（预编译二进制）
```

所以 `diy-part1.sh` 里做了三件事：

1. **展平**：把两个子目录提到 `package/custom/` 顶层。若整仓留在同名目录 `package/custom/luci-app-gecoosac-src/`，会触发脚本后方的「清理重复嵌套目录」逻辑——`luci-app-gecoosac/luci-app-gecoosac` 含 Makefile 会被判为重复嵌套而误删，导致前端包注册不上。
2. **补 LICENSE**：`gecoosac/Makefile` 的 `Build/Prepare` 引用 `../LICENSE`（即 `package/custom/LICENSE`）。展平只搬了子目录，仓库根的 LICENSE 要单独补上去，否则 prepare 阶段报 `cp: cannot stat '../LICENSE'`。
3. **进 `REQUIRED` 校验**：`ADD_GECOOSAC=true` 且**未降级**时，把 `luci-app-gecoosac` 加进必装清单，索引里查不到就报错，不会静默编出一个没界面的固件。
4. **预取后端二进制 + 失败降级**（`gecoosac_prefetch` / `skip_gecoosac`）：见下节。

### 集客 AC 的降级策略（2026-10-30）

集客 AC 有**两重**外部依赖：仓库（`git clone`）+ GitHub Release 里的预编译二进制（`make download`）。而 `configs/` 里 12 个机型现在全勾了它——任何一处挂掉 `make` 都会硬失败，等于一个第三方 Release 能拖垮全部机型。

| 失败点 | 原行为 | 现行为 |
|---|---|---|
| `git clone` 仓库失败 | `exit 1`，整轮结束 | `::warning::` + 跳过该插件 |
| 后端二进制 404 / 哈希不符 | 推迟到 `make download` 才炸，届时无解 | `gecoosac_prefetch` **提前**下载校验，失败即跳过 |

实现要点：

1. `gecoosac_prefetch <包目录> <dl 目录>`：从 `gecoosac/Makefile` 解析 `PKG_VERSION` 和对应架构的 `PKG_HASH`（`PKG_ARCH:=xxx` 紧跟 `PKG_HASH:=yyy` 的成对结构），自己把 Release 资产下到 `dl/$(PKG_SOURCE)` 并 `sha256sum -c` 校验；文件已在 `dl/` 且哈希对得上就直接返回，不重复下载。
   - **为什么要提前**：等 `make` 发现 404 时已经没法优雅退出，`make download` 一挂整轮就结束了。提前探测 + 预置缓存是唯一能「warn 而不是 die」的位置。
   - `PKG_HASH:=dummy`（该架构上游没编预编译包）同样按失败处理。
   - 架构默认 `ac_linux_arm64`（AN758x 全系 aarch64），可用环境变量 `GECOOSAC_ARCH` 覆盖。
2. 失败时走 `skip_gecoosac`：打 `::warning::`、写 `$GITHUB_STEP_SUMMARY`（run 页面 Summary 直接可见），并删掉 `package/custom/{gecoosac,luci-app-gecoosac}` → `defconfig` 把 `.config` 里的 `CONFIG_PACKAGE_gecoosac*` 当无效符号静默剔除 → 固件少一个插件，其余照常编完。
3. `REQUIRED` 校验必须带 `GECOOSAC_OK` 判断，否则降级后「索引里查不到就 `exit 1`」会把降级又抵消回去。

> ⚠ **体积代价**：arm64 那份二进制约 **16 MB**（`gecoosac-2.2.20251015-ac_linux_arm64`，16,318,648 字节）。现在**每个**机型都会因此变大一圈，而之前只有 2004-DU 有。想精简的机型把 config 里那三行 gecoosac 删掉即可（`ADD_GECOOSAC` 保持 `true` 也无妨，只是不再被选中）。

---

## 四、`build-ponwrt.yml` 改动（5 处）

### 1. `private_repo` 默认值改为 `none`

```yaml
private_repo:
  default: 'none'      # 上游原为 'qwe-qaq/openwrt-fttr'
```

`qwe-qaq/openwrt-fttr` 是私有仓库，本 fork 无读权限时：
- `Probe FTTR repos visibility` 探测判定为 private
- `Setup private repo credentials` 在没有任何凭证时 `exit 1`
- **整次构建在编译前就失败**

默认 `none` 让构建无痛跳过 FTTR。拿到 collaborator 权限后，在下拉里选回即可。

### 2. 新增 `libstdcpp` 硬校验

插在 `✅ PON 关键包校验通过` 之后：

```bash
if ! grep -q "^CONFIG_PACKAGE_libstdcpp=y" .config; then
  echo "::error::libstdcpp 未启用（apk 产物为 libstdcpp6），nping / luci-app-ssr-plus 将无法安装"
  # ... 5 条诊断信息
  exit 1
fi
```

`defconfig` 会把源码树里不存在的符号静默剔除。没有这道校验，`libstdcpp` 一旦漏掉，要等到刷完机装 ssr-plus 才发现。

### 3. `find dl` 加 `-maxdepth 1`（2 处）

```diff
- find dl -size -1024c -type f -exec ls -l {} \; 2>/dev/null
- find dl -size -1024c -type f -exec rm -f {} \; 2>/dev/null
+ # ⚠ 只清 dl/ 顶层，禁止递归
+ find dl -maxdepth 1 -type f -size -1024c -print -exec rm -f {} \; 2>/dev/null
```

原写法会递归删掉 `dl/` 下**所有**小于 1KB 的文件。但 `dl/go-mod-cache/` 里大量 Go 源文件小于 1KB（`lo/internal/rand`、`golib/clock`、`golib/errors`、`protobuf/internal/editiondefaults` 等），删掉后目录变空，Go 判定包不存在并报：

```
no required module provides package ...
```

这个错出现在编译阶段，指向完全不相干的地方。

### 4. 新增两个步骤

**`Drop go-mod-cache from dl cache`**（步骤 18.7，`always()` 执行）

`dl/go-mod-cache` 的模块目录是只读的，Go 不会重新校验已解压的模块内容——一旦在打包/解包环节被破坏就无法自愈。构建结束后主动丢弃，让下次重新下载，换取缓存永远干净。

**`Collect libstdcpp6 apk` + `Upload libstdcpp6 apk`**（步骤 20.5）

不刷机也能给已刷好的路由器补装 `libstdcpp6`。收集内容：
- `libstdcpp6-*.apk`
- `nping-*.apk`（ssr-plus 依赖它，一起给）
- `key-build.pem` / `public-key.pem`（导入 `/etc/apk/keys` 后装自编包不用 `--allow-untrusted`）

产出为 Artifact：`libstdcpp6_apk_<机型>_<时间>`。

> ⚠ 必须排在 `Organize files` 之前——那一步会 `rm -rf bin/targets/*/*/packages`。

在路由器上补装：

```sh
# 方式一：导入公钥后直接装（推荐）
cp public-key.pem /etc/apk/keys/
apk add ./libstdcpp6-*.apk

# 方式二：不导入公钥
apk add --allow-untrusted ./libstdcpp6-*.apk
```

---

## 五、代理/组网插件（homeproxy / zerotier）—— 2026-11-01

> **⚠ 状态变更（2026-11-01 晚）**：**passwall2 已移除**，本分支最终只启用
> **homeproxy + zerotier** 两个。`diy-part1.sh` 里 `ADD_PASSWALL2=false`，
> 14 个 config 的第 25 节只剩 homeproxy / sing-box / zerotier 六行。
> 理由：passwall2 与 homeproxy 内核同为 sing-box，两套 UI 功能高度重叠，
> 同时装纯属浪费约 8~10 MB 体积和一份维护成本。
> 下方 2~3 小节关于 passwall2 来源、`Basic Core` choice、`INCLUDE_*` 坑的
> 分析仍完整保留 —— 将来要加回来只需 `ADD_PASSWALL2=true` 并恢复 config 里的
> 那几行（GIT 历史里两个 commit 都有）。

### 1. 两个组件到底从哪来

| 组件 | 来源 | 需要 clone？ |
|---|---|---|
| `luci-app-homeproxy` | `feeds/luci/applications/luci-app-homeproxy` | **不需要**，feeds 自带 |
| `luci-app-zerotier` | `feeds/luci/applications/luci-app-zerotier` | **不需要** |
| `sing-box`（homeproxy 核心）/ `ucode-mod-digest` / `kmod-nft-tproxy` | `feeds/packages` + 主源码 `package/utils/ucode` | **不需要** |
| `zerotier` 后端 | `feeds/packages/net/zerotier`（1.16.2） | **不需要** |
| ~~`luci-app-passwall2`~~ | ~~`Openwrt-Passwall/openwrt-passwall2`~~ | ~~需要~~ **已移除** |

### 2. passwall2 为什么不 clone 后端仓库（重点）

`xiaorouji/openwrt-passwall-packages` 的 18 个顶层包目录——
`chinadns-ng`、`dns2socks`、`geoview`、`hysteria`、`ipt2socks`、`microsocks`、
`naiveproxy`、`shadow-tls`、`shadowsocks-rust`、`shadowsocksr-libev`、`simple-obfs`、
`sing-box`、`smartdns`、`tcping`、`v2ray-geodata`、`v2ray-plugin`、`xray-core`、`xray-plugin`
——**在 `immortalwrt/packages` 里每一个都有一份同名包**。

所以再从 passwall-packages clone 一份到 `package/custom`，等于：
1. 同名包被定义两次，`scan.mk` 报冲突（`tmp/.packageinfo` 里只会留一个，行为取决于扫描顺序）；
2. `sing-box` 白编一遍（feeds 里已经是 **1.14.3**，够用）。

结论：**只 clone UI**。后端全部走 feeds，版本与 SDK 严格匹配。

### 3. passwall2 底层只保留 sing-box 的实现

`luci-app-passwall2` 的 `Makefile` 里 `Basic Core` 是个 **choice**：

```kconfig
choice
    prompt "Basic Core"
    default PACKAGE_luci-app-passwall2_Basic_Core_All if aarch64||arm||i386||x86_64
    default PACKAGE_luci-app-passwall2_Basic_Core_Xray

    config ..._Basic_Core_Xray
        select PACKAGE_xray-core
    config ..._Basic_Core_SingBox
        select PACKAGE_sing-box          ← 只有这一个，不带 xray
    config ..._Basic_Core_All
        select PACKAGE_xray-core
        select PACKAGE_sing-box
endchoice
```

**aarch64 的默认值是 `All`（xray + sing-box 两个都装）**。所以要：

```kconfig
CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_SingBox=y
# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_All is not set
# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray is not set
CONFIG_PACKAGE_sing-box=y
# CONFIG_PACKAGE_xray-core is not set
```

### 4. 必须显式 `is not set` 的 7 个 INCLUDE_*

这些在 aarch64 下 **默认就是 y**，只"不选"没用，必须写 `is not set` 才真关掉：

| 符号 | 会拉进来的东西 |
|---|---|
| `..._INCLUDE_Haproxy` | `haproxy` |
| `..._INCLUDE_Shadowsocks_Rust_Client` | `shadowsocks-rust-sslocal` |
| `..._INCLUDE_Shadowsocks_Rust_Server` | `shadowsocks-rust-ssserver` |
| `..._INCLUDE_ShadowsocksR_Libev_Client` | `shadowsocksr-libev-ssr-local` / `-redir` |
| `..._INCLUDE_ShadowsocksR_Libev_Server` | `shadowsocksr-libev-ssr-server` |
| `..._INCLUDE_Simple_Obfs` | `simple-obfs-client` |
| `..._INCLUDE_V2ray_Plugin` | `v2ray-plugin` |

漏掉任何一个，固件就会白白胖一圈（hapsroxy ~1.5MB、ss-rust ~4MB）。

### 5. 透明代理只留 nftables

```kconfig
CONFIG_PACKAGE_luci-app-passwall2_Nftables_Transparent_Proxy=y
# CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy is not set
```

ponwrt 用 `firewall4`，`Nftables_Transparent_Proxy` 本来就默认 y；iptables 那套会额外拉
`ipset` / `iptables-zz-legacy` / 一堆 `kmod-ipt-*`，纯浪费。

### 6. 依赖闭环（已逐项核实，2026-11-01）

| 包 | 依赖 | 在 feeds 里？ |
|---|---|---|
| `luci-app-homeproxy` | `sing-box` / `firewall4` / `kmod-nft-tproxy` / `ucode-mod-digest` | ✓ 全部满足（`ucode-mod-digest` 由 `package/utils/ucode` 的 `digest` 模块生成） |
| `luci-app-~~passwall2~~` | ~~`tcping` / `geoview` / `v2ray-geoip` / `v2ray-geosite` / `lyaml` / `luci-lib-jsonc` / `ip-full`~~ | **已移除**（2026-11-01），这些依赖随之不进固件 |
| `zerotier` | `libstdcpp` / `kmod-tun` / `libminiupnpc` / `libnatpmp` / `libatomic` | ✓ `libstdcpp` 本分支已 `=y` |

任一依赖缺失，`defconfig` 会把 `=y` **静默剔除**——所以 `build-ponwrt.yml`
加了一道硬校验（第 5 处改动），编之前就 `exit 1`。

### 7. 体积（passwall2 移除后重算）

基线（改前）单台 `squashfs-sysupgrade.itb` 约 **14 MB**。

| 新增 | 估算 |
|---|---|
| `sing-box`（homeproxy 唯一核心） | +30~35 MB |
| `luci-app-homeproxy` 界面 + i18n（ucode） | +1~2 MB |
| `zerotier`（1.16.2）+ `luci-app-zerotier` | +1.5~2 MB |
| **合计** | **约 +33~39 MB → 单台 47~53 MB** |

相比"passwall2 在的时候"省下的部分：`v2ray-geoip` + `v2ray-geosite`（**12~18 MB**，
已压缩 dat、squashfs 几乎不二次压缩，是最大一块）、`luci-app-passwall2` 界面
（~1 MB）、`tcping` / `geoview` / `chinadns-ng` / dns2socks / ipt2socks / microsocks（~1 MB）。
**注意 `v2ray-geodata` 不会再进固件**——`sing-box` 与 `luci-app-homeproxy` 都不依赖它，
homeproxy 的规则集是运行时从远程 rule-set 拉取，不占固件。

设备 NAND 256 MB、ubi 占满整片，53 MB 约占 21%，overlay 仍剩 ~200 MB。

### 8. 后装 passwall2：内核前置已预置（2026-11-01）

固件里不带 pw2（与 homeproxy 同为 sing-box 内核、两套 UI 重复），但**内核前置全部预置**，
将来想用 pw2 直接 `apk add` 装上就能跑，不会因为缺 kmod 起不来。

依据是 pw2 26.10.x 源码 `luci-app-passwall2/root/usr/share/passwall2/app.sh` 的
`check_dep()`——它启动时会去 `/lib/apk/packages/<pkg>.list`（旧系统是
`/usr/lib/opkg/info/<pkg>.control`）逐个自查：

```sh
# nft 通路（firewall4 + dnsmasq-full nftset 时自动选中）
dep_list="kmod-nft-socket kmod-nft-tproxy kmod-nft-nat"
# iptables 通路（本固件用不到）
dep_list="iptables-mod-tproxy iptables-mod-socket iptables-mod-iprange \
          iptables-mod-conntrack-extra iptables-mod-extra kmod-ipt-nat"
```

`app.sh` 只查 nft 那 3 个；但走 sing-box 后端时还隐含需要 3 个（pw2 不自查，缺了
「自动分流 / 进程识别」这类功能会静默失效）：

| kmod | 作用 | 在 config 哪段 |
|---|---|---|
| `kmod-nft-socket` / `kmod-nft-tproxy` / `kmod-nft-nat` | 透明代理本体 | 第 4 段 |
| `kmod-inet-diag` | sing-box 按进程识别并分配出口 | 第 4 段 |
| `kmod-netlink-diag` | 同上，netlink 侧 | 第 4 段 |
| `kmod-tun` | TUN 出站 / tun2socks | 第 5 段 |

每个 `configs/*.config` 末尾新增的 **第 26 段**把这 6 个再显式 `=y` 一遍做保底
（同值重复，`make defconfig` 会自动去重），以后改动第 4/5 段时别把它们删掉。

**不做的事**：iptables 通路的 `ipset` / `iptables-zz-legacy` / 6 个 `kmod-ipt-*`
不预置——固件是 `firewall4` + `dnsmasq-full(nftset)`，pw2 会自己选 nft 通路，
装 iptables 栈纯属白占体积（也因为本分支基调是「全 nft，不引 iptables」）。

后装时除 kmod 外的非内核依赖（`tcping` / `geoview` / `chinadns-ng` / `lyaml` /
`luci-lib-jsonc` / `ip-full` / `unzip` / `v2ray-geoip` / `v2ray-geosite`）从源装即可，
SourceForge 的 `openwrt-passwall-build` 三个目录（`passwall2` / `passwall_luci` /
`passwall_packages`）里都有，架构目录选 `aarch64_cortex-a53`。

---

## 六、怎么用这个分支

1. Fork 后把默认分支切到 `add-proxy-apps`，或在 Actions 页面左上角手动选择该分支
2. 跑 `Build PonWrt`：
   - `soc` / `profile` 按机型选
   - `private_repo` **保持默认 `none`**
   - `scope=firmware` 出固件
3. 首次编译建议先跑 `Warm Cache` 预热工具链，否则 350 分钟大概率不够

### 编出来的固件里有什么

| 类别 | 内容 |
|---|---|
| 系统 | ImmortalWrt（ponwrt）+ LuCI + 中文（`zh_Hans`） |
| 主题 | Fluent 2（`luci-theme-fluent`） |
| 状态页 | `luci-app-airoha-npu`（NPU/CPU/Frame Engine/PPE）、`luci-app-pon-status`（PON 光模块）、`luci-app-natmode`（NAT 类型） |
| 代理 | `luci-app-homeproxy` + `sing-box` 1.14.3（homeproxy 唯一核心，**不带 xray / 不带 v2ray-geodata**） |
| 组网 | `luci-app-zerotier` + `zerotier` 1.16.2 |
| 远程 | `luci-app-frpc` |
| AC 管理 | `luci-app-gecoosac`（仅 `h3c_hm2004-du`） |
| ~~FTTR~~ | ~~已关闭~~ |

---

## 七、同步上游时注意

本分支的自有改动全部是**新增**或**默认值调整**，不涉及结构重写。同步上游的推荐做法：

```sh
git checkout -b tmp upstream/main     # 以上游最新为基线
# 按「语义清单」重新打补丁，而不是 rebase 自有提交
```

不要 `git rebase`——历史里混了多次中途 merge 上游的提交，rebase 必然大面积冲突。

**已放弃的历史改动**（上游已自带或架构冲突，不要再搬回来）：

| 旧改动 | 现状 |
|---|---|
| `configs/common-apps.config`（公共配置集中注入） | 上游无此机制，内容已直接落到 14 个机型 config |
| `host-toolchain.yml` + `scripts/host-toolchain.sh` | 上游已删除该套，改用 `prewarm` + `prebuilt_host` |
| `scripts/pwrt-cache.sh` 自建缓存 / `-early` 双缓存 / `cache-rollover` job | 上游 `pwrt-cache.sh` 实现更完整 |
| `create-github-app-token@v1`（`app-id`） | 上游已用 `@v3`（`client-id`），更正确 |
