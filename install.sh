#!/bin/sh
# kusa-connect 安装脚本：下载对应平台的发布包，核对 SHA256，装到 ~/.local/bin（或 KUSA_CONNECT_INSTALL_DIR）。
#
#   curl -fsSL https://raw.githubusercontent.com/Kazama-Inc/kusa-connect/main/install.sh | sh
#
# 环境变量：
#   KUSA_CONNECT_VERSION      要装的版本（如 0.1.0）；不给时装最新版
#   KUSA_CONNECT_INSTALL_DIR  装到哪个目录；不给时 ~/.local/bin
#   KUSA_CONNECT_RELEASES     发布地址；不给时 https://github.com/Kazama-Inc/kusa-connect/releases（测试用）
set -eu

releases="${KUSA_CONNECT_RELEASES:-https://github.com/Kazama-Inc/kusa-connect/releases}"
install_dir="${KUSA_CONNECT_INSTALL_DIR:-$HOME/.local/bin}"
version="${KUSA_CONNECT_VERSION:-}"

say() { printf '%s\n' "$*"; }
fail() { printf 'kusa-connect 安装失败：%s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail "暂只支持 macOS 与 Linux（这台是 $(uname -s)）" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) fail "暂只支持 amd64 与 arm64（这台是 $(uname -m)）" ;;
esac
# 在 Apple 芯片的 Mac 上经 Rosetta 跑的终端里 uname -m 是 x86_64：装原生的 arm64 版
if [ "$os" = darwin ] && [ "$arch" = amd64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
  arch=arm64
fi

if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL -o "$2" "$1"; }
  final_url() { curl -fsSLI -o /dev/null -w '%{url_effective}' "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -q -O "$2" "$1"; }
  final_url() { wget -q -S --spider "$1" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tail -n 1 | tr -d '\r'; }
else
  fail "要有 curl 或 wget"
fi

if [ -z "$version" ]; then
  # releases/latest 跳转到 releases/tag/v<版本>
  tag="$(final_url "$releases/latest")" || fail "查不到最新版本（$releases/latest）"
  version="${tag##*/v}"
  [ -n "$version" ] && [ "$version" != "$tag" ] || fail "查不到最新版本（$releases/latest 跳到了 $tag）"
fi
version="${version#v}"

name="kusa-connect_${version}_${os}_${arch}.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

say "下载 kusa-connect $version（$os/$arch）…"
fetch "$releases/download/v$version/$name" "$tmp/$name" || fail "下载 $name 失败"
fetch "$releases/download/v$version/SHA256SUMS" "$tmp/SHA256SUMS" || fail "下载 SHA256SUMS 失败"

want="$(awk -v n="$name" '$2 == n { print $1 }' "$tmp/SHA256SUMS")"
[ -n "$want" ] || fail "SHA256SUMS 里没有 $name"
if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "$tmp/$name" | awk '{ print $1 }')"
elif command -v shasum >/dev/null 2>&1; then
  got="$(shasum -a 256 "$tmp/$name" | awk '{ print $1 }')"
else
  fail "要有 sha256sum 或 shasum 来核对下载的包"
fi
[ "$got" = "$want" ] || fail "$name 的 SHA256 对不上（下载不完整或被篡改）"

tar -C "$tmp" -xzf "$tmp/$name" kusa-connect
mkdir -p "$install_dir"
mv "$tmp/kusa-connect" "$install_dir/kusa-connect"
chmod 755 "$install_dir/kusa-connect"

say "已装好：$install_dir/kusa-connect（$("$install_dir/kusa-connect" --version)）"
case ":$PATH:" in
  *":$install_dir:"*) ;;
  *) say "提示：$install_dir 不在 PATH 里。把下面这行加进 ~/.zshrc 或 ~/.bashrc，再开一个新终端：
  export PATH=\"$install_dir:\$PATH\"" ;;
esac
say "接下来回到网页，复制「连接我的电脑」给的命令在这里运行。"
