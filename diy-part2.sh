#!/bin/bash
# ================================================================
# diy-part2.sh —— 默认值定制（在 .config 加载之后运行，cwd = ponwrt 根）
#   1) 时区 Asia/Shanghai (CST-8)
#   1b) 默认 LAN 地址 10.0.0.1
#   1c) failsafe / 预启动网络同步到 10.0.0.1
#   2) 5G WiFi：CN / auto / HE160
#   3) 概览页 CPU 行：USR/SYS + 每核明细
#   4) 固件版本追加作者与构建时间
# ================================================================

set -euo pipefail

echo "=========================================="
echo "默认值定制：时区 + LAN IP + 5G WiFi (diy-part2.sh)"
echo "=========================================="

# =============================================================
# 可配置：5G 无线参数
# 如需改动，直接改这里即可（编译期常量，会写进 uci-defaults 脚本）
# =============================================================
WIFI_5G_COUNTRY="${WIFI_5G_COUNTRY:-CN}"       # 国家代码（CN = 中国）
WIFI_5G_CHANNEL="${WIFI_5G_CHANNEL:-auto}"     # 信道（auto = 自动选择）
WIFI_5G_HTMODE="${WIFI_5G_HTMODE:-HE160}"      # 160MHz（WiFi6）；回落 HE80
WIFI_5G_FALLBACK="${WIFI_5G_FALLBACK:-HE80}"   # 硬件不支持 160MHz 时的回落值

# 默认 LAN 地址（编译期常量，会写进 config_generate 与 uci-defaults 脚本）
# 想换网段就改这里，两处会同步生效；failsafe 的预启动网络也跟这个走。
LAN_IP="${LAN_IP:-10.0.0.1}"
LAN_NETMASK="${LAN_NETMASK:-255.255.255.0}"
LAN_BROADCAST="${LAN_BROADCAST:-10.0.0.255}"

# 可由 workflow 的 fw_author 输入项覆盖（经 env 注入）；本地单独跑时默认 qwe
FW_AUTHOR="${FW_AUTHOR:-qwe}"
FW_BUILD_TIME="${FW_BUILD_TIME:-}"
FW_DESC_SUFFIX="${FW_DESC_SUFFIX:-}"

echo "配置：5G country=$WIFI_5G_COUNTRY channel=$WIFI_5G_CHANNEL htmode=$WIFI_5G_HTMODE fallback=$WIFI_5G_FALLBACK"
echo "配置：FW_AUTHOR=$FW_AUTHOR"

# ---------------------------------------------------------
# 1. 修改 config_generate 的默认值（首次开机生成的 /etc/config/system）
# ---------------------------------------------------------
CFG="package/base-files/files/bin/config_generate"

if [ -f "$CFG" ]; then
  # 兼容 @system[-1]（旧）与 @system[0]（OpenWrt 21+）
  sed -i "s/option timezone.*/option timezone 'CST-8'/" "$CFG"
  sed -i "s/option zonename.*/option zonename 'Asia\/Shanghai'/" "$CFG"
  echo "✅ config_generate 默认时区 -> CST-8 / Asia/Shanghai"
else
  echo "::warning::未找到 $CFG，跳过默认值修改"
fi

# ---------------------------------------------------------
# 1b. 默认 LAN 地址 -> $LAN_IP
#   两层，和下面的时区/无线同一思路：
#   a) 编译期改 config_generate 里的 lan 默认值 —— 全新刷机、恢复出厂都是它。
#      前提是 CONFIG_TARGET_DEFAULT_LAN_IP_FROM_PREINIT 没开；开了的话
#      board.json 的 lan.ipaddr 优先级更高，会盖掉这里（当前基座是 not set）。
#   b) 运行期 uci-defaults 兜底 —— 保留配置升级时 /etc/config/network 已存在，
#      光改 config_generate 不生效，靠脚本改写；但只在地址仍是出厂默认
#      192.168.1.1（或为空）时才动手，用户自己改过的网段不动。
# ---------------------------------------------------------
if [ -f "$CFG" ]; then
  if grep -qF 'lan) ipad=${ipaddr:-"192.168.1.1"} ;;' "$CFG"; then
    sed -i "s|lan) ipad=\${ipaddr:-\"192\.168\.1\.1\"} ;;|lan) ipad=\${ipaddr:-\"$LAN_IP\"} ;;|" "$CFG"
    echo "✅ config_generate 默认 LAN 地址 -> $LAN_IP"
  elif grep -qF "lan) ipad=\${ipaddr:-\"$LAN_IP\"}" "$CFG"; then
    echo "ℹ config_generate 默认 LAN 地址已是 $LAN_IP，跳过"
  else
    echo "::warning::config_generate 里没匹配到预期的 lan 默认地址行，交由 uci-defaults 兜底"
  fi
