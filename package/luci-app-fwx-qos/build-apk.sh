#!/bin/sh
#
# 独立把 luci-app-fwx-qos 打成可安装的 .apk (apk v3 / ADB 格式)
#
# 不需要完整的 OpenWrt 构建环境：包里只有 Lua/HTML/Shell，没有需要编译的代码。
# 需要 apk-tools v3 的 apk 二进制（Alpine 的 apk-tools-static 即可）：
#
#   https://dl-cdn.alpinelinux.org/alpine/v3.23/main/x86_64/apk-tools-static-3.0.9-r0.apk
#   tar xzf apk-tools-static-*.apk -C apktools   # 得到 apktools/sbin/apk.static
#
# 用法：
#   APK=/path/to/apk.static ./build-apk.sh [输出目录]
#
set -e

PKG="luci-app-fwx-qos"
VERSION="1.0-r2"
PKGARCH="noarch"
LICENSE="MIT"
DESCRIPTION="FanchmWrt per-device bandwidth limit (nftables limit)"
ORIGIN="package/luci-app-fwx-qos"
MAINTAINER="fanchmwrt contributors"

here="$(cd "$(dirname "$0")" && pwd)"
files="$here/files"
outdir="${1:-$here}"

APK="${APK:-}"
if [ -z "$APK" ]; then
	for cand in /tmp/apktools/sbin/apk.static "$(command -v apk.static 2>/dev/null)" "$(command -v apk 2>/dev/null)"; do
		[ -n "$cand" ] && [ -x "$cand" ] && APK="$cand" && break
	done
fi
if [ -z "$APK" ] || [ ! -x "$APK" ]; then
	echo "找不到 apk v3 可执行文件，请用 APK=/path/to/apk.static 指定" >&2
	exit 1
fi

build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
idir="$build/root"

mkdir -p "$idir/usr/lib/lua/luci/controller" \
	 "$idir/usr/lib/lua/luci/view/fwx_qos" \
	 "$idir/usr/sbin" \
	 "$idir/etc/init.d" \
	 "$idir/etc/config" \
	 "$idir/usr/share/luci/menu.d" \
	 "$idir/usr/share/rpcd/acl.d" \
	 "$idir/lib/apk/packages"

install -m 0644 "$files/fwx_qos.lua" "$idir/usr/lib/lua/luci/controller/fwx_qos.lua"
install -m 0644 "$files/qos.htm" "$idir/usr/lib/lua/luci/view/fwx_qos/qos.htm"
install -m 0755 "$files/fwx-qos-gen" "$idir/usr/sbin/fwx-qos-gen"
install -m 0755 "$files/fwx-qos.init" "$idir/etc/init.d/fwx-qos"
install -m 0644 "$files/fwx_qos.config" "$idir/etc/config/fwx_qos"
install -m 0644 "$files/luci-app-fwx-qos.json" "$idir/usr/share/luci/menu.d/luci-app-fwx-qos.json"
install -m 0644 "$files/rpcd-acl.json" "$idir/usr/share/rpcd/acl.d/luci-app-fwx-qos.json"

# 安装文件清单（不含 apk 自身的元数据目录）
( cd "$idir" && find . -type f -not -path './lib/apk/*' -printf '/%P\n' | sort ) \
	> "$idir/lib/apk/packages/$PKG.list"

# conffiles：/etc/config/fwx_qos 由用户保留
echo "/etc/config/fwx_qos" > "$idir/lib/apk/packages/$PKG.conffiles"
( cd "$idir" && sha256sum etc/config/fwx_qos | awk '{print "/etc/config/fwx_qos " $1}' ) \
	> "$idir/lib/apk/packages/$PKG.conffiles_static"

out="$outdir/$PKG-$VERSION.apk"
rm -f "$out"
mkdir -p "$outdir"

"$APK" mkpkg \
	--info "name:$PKG" \
	--info "version:$VERSION" \
	--info "description:$DESCRIPTION" \
	--info "arch:$PKGARCH" \
	--info "license:$LICENSE" \
	--info "origin:$ORIGIN" \
	--info "maintainer:$MAINTAINER" \
	--info "depends:luci-base" \
	--info "provides:$PKG-any" \
	--script "post-install:$files/post-install" \
	--files "$idir" \
	--output "$out"

echo "已生成: $out"
"$APK" adbdump "$out" | head -20
