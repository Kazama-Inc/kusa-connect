#!/bin/sh
# kusa-connect installer: downloads the release package for this platform, verifies its SHA256,
# and installs it to ~/.local/bin (or KUSA_CONNECT_INSTALL_DIR).
#
#   curl -fsSL https://raw.githubusercontent.com/Kazama-Inc/kusa-connect/main/install.sh | sh
#
# Environment:
#   KUSA_CONNECT_VERSION      version to install (e.g. 0.1.0); latest when unset
#   KUSA_CONNECT_INSTALL_DIR  install directory; ~/.local/bin when unset
#   KUSA_CONNECT_RELEASES     release base URL; https://github.com/Kazama-Inc/kusa-connect/releases when unset (for tests)
#
# Variables are always written as ${name}: macOS /bin/sh (bash 3.2) in a UTF-8 locale treats
# non-ASCII bytes right after $name as part of the variable name.
set -eu

releases="${KUSA_CONNECT_RELEASES:-https://github.com/Kazama-Inc/kusa-connect/releases}"
install_dir="${KUSA_CONNECT_INSTALL_DIR:-${HOME}/.local/bin}"
version="${KUSA_CONNECT_VERSION:-}"

say() { printf '%s\n' "$*"; }
fail() { printf 'kusa-connect install failed: %s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail "only macOS and Linux are supported (this machine: $(uname -s))" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) fail "only amd64 and arm64 are supported (this machine: $(uname -m))" ;;
esac
# A terminal running under Rosetta on Apple silicon reports x86_64: install the native arm64 build.
if [ "${os}" = darwin ] && [ "${arch}" = amd64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
  arch=arm64
fi

if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL -o "$2" "$1"; }
  final_url() { curl -fsSLI -o /dev/null -w '%{url_effective}' "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -q -O "$2" "$1"; }
  final_url() { wget -q -S --spider "$1" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tail -n 1 | tr -d '\r'; }
else
  fail "curl or wget is required"
fi

if [ -z "${version}" ]; then
  # releases/latest redirects to releases/tag/v<version>
  tag="$(final_url "${releases}/latest")" || fail "couldn't find the latest version (${releases}/latest)"
  version="${tag##*/v}"
  [ -n "${version}" ] && [ "${version}" != "${tag}" ] || fail "couldn't find the latest version (${releases}/latest redirected to ${tag})"
fi
version="${version#v}"

name="kusa-connect_${version}_${os}_${arch}.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT INT TERM

say "Downloading kusa-connect ${version} (${os}/${arch})..."
fetch "${releases}/download/v${version}/${name}" "${tmp}/${name}" || fail "couldn't download ${name}"
fetch "${releases}/download/v${version}/SHA256SUMS" "${tmp}/SHA256SUMS" || fail "couldn't download SHA256SUMS"

want="$(awk -v n="${name}" '$2 == n { print $1 }' "${tmp}/SHA256SUMS")"
[ -n "${want}" ] || fail "SHA256SUMS has no entry for ${name}"
if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "${tmp}/${name}" | awk '{ print $1 }')"
elif command -v shasum >/dev/null 2>&1; then
  got="$(shasum -a 256 "${tmp}/${name}" | awk '{ print $1 }')"
else
  fail "sha256sum or shasum is required to verify the download"
fi
[ "${got}" = "${want}" ] || fail "SHA256 mismatch for ${name} (the download is incomplete or was tampered with)"

tar -C "${tmp}" -xzf "${tmp}/${name}" kusa-connect
mkdir -p "${install_dir}"
mv "${tmp}/kusa-connect" "${install_dir}/kusa-connect"
chmod 755 "${install_dir}/kusa-connect"

say "Installed ${install_dir}/kusa-connect ($("${install_dir}/kusa-connect" --version))"
case ":${PATH}:" in
  *":${install_dir}:"*) ;;
  *) say "Note: ${install_dir} is not on your PATH. Add this line to ~/.zshrc or ~/.bashrc, then open a new terminal:
  export PATH=\"${install_dir}:\$PATH\"" ;;
esac
say "Next, go back to the web page and run the command it gives you under \"Connect with kusa-connect\"."