fi

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/95-lan-ip <<UCEOF
#!/bin/sh
# 默认 LAN 地址：$LAN_IP
# 由 diy-part2.sh 生成（编译期常量注入）
# 只在仍是出厂默认 192.168.1.1 时才改写，用户自己调过的网段保持不动。

LAN_IP='$LAN_IP'
LAN_NETMASK='$LAN_NETMASK'

cur=\$(uci -q get network.lan.ipaddr)

case "\$cur" in
	""|192.168.1.1|192.168.1.1/*|192.168.1.1/*/*)
		# config_generate 写的是 list ipaddr 'x.x.x.x/24'，先删再设，
		# 保证变成单独 option，netmask 由下面这行给出
		uci -q delete network.lan.ipaddr
		uci -q set network.lan.proto='static'
		uci -q set network.lan.ipaddr="\$LAN_IP"
		uci -q set network.lan.netmask="\$LAN_NETMASK"
		uci -q commit network
		logger -t 95-lan-ip "默认 LAN 地址 \$cur -> \$LAN_IP"
		;;
	*)
		logger -t 95-lan-ip "LAN 已是 \$cur，保留自定义地址"
		;;
esac

exit 0
UCEOF
chmod +x files/etc/uci-defaults/95-lan-ip
echo "✅ uci-defaults LAN 地址脚本已写入：$LAN_IP/$LAN_NETMASK"

# ---------------------------------------------------------
# 1c. failsafe / 预启动网络同步到 $LAN_IP
#   进 failsafe 时用的是 pi_ip（写进 /lib/preinit/00_preinit.conf），
#   它的值来自 CONFIG_TARGET_PREINIT_IP，只有该符号为空才回落
#   base-files/Makefile 里硬编码的 192.168.1.1。所以两处都要改，
#   否则 LAN 换成 10.0.0.x 后进 failsafe 还得把电脑换回 192.168.1.x。
#
#   时机：本脚本在步骤 9 的 `make defconfig` 之前跑（workflow 顺序如此）。
#   注意：只写 .config 不够 —— 见下面 image-config.in 那段说明，没有可见
#   prompt 的符号会被 defconfig 按 default 重算，所以三层都要改。
# ---------------------------------------------------------
BF_MK="package/base-files/Makefile"
if [ -f "$BF_MK" ]; then
  sed -i "/pi_ip=/s|\"192\.168\.1\.1\"|\"$LAN_IP\"|" "$BF_MK"
  sed -i "/pi_broadcast=/s|\"192\.168\.1\.255\"|\"$LAN_BROADCAST\"|" "$BF_MK"
  # 这一段在 ifeq CONFIG_TARGET_DEFAULT_LAN_IP_FROM_PREINIT,y 里，当前没开；
  # 但万一哪天开了，board.json 的 lan.ipaddr 优先级更高，这里不改就会把
  # config_generate 的改动盖掉（见 1b 的说明）。
  sed -i "/json_add_string ipaddr/s|\"192\.168\.1\.1\"|\"$LAN_IP\"|" "$BF_MK"
  echo "✅ Makefile 里 pi_ip / pi_broadcast / 99-lan-ip 的默认值 -> $LAN_IP / $LAN_BROADCAST"
else
  echo "::warning::未找到 $BF_MK，跳过 preinit 兜底默认值修改"
fi

if [ -f .config ]; then
  # 先删掉旧的两种写法（含 is not set），再追加，避免 kconfig 报重复赋值
  sed -i '/^CONFIG_TARGET_PREINIT_IP=/d; /^# CONFIG_TARGET_PREINIT_IP is not set/d' .config
  echo "CONFIG_TARGET_PREINIT_IP=\"$LAN_IP\"" >> .config
  sed -i '/^CONFIG_TARGET_PREINIT_BROADCAST=/d; /^# CONFIG_TARGET_PREINIT_BROADCAST is not set/d' .config
  echo "CONFIG_TARGET_PREINIT_BROADCAST=\"$LAN_BROADCAST\"" >> .config
  echo "✅ .config 里 preinit 网络 -> $LAN_IP / $LAN_BROADCAST（failsafe 同网段）"
