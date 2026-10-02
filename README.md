# EridanusHub

Eridanus & QQ Bot (SnowLuma / NapCat / LuckyLillia) Android Termux 一键自动化部署与运维套件。

## 🚀 手机端 Termux 一键部署命令

在手机 Termux 中复制并执行以下命令即可全自动完成配置：

```bash
curl -fsSL https://raw.githubusercontent.com/12214376/EridanusHub/main/scripts/deploy_termux.sh -o ~/setup.sh 2>/dev/null || curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/12214376/EridanusHub/main/scripts/deploy_termux.sh -o ~/setup.sh 2>/dev/null; bash ~/setup.sh
```

## 📦 项目组成
- `scripts/deploy_termux.sh`: 宿主与 PRoot Ubuntu 容器自动化安装配置脚本（Node 22、Python 3.11、Linux QQ、noVNC 等）。
- `scripts/bot_service.sh`: 容器内服务管理、端口检测、一键启停与更新工具。
- `app/`: Eridanus Android 协同客户端（测试通过后同步推送到此仓库）。
