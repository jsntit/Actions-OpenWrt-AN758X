# `add-proxy-apps` 分支说明

本分支 = **上游主线（`qwe-qaq/Actions-OpenWrt-AN758X` 的 `main`）+ 代理插件链 + 自用定制**。

`main` 分支与上游**完全一致**（无任何自有改动），所有定制只落在本分支。

- 基线提交：`1bdb291`（= 上游 `main`）
- 与 `main` 的差异：**16 个文件，+452 / −19**

---

## 一、和 `main` 的差异一览

| 文件 | 变更 | 一句话说明 |
|---|---|---|
| `configs/*.config`（13 个机型） | +20 ×13 | 统一补 `kmod-nft-queue` / `libstdcpp` / `kmod-dummy` |
| `configs/h3c_hm2004-du.config` | +63 / −19 | 同上三项 + `frpc` / `gecoosac`，并**关闭 FTTR 下行** |
| `diy-part1.sh` | +37 / −1 | 新增 `ADD_GECOOSAC`；`ADD_FLUENT=true`；`ADD_FTTR` 默认 false |
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

### 2. `h3c_hm2004-du.config` 额外加两个插件

```kconfig
CONFIG_PACKAGE_luci-app-frpc=y
CONFIG_PACKAGE_luci-i18n-frpc-zh-cn=y
CONFIG_PACKAGE_luci-app-gecoosac=y
CONFIG_PACKAGE_luci-i18n-gecoosac-zh-cn=y
CONFIG_PACKAGE_gecoosac=y
```

- **frpc**：来自 immortalwrt 的 luci feed，只需勾选。
- **gecoosac**（集客 AC 控制器）：来自第三方仓库 `laipeng668/luci-app-gecoosac`，由 `diy-part1.sh` 拉取。后端 `gecoosac` 通过 `PROVIDES:=gecoosac-files gecoosac-common` 满足前端的全部依赖，不需要额外包，也不会和官方 feeds 冲突。

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
| `ADD_GECOOSAC` | 无此项 | **新增，`true`** | 集客 AC 控制器 |
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
3. **进 `REQUIRED` 校验**：`ADD_GECOOSAC=true` 时把 `luci-app-gecoosac` 加进必装清单，索引里查不到就报错，不会静默编出一个没界面的固件。

---

## 四、`build-ponwrt.yml` 改动（4 处）

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

## 五、怎么用这个分支

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
| 代理 | `kmod-nft-queue` + `libstdcpp` 已内置，`ssr-plus` / `homeproxy` 等可直接从源安装 |
| 远程 | `luci-app-frpc` |
| AC 管理 | `luci-app-gecoosac`（仅 `h3c_hm2004-du`） |
| ~~FTTR~~ | ~~已关闭~~ |

---

## 六、同步上游时注意

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