fi

# Kconfig 侧（决定性的一层）：TARGET_PREINIT_IP / _BROADCAST 的 prompt 是
# `if PREINITOPT`，而基座里 PREINITOPT 是关的 —— 没有可见 prompt 的符号，
# `make defconfig` 会按 default 重算，上面写进 .config 的值会被直接丢掉。
# 所以 default 本身也得改；.config 那两行留着无害（该符号可写时会优先）。
IMG_IN="package/base-files/image-config.in"
if [ -f "$IMG_IN" ]; then
  sed -i "/^config TARGET_PREINIT_IP\$/,/^config /s|^\([[:space:]]*default[[:space:]]*\)\"192\.168\.1\.1\"|\1\"$LAN_IP\"|" "$IMG_IN"
  sed -i "/^config TARGET_PREINIT_BROADCAST\$/,/^config /s|^\([[:space:]]*default[[:space:]]*\)\"192\.168\.1\.255\"|\1\"$LAN_BROADCAST\"|" "$IMG_IN"
  echo "✅ image-config.in 里 preinit 的 Kconfig 默认值 -> $LAN_IP / $LAN_BROADCAST"
else
  echo "::warning::未找到 $IMG_IN，preinit 默认值只有 .config 一层，可能被 defconfig 覆盖"
fi

# ---------------------------------------------------------
# 2. uci-defaults：即使保留了旧配置也强制刷成中国时区
# ---------------------------------------------------------
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-timezone-cn <<'EOF'
#!/bin/sh
uci -q batch <<'UCI'
set system.@system[0].zonename='Asia/Shanghai'
set system.@system[0].timezone='CST-8'
commit system
UCI
exit 0
EOF
chmod +x files/etc/uci-defaults/99-timezone-cn
echo "✅ uci-defaults 时区脚本已写入"

# ---------------------------------------------------------
# 3. 补上亚洲时区数据库包（LuCI 显示与时区切换需要）
# ---------------------------------------------------------
if [ -f .config ]; then
  sed -i '/^CONFIG_PACKAGE_zoneinfo-asia=/d; /^# CONFIG_PACKAGE_zoneinfo-asia is not set/d' .config
  echo "CONFIG_PACKAGE_zoneinfo-asia=y    # 亚洲时区数据库（中国时区需要）" >> .config
  echo "✅ zoneinfo-asia 已加入 .config"

  # libffi：见 diy-part1.sh 的同名段落。源码树原本没有这个包，
  # python3(3.14) 的 _ctypes 却必须要它的 ffi.h / libffi.pc，
  # 缺了就 fatal error 拖垮 world。这里显式打开 target 版，
  # 让 Build/InstallDev 把头文件装进 staging_dir。
  sed -i '/^CONFIG_PACKAGE_libffi=/d; /^# CONFIG_PACKAGE_libffi is not set/d' .config
  echo "CONFIG_PACKAGE_libffi=y           # python3 _ctypes 需要 ffi.h / libffi.pc" >> .config
  echo "✅ libffi 已加入 .config"
fi

# ---------------------------------------------------------
# 4. 5G WiFi：CN / auto / HE160
#   分两层：编译期改 detect 脚本默认值（best effort，各版本路径不同）；
#   运行期用 uci-defaults 首启强制刷（主要手段，保留配置升级也生效，且自带
#   「wireless 尚未生成就先 wifi config」的逻辑）。
# ---------------------------------------------------------

# ---- 4a. 编译期：改 detect 脚本默认值（best effort） ----
DETECT_SCRIPT=""
for cand in \
  "package/kernel/mac80211/files/lib/wifi/mac80211.sh" \
  "package/kernel/mac80211/files/lib/wifi/mac80211.uc" \
  "package/network/services/hostapd/files/lib/wifi/mac80211.sh"; do
  [ -f "$cand" ] && { DETECT_SCRIPT="$cand"; break; }
done

