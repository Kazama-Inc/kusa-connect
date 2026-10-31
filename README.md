# kusa-connect

让 [Kusa](https://kusa.pics) 的智能体在你自己电脑的指定目录里读写文件、执行命令。智能体（模型）仍在线上，这台电脑只执行它发来的操作。

本仓库只放 `kusa-connect` 的安装脚本与发布包（GitHub Releases）。

*English: `kusa-connect` lets a Kusa agent read, write and run commands in folders you choose on your own Mac or Linux machine. The model stays in the cloud; your computer only executes the operations it sends, after you confirm them. This repository hosts the installer and release binaries.*

## 安装

macOS 与 Linux（amd64、arm64）：

```bash
curl -fsSL https://raw.githubusercontent.com/Kazama-Inc/kusa-connect/main/install.sh | sh
```

装到 `~/.local/bin/kusa-connect`。脚本会核对发布包的 SHA256。可选环境变量：

| 变量 | 作用 |
|---|---|
| `KUSA_CONNECT_VERSION` | 装指定版本（如 `0.1.0`），不给时装最新版 |
| `KUSA_CONNECT_INSTALL_DIR` | 装到别的目录 |

也可以在 [Releases](https://github.com/Kazama-Inc/kusa-connect/releases) 手动下载对应平台的 `tar.gz`，用 `SHA256SUMS` 核对后解压。

## 使用

1. 在 Kusa 网页的「新建工作区」里选「电脑上的文件夹」，打开方式选「用 kusa-connect 连接」，复制给出的命令。
2. 在电脑上运行它，把最后的目录换成你要开放的目录（可以给多个）：

   ```bash
   kusa-connect --server https://… --token kc_… ~/my-project
   ```

   第一次之后服务端地址与令牌记在 `~/.kusa/connect.json`（权限 0600），之后只要 `kusa-connect ~/my-project`。
3. 按 Ctrl+C 断开。`kusa-connect logout` 删掉本机存的令牌；要让令牌在服务端也失效，在网页的工作区管理里撤销这台电脑。

`kusa-connect --help` 看全部参数。

## 安全

- **只开放你给的目录。** 目录之外的路径（包括经符号链接绕出去的）一律拒绝。
- **改动和命令在这台电脑上确认。** 缺省写文件与执行命令都要在终端里按 `y` 允许，`n 理由` 拒绝（理由会原文告诉智能体），`a` 在这次连接里对同一操作不再问。
- **确认方式可以锁定。** 用 `--accept ask|ask-all|ask-exec|web` 启动时锁定，网页上改不了；不锁定时网页可以改严，改松要在这台电脑上同意一次。
- **不下发密钥，不上传环境变量。** 子进程只继承 `PATH`、`HOME`、`LANG` 等少数几个变量，名字像密钥的一律不继承。
- 只通过 https 连服务端；断开时停掉还在跑的命令。

## 卸载

```bash
rm ~/.local/bin/kusa-connect ~/.kusa/connect.json
```

## 源码与许可

`kusa-connect` 由 Kusa 的 SDK 编译（`cmd/kusa-connect`），源码暂未公开。许可条款待定。

## 本仓库的测试

```bash
python3 -m unittest discover -s test
```