if [ -n "$DETECT_SCRIPT" ]; then
  # 5G（11a / band 5g）的默认信道改成 auto
  sed -i "s/option channel '36'/option channel 'auto'/g" "$DETECT_SCRIPT"
  sed -i "s/option channel='36'/option channel='auto'/g" "$DETECT_SCRIPT"
  echo "✅ detect 脚本默认信道 -> auto ($DETECT_SCRIPT)"
else
  echo "::warning::未找到无线 detect 脚本，跳过编译期默认值修改（由 uci-defaults 兜底）"
fi

# ---- 4b. 运行期：uci-defaults 首启强制刷 ----
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/96-wifi-5g-cn <<UCEOF
#!/bin/sh
# 5G WiFi 默认值：国家码 CN、信道 auto、频宽 160MHz
# 由 diy-part2.sh 生成（编译期常量注入）

COUNTRY='$WIFI_5G_COUNTRY'
CHANNEL='$WIFI_5G_CHANNEL'
HTMODE='$WIFI_5G_HTMODE'
FALLBACK='$WIFI_5G_FALLBACK'

log() { logger -t wifi-5g "\$@"; }

# uci-defaults 可能在 wifi config 之前执行 —— 没生成就先生成
if [ ! -f /etc/config/wireless ]; then
	command -v wifi >/dev/null 2>&1 && wifi config >/dev/null 2>&1
fi
[ -f /etc/config/wireless ] || { log "未找到 /etc/config/wireless，跳过"; exit 0; }

# 检测该 phy 是否支持 160MHz（兼容 "160 MHz" 与 "80+80 MHz" 两种表述）
support_160() {
	local phy="\$1"
	[ -z "\$phy" ] && return 1
	command -v iw >/dev/null 2>&1 || return 1
	iw phy "\$phy" info 2>/dev/null | grep -qE '160 MHz|80\+80 MHz' || return 1
	return 0
}

changed=0
for dev in \$(uci -q show wireless | sed -n 's/^wireless\.\([A-Za-z0-9_-]*\)=wifi-device\$/\1/p'); do
	band="\$(uci -q get wireless.\$dev.band 2>/dev/null)"
	hwmode="\$(uci -q get wireless.\$dev.hwmode 2>/dev/null)"

	# 只处理 5G：新版用 band='5g'，旧版用 hwmode='11a'
	is5g=0
	[ "\$band" = "5g" ] && is5g=1
	[ -z "\$band" ] && [ "\$hwmode" = "11a" ] && is5g=1
	[ "\$is5g" = "0" ] && continue

	# 频宽：确认不支持 160MHz 才回落
	# 取不到 phy 名时不检测（保持 HTMODE）—— 避免无 phy 选项的 radio 被误判回落
	ht="\$HTMODE"
	phy="\$(uci -q get wireless.\$dev.phy 2>/dev/null)"
	if [ -n "\$phy" ] && ! support_160 "\$phy"; then
		ht="\$FALLBACK"
		log "\$dev：未检测到 160MHz 能力，回落为 \$ht"
	fi

	uci -q set wireless.\$dev.country="\$COUNTRY"
	uci -q set wireless.\$dev.country_ie='1'
	uci -q set wireless.\$dev.channel="\$CHANNEL"
	uci -q set wireless.\$dev.htmode="\$ht"

	log "\$dev：country=\$COUNTRY channel=\$CHANNEL htmode=\$ht"
	changed=1
done

if [ "\$changed" = "1" ]; then
	uci -q commit wireless
	# 重载而非重启：避免首启期间无线中断后不可恢复
	command -v wifi >/dev/null 2>&1 && wifi reload >/dev/null 2>&1 || true
	log "已提交 wireless 配置"
else
	log "未找到 5G radio，未做任何修改"
fi

exit 0
UCEOF
chmod +x files/etc/uci-defaults/96-wifi-5g-cn
echo "✅ uci-defaults 5G WiFi 脚本已写入（country=$WIFI_5G_COUNTRY channel=$WIFI_5G_CHANNEL htmode=$WIFI_5G_HTMODE）"

# ---- 4c. 确保 hostapd 支持 160MHz / 11ax ----
# wpad-openssl = 完整版 hostapd，支持 HE160；
# 若用的是 wpad-basic / hostapd-basic（精简版），160MHz 可能不生效。
if [ -f .config ]; then
  if grep -qE "^CONFIG_PACKAGE_(wpad-basic|hostapd-basic)=y" .config; then
    echo "::warning::检测到精简版 wpad/hostapd-basic，160MHz 可能不支持"
  fi
  # 无线工具：uci-defaults 里的能力检测需要 iw
  if ! grep -q "^CONFIG_PACKAGE_iw=y" .config; then
    sed -i '/^CONFIG_PACKAGE_iw=/d; /^# CONFIG_PACKAGE_iw is not set/d' .config
    echo "CONFIG_PACKAGE_iw=y                       # 无线命令行工具（160MHz 能力检测需要）" >> .config
    echo "✅ iw 已加入 .config"
  fi
fi

# ---------------------------------------------------------
# 5. 概览页「CPU 使用率（%）」行：USR/SYS + 每核明细
#   luci 原本是 popen("top -n1 | awk ...") 的单值。这里只把它改指到
#   files/sbin/cpuusage，前端 10_system.js 与 ACL 都不动。
#   纯显示层：找不到目标只 warning，不让它把几小时的构建搞挂。
# ---------------------------------------------------------
PATCH_CPUUSAGE="$(dirname "$0")/scripts/patch-luci-cpuusage.sh"
if [ -f "$PATCH_CPUUSAGE" ]; then
  PONWRT_DIR=. bash "$PATCH_CPUUSAGE" || true
else
  echo "::warning::未找到 $PATCH_CPUUSAGE，跳过概览页 CPU 使用率行定制"
fi

[ -z "$FW_BUILD_TIME" ] && FW_BUILD_TIME="$(TZ="${TZ:-Asia/Shanghai}" date '+%Y-%m-%d %H:%M')"

VER_CODE="$(sed -n 's/^CONFIG_VERSION_CODE="\(.*\)"$/\1/p' .config 2>/dev/null || true)"
if [ -n "$VER_CODE" ]; then
  DESC_BODY='%D %V %C'
else
  DESC_BODY='%D %V'
fi
[ -z "$FW_DESC_SUFFIX" ] && FW_DESC_SUFFIX="· ${FW_AUTHOR} · ${FW_BUILD_TIME}"

RELEASE_TPL="package/base-files/files/etc/openwrt_release"
OSREL_TPL="package/base-files/files/usr/lib/os-release"

# 用 perl + 环境变量传替换文本：作者名/后缀里带 / | # & 都不会搞坏语法
# （直接 sed "s|...|${FW_DESC_SUFFIX}|" 遇到这些字符会炸）
FW_DESC_LINE="DISTRIB_DESCRIPTION='${DESC_BODY} ${FW_DESC_SUFFIX}'"
OSREL_LINE="OPENWRT_RELEASE=\"${DESC_BODY} ${FW_DESC_SUFFIX}\""
export FW_DESC_LINE OSREL_LINE

if [ -f "$RELEASE_TPL" ]; then
  # 只替换 DISTRIB_DESCRIPTION 行，不动 DISTRIB_ID / DISTRIB_RELEASE 等其它行
  perl -i -pe 's/^DISTRIB_DESCRIPTION=.*/$ENV{FW_DESC_LINE}/' "$RELEASE_TPL"
  echo "✅ 固件版本模板 -> $FW_DESC_LINE"
else
  echo "::warning::未找到 $RELEASE_TPL，固件版本不会带构建信息"
fi

# os-release 同步（部分工具/LuCI 版本读它；%B 只是 SOURCE_DATE_EPOCH 时间戳，不好看）
if [ -f "$OSREL_TPL" ]; then
  perl -i -pe 's/^OPENWRT_RELEASE=.*/$ENV{OSREL_LINE}/' "$OSREL_TPL"
  echo "✅ os-release 同步 -> $OSREL_LINE"
fi

# 用 -f 不要用 -x：git checkout / Windows 打包会丢可执行位，-x 判失败会静默整段跳过。
# 末尾 || true：本文件开头是 set -euo pipefail，被 source 的子脚本里任何一步
# 返回非 0 都会让这里当场退出，后面的步骤全不执行且整轮构建中断。
# 加密是可选增强，不该有能力搞挂构建。
[ -f scripts/diy-part2-crypto.sh ] && . ./scripts/diy-part2-crypto.sh || true

echo "🎉 diy-part2.sh 执行完毕 (author=$FW_AUTHOR)"
