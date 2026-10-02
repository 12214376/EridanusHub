#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Eridanus & SnowLuma 一键自动化环境部署脚本 (Termux 专属)
# 支持在 Android 设备上快速部署 Ubuntu 24.04/22.04 + Node 22 + Linux QQ + Python 3.11
# ==============================================================================

# set -e (disabled to allow robust execution and graceful fallbacks)

echo "=========================================================="
echo "      🚀 Eridanus & SnowLuma Termux 宿主自动化部署      "
echo "=========================================================="

# 1. 开启外部应用调用权限 (支持 Eridanus App 隐式起停控制)
echo "[1/5] 配置 Termux 外部应用控制权限..."
mkdir -p ~/.termux
if [ -f ~/.termux/termux.properties ]; then
    sed -i '/allow-external-apps/d' ~/.termux/termux.properties
fi
echo "allow-external-apps = true" >> ~/.termux/termux.properties
echo "✓ allow-external-apps 已启用"

# 2. 检查 Termux 基础包
echo "[2/5] 检查 Termux 宿主组件..."
if ! command -v proot-distro >/dev/null 2>&1; then
    echo "正在安装 proot-distro..."
    pkg install -y proot-distro 2>/dev/null || apt-get install -y proot-distro 2>/dev/null || true
else
    echo "✓ proot-distro 已就绪，跳过宿主包更新"
fi

# 3. 安装 Ubuntu 用户态
echo "[3/5] 准备 Ubuntu Linux 容器环境..."
if proot-distro login ubuntu -- echo "ok" >/dev/null 2>&1 || [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ]; then
    echo "✓ 检测到已安装 Ubuntu 容器，直接复用"
else
    echo "正在拉取并安装 Ubuntu 根文件系统..."
    proot-distro install ubuntu || true
fi

# 4. 在 Ubuntu 容器内部配置所需依赖
echo "[4/5] 进入 Ubuntu 容器并配置 Node / Python / Linux QQ / Xvfb 环境..."

cat << 'UBUNTU_ENV_EOF' | proot-distro login ubuntu -- bash
set -e
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

echo "-> [Ubuntu] 配置北京时间时区 (Asia/Shanghai)..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
echo "Asia/Shanghai" > /etc/timezone 2>/dev/null || true
echo "export TZ=Asia/Shanghai" >> /root/.bashrc 2>/dev/null || true
echo "export TZ=Asia/Shanghai" >> /etc/profile 2>/dev/null || true
export TZ=Asia/Shanghai

echo "-> [Ubuntu] 更新软件源并安装基础系统依赖..."
apt-get update -y || true
apt-get install -y software-properties-common curl wget git build-essential \
    xvfb fluxbox x11vnc novnc websockify redis-server \
    python3 python3-pip python3-venv python3-dev \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libcairo2-dev pkg-config python3-cairo libglib2.0-0 \
    libasound2 libasound2t64 libgtk-3-0 fonts-noto-cjk libcap2-bin || true

# 准备 noVNC 首页软链接
ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html 2>/dev/null || true

# 安装 Node.js 22 LTS
if ! command -v node >/dev/null 2>&1; then
    echo "-> [Ubuntu] 安装 Node.js 22 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - || true
    apt-get install -y nodejs || true
fi
echo "✓ Node 版本: $(node -v 2>/dev/null || echo '未就绪')"
echo "✓ Python 版本: $(python3 --version 2>/dev/null || echo '未就绪')"

# 赋予 Node ptrace 能力
setcap cap_sys_ptrace=ep "$(readlink -f "$(which node)")" 2>/dev/null || true

# 冻结 QQ 热更新 (防止补丁破坏 Hook)
if ! grep -q "qqpatch.gtimg.cn" /etc/hosts 2>/dev/null; then
    echo "0.0.0.0 qqpatch.gtimg.cn" >> /etc/hosts
fi

# 下载 Linux QQ arm64
mkdir -p /root/qq_installer
cd /root/qq_installer
if [ ! -f /root/qq_installer/linuxqq.deb ]; then
    echo "-> [Ubuntu] 下载官方 Linux QQ (ARM64)..."
    wget -q --show-progress -O linuxqq.deb "https://qqdl.gtimg.cn/qqfile/QQNT/9.9.36/beta/9ee04bef/linuxqq_3.2.34-53644_arm64.deb" || true
    if [ -f linuxqq.deb ]; then
        dpkg -i linuxqq.deb || apt-get install -fy || true
    fi
fi

# 部署 SnowLuma
mkdir -p /root/snowluma
cd /root/snowluma
if [ ! -f /root/snowluma/index.mjs ]; then
    echo "-> [Ubuntu] 下载 SnowLuma 核心 (ARM64 Lite)..."
    SL_URL=$(curl -s "https://api.github.com/repos/SnowLuma/SnowLuma/releases/latest" | grep -o "https://[^\" ]*linux-arm64-lite\.tar\.gz" | head -n 1)
    if [ -z "$SL_URL" ]; then
        SL_URL="https://github.com/SnowLuma/SnowLuma/releases/download/v1.14.20/SnowLuma-v1.14.20-linux-arm64-lite.tar.gz"
    fi
    wget -q --show-progress -O snowluma.tar.gz "$SL_URL" 2>/dev/null || wget -q -O snowluma.tar.gz "https://ghproxy.net/$SL_URL" 2>/dev/null || true
    if [ -f snowluma.tar.gz ]; then
        tar -xzf snowluma.tar.gz --strip-components=1 2>/dev/null || tar -xzf snowluma.tar.gz 2>/dev/null || true
        rm -f snowluma.tar.gz
    fi
fi

# 部署 NapCatQQ (无头 NTQQ 协议端)
mkdir -p /root/napcat
if [ ! -f /root/napcat/napcat.mjs ] && [ ! -f /root/napcat/loadNapCat.js ]; then
    echo "-> [Ubuntu] 下载 NapCatQQ (Linux ARM64)..."
    NC_URL="https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.linux.arm64.zip"
    wget -q --show-progress -O /tmp/napcat.zip "$NC_URL" 2>/dev/null || wget -q -O /tmp/napcat.zip "https://ghproxy.net/$NC_URL" 2>/dev/null || wget -q -O /tmp/napcat.zip "https://github.com/NapNeko/NapCatQQ/releases/download/v4.4.55/NapCat.linux.arm64.zip" || true
    if [ -f /tmp/napcat.zip ]; then
        unzip -q -o /tmp/napcat.zip -d /root/napcat || true
        rm -f /tmp/napcat.zip
    fi
fi
mkdir -p /root/napcat/config
if [ ! -f /root/napcat/config/webui.json ]; then
    cat << EOF_NC > /root/napcat/config/webui.json
{
  "host": "0.0.0.0",
  "port": 6099,
  "token": "124982318dfe",
  "loginRate": 3
}
EOF_NC
fi

# 部署 LuckyLilliaBot (极简独立无头 OneBot 端)
mkdir -p /root/llonebot
if [ ! -f /root/llonebot/llbot ] && [ ! -f /root/llonebot/package.json ]; then
    echo "-> [Ubuntu] 下载 LuckyLilliaBot (Linux ARM64)..."
    LL_URL=$(curl -s "https://api.github.com/repos/LLOneBot/LuckyLilliaBot/releases/latest" | grep -o "https://[^\" ]*linux-arm64[^\" ]*\.tar\.gz" | head -n 1)
    [ -z "$LL_URL" ] && LL_URL="https://github.com/LLOneBot/LuckyLilliaBot/releases/download/v4.2.1/LLBot-Linux-arm64.tar.gz"
    wget -q --show-progress -O /tmp/llbot.tar.gz "$LL_URL" 2>/dev/null || wget -q -O /tmp/llbot.tar.gz "https://ghproxy.net/$LL_URL" 2>/dev/null || true
    if [ -f /tmp/llbot.tar.gz ]; then
        tar -xzf /tmp/llbot.tar.gz -C /root/llonebot 2>/dev/null || true
        rm -f /tmp/llbot.tar.gz
    fi
fi

# 部署 Eridanus
mkdir -p /root/eridanus
cd /root/eridanus
if [ ! -f /root/eridanus/main.py ]; then
    echo "-> [Ubuntu] 拉取 Eridanus 源码..."
    git clone https://github.com/12214376/Eridanus.git /root/eridanus 2>/dev/null || git clone https://ghproxy.net/https://github.com/12214376/Eridanus.git /root/eridanus || true
fi

if [ -f /root/eridanus/requirements.txt ]; then
    echo "-> [Ubuntu] 准备 Python 虚拟环境与依赖..."
    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "")
    if [ -n "$PY_VER" ]; then
        apt-get install -y "python${PY_VER}-venv" || true
    fi
    apt-get install -y python3-venv python3-full python3-pip python3-setuptools python3-wheel || true
    
    rm -rf /root/eridanus/venv
    
    # 尝试标准创建 venv
    if ! python3 -m venv /root/eridanus/venv 2>/dev/null; then
        echo "-> 提示: ensurepip 缺失，采用 --without-pip 模式创建虚拟环境并注入 pip..."
        python3 -m venv --without-pip /root/eridanus/venv || true
        if [ -f /root/eridanus/venv/bin/python3 ]; then
            curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py || true
            if [ -f /tmp/get-pip.py ]; then
                /root/eridanus/venv/bin/python3 /tmp/get-pip.py || true
                rm -f /tmp/get-pip.py
            fi
        fi
    fi
    
    # 检查并安装依赖
    PIP_BIN=""
    if [ -f /root/eridanus/venv/bin/pip ]; then
        PIP_BIN="/root/eridanus/venv/bin/pip"
    elif [ -f /root/eridanus/venv/bin/pip3 ]; then
        PIP_BIN="/root/eridanus/venv/bin/pip3"
    fi

    if [ -n "$PIP_BIN" ]; then
        echo "-> [Ubuntu] 在虚拟环境中安装 Eridanus 依赖..."
        "$PIP_BIN" install --upgrade pip -i https://pypi.tuna.tsinghua.edu.cn/simple || true
        "$PIP_BIN" install audioop-lts wheel setuptools flask-sock -i https://pypi.tuna.tsinghua.edu.cn/simple || true
        "$PIP_BIN" install -r /root/eridanus/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple || true
    elif command -v pip3 >/dev/null 2>&1; then
        echo "-> [Ubuntu] 在全局环境中安装 Eridanus 依赖..."
        pip3 install --break-system-packages audioop-lts wheel setuptools flask-sock -i https://pypi.tuna.tsinghua.edu.cn/simple || true
        pip3 install --break-system-packages --ignore-installed -r /root/eridanus/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple || true
    fi
fi

echo "✓ 容器内部环境配置完毕！"
UBUNTU_ENV_EOF

echo "✓ Ubuntu 容器环境配置完成！"

# 5. 安装本地控制脚本
echo "[5/5] 安装宿主控制脚本 ~/bot_service.sh..."

SCRIPT_URL="https://raw.githubusercontent.com/12214376/EridanusHub/main/scripts/bot_service.sh"
echo "正在从 GitHub 获取最新控制脚本: $SCRIPT_URL ..."
curl -fsSL "$SCRIPT_URL" -o ~/bot_service.sh 2>/dev/null || curl -fsSL "https://ghproxy.net/$SCRIPT_URL" -o ~/bot_service.sh 2>/dev/null || curl -fsSL "https://raw.githubusercontent.com/12214376/Eridanus/master/scripts/bot_service.sh" -o ~/bot_service.sh 2>/dev/null || true

# 检查本地是否有可读的离线备份作为降级兜底 (杜绝 Permission denied 报错)
if [ ! -s ~/bot_service.sh ] && [ -r /sdcard/Download/bot_service.sh ]; then
    cp /sdcard/Download/bot_service.sh ~/bot_service.sh 2>/dev/null || true
fi

# 若文件无效或包含 404，写入内置兜底脚本
if [ ! -f ~/bot_service.sh ] || [ ! -s ~/bot_service.sh ] || grep -q "404:" ~/bot_service.sh; then
    cat << "EOF" > ~/bot_service.sh
#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Eridanus & SnowLuma Service Controller for Termux
# 运行在 Termux 宿主或 Ubuntu 容器内部，调度与管理各项 Bot 服务
# ==============================================================================

export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PREFIX="/data/data/com.termux/files/usr"
export HOME="/data/data/com.termux/files/home"

ACTION="$1"
UBUNTU_DIR="/data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu"
[ ! -d "$UBUNTU_DIR" ] && UBUNTU_DIR="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu"

# 检测当前是否已在 PRoot Ubuntu 容器内运行
if [ "$(id -u)" -eq 0 ] || ! command -v proot-distro >/dev/null 2>&1; then
    IS_CONTAINER=1
else
    IS_CONTAINER=0
fi

# 全局时区设置 (北京时间 UTC+8)
export TZ='Asia/Shanghai'

sync_timezone() {
    export TZ='Asia/Shanghai'
    if [ "$IS_CONTAINER" -eq 1 ]; then
        if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
            ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
            echo "Asia/Shanghai" > /etc/timezone 2>/dev/null || true
        fi
    else
        if [ -f "$UBUNTU_DIR/rootfs/usr/share/zoneinfo/Asia/Shanghai" ]; then
            ln -sf /usr/share/zoneinfo/Asia/Shanghai "$UBUNTU_DIR/rootfs/etc/localtime" 2>/dev/null || true
            echo "Asia/Shanghai" > "$UBUNTU_DIR/rootfs/etc/timezone" 2>/dev/null || true
        fi
        proot-distro login ubuntu -- bash -c "
            export TZ=Asia/Shanghai
            [ -f /usr/share/zoneinfo/Asia/Shanghai ] && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
            echo 'Asia/Shanghai' > /etc/timezone 2>/dev/null || true
            if ! grep -q 'TZ=Asia/Shanghai' /root/.bashrc 2>/dev/null; then
                echo 'export TZ=Asia/Shanghai' >> /root/.bashrc 2>/dev/null || true
            fi
        " 2>/dev/null || true
    fi
}

is_port_listening() {
    local port=$1
    timeout 0.5 bash -c "(echo > /dev/tcp/127.0.0.1/$port)" 2>/dev/null
}

start_snowluma() {
    echo "[Hub] 正在启动 SnowLuma 服务栈 (含 noVNC 扫码环境)..."
    sync_timezone
    stop_snowluma >/dev/null 2>&1 || true
    sleep 1

    if [ "$IS_CONTAINER" -eq 1 ]; then
        export DISPLAY=:1
        export HOME=/root
        export TZ=Asia/Shanghai
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
        
        rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1 /tmp/.X*-lock
        nohup Xvfb :1 -screen 0 1024x768x16 -nolisten tcp >/tmp/xvfb.log 2>&1 &
        sleep 1
        nohup fluxbox >/dev/null 2>&1 &
        nohup x11vnc -display :1 -rfbport 5900 -nopw -listen 127.0.0.1 -forever -noshm >/tmp/x11vnc.log 2>&1 &
        sleep 1
        nohup websockify --web /usr/share/novnc --libserver 6081 127.0.0.1:5900 >/tmp/websockify.log 2>&1 &
        if [ -d /root/snowluma ]; then
            (cd /root/snowluma && nohup node index.mjs > /root/snowluma.log 2>&1 &)
        fi
        if [ -f /opt/QQ/qq ]; then
            nohup /opt/QQ/qq --no-sandbox >/tmp/qq.log 2>&1 &
        fi
    else
        nohup proot-distro login ubuntu -- bash -c '
            export DISPLAY=:1
            export HOME=/root
            export TZ=Asia/Shanghai
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
            
            rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1 /tmp/.X*-lock
            Xvfb :1 -screen 0 1024x768x16 -nolisten tcp >/tmp/xvfb.log 2>&1 &
            sleep 1
            fluxbox >/dev/null 2>&1 &
            x11vnc -display :1 -rfbport 5900 -nopw -listen 127.0.0.1 -forever -noshm >/tmp/x11vnc.log 2>&1 &
            sleep 1
            websockify --web /usr/share/novnc --libserver 6081 127.0.0.1:5900 >/tmp/websockify.log 2>&1 &
            
            if [ -f /opt/QQ/qq ]; then
                nohup /opt/QQ/qq --no-sandbox >/tmp/qq.log 2>&1 &
            fi

            if [ -d /root/snowluma ]; then
                cd /root/snowluma && exec node index.mjs > /root/snowluma.log 2>&1
            else
                wait
            fi
        ' > /data/data/com.termux/files/home/snowluma_daemon.log 2>&1 &
    fi
    echo "[Hub] SnowLuma 与 noVNC 启动命令已下发。"
}

stop_snowluma() {
    echo "[Hub] 正在停止 SnowLuma、Linux QQ 及 noVNC 服务栈..."
    pkill -9 -f '[s]nowluma_daemon' 2>/dev/null || true
    pkill -9 -f '[s]nowluma/index.mjs' 2>/dev/null || true
    pkill -9 -f 'node [i]ndex.mjs' 2>/dev/null || true
    pkill -9 -f '[w]ebsockify' 2>/dev/null || true
    pkill -9 -f '[x]11vnc' 2>/dev/null || true
    pkill -9 -f '[f]luxbox' 2>/dev/null || true
    pkill -9 -f '[X]vfb :1' 2>/dev/null || true
    pkill -9 -x qq 2>/dev/null || true
    pkill -9 -f "/opt/QQ" 2>/dev/null || true
    fuser -k -9 6081/tcp 2>/dev/null || true
    fuser -k -9 5900/tcp 2>/dev/null || true
    fuser -k -9 5099/tcp 2>/dev/null || true

    if [ "$IS_CONTAINER" -eq 1 ]; then
        rm -rf /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true
    else
        rm -rf "$UBUNTU_DIR/rootfs/tmp/.X"* 2>/dev/null || true
        proot-distro login ubuntu -- bash -c "
            pkill -9 -f '[s]nowluma/index.mjs' 2>/dev/null || true
            pkill -9 -f 'node [i]ndex.mjs' 2>/dev/null || true
            pkill -9 -f '[w]ebsockify' 2>/dev/null || true
            pkill -9 -f '[x]11vnc' 2>/dev/null || true
            pkill -9 -f '[f]luxbox' 2>/dev/null || true
            pkill -9 -f '[X]vfb' 2>/dev/null || true
            pkill -9 -x qq 2>/dev/null || true
            pkill -9 -f '/opt/QQ' 2>/dev/null || true
            fuser -k -9 6081/tcp 2>/dev/null || true
            fuser -k -9 5900/tcp 2>/dev/null || true
            fuser -k -9 5099/tcp 2>/dev/null || true
            rm -rf /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true
        " 2>/dev/null || true
    fi
    echo "[Hub] SnowLuma 与 noVNC 服务栈已彻底终止。"
}

start_napcat() {
    echo "[Hub] 正在启动 NapCatQQ (无头 Headless 模式)..."
    sync_timezone
    stop_napcat >/dev/null 2>&1 || true
    stop_llonebot >/dev/null 2>&1 || true
    stop_snowluma >/dev/null 2>&1 || true
    sleep 1

    local START_CMD='
        export HOME=/root
        export TZ=Asia/Shanghai
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
        
        # 0. 确保 WebUI token 存在且固定为 124982318dfe
        if [ -f /root/napcat/config/webui.json ]; then
            sed -i "s/\"token\": \".*\"/\"token\": \"124982318dfe\"/" /root/napcat/config/webui.json 2>/dev/null || true
        fi

        # 1. 备份原版 package.json 并挂载 NapCat 注入脚本
        if [ -f /opt/QQ/resources/app/package.json ] && [ ! -f /opt/QQ/resources/app/package.json.orig ]; then
            cp /opt/QQ/resources/app/package.json /opt/QQ/resources/app/package.json.orig 2>/dev/null || true
        fi
        [ -d /root/napcat ] && ln -sfn /root/napcat /opt/QQ/resources/app/napcat 2>/dev/null || true
        [ -f /root/napcat/loadNapCat.js ] && cp -f /root/napcat/loadNapCat.js /opt/QQ/resources/app/loadNapCat.js 2>/dev/null || true
        if [ -f /opt/QQ/resources/app/package.json ]; then
            sed -i "s/\"main\": \".*\"/\"main\": \".\/loadNapCat.js\"/" /opt/QQ/resources/app/package.json 2>/dev/null || true
        fi

        # 2. 软链接 resources 目录避免路径歧义
        [ -d /opt/QQ/resources ] && ln -sf /opt/QQ/resources /usr/bin/resources 2>/dev/null || true

        # 3. 启动无头 QQ（xvfb 1x1 虚拟屏幕，免桌面/免 VNC/极低功耗，直接通过 WebUI 6099 扫码配置）
        exec xvfb-run -a /opt/QQ/qq --no-sandbox -q > /root/napcat.log 2>&1
    '

    if [ "$IS_CONTAINER" -eq 1 ]; then
        eval "$START_CMD" &
    else
        nohup proot-distro login ubuntu -- bash -c "$START_CMD" > /data/data/com.termux/files/home/napcat_daemon.log 2>&1 &
    fi
    echo "[Hub] NapCatQQ (无头) 启动指令已下发，请在 App 打开控制端 (WebUI 6099) 扫码登录。"
}

stop_napcat() {
    echo "[Hub] 正在停止 NapCatQQ 服务..."
    fuser -k -9 6099/tcp 2>/dev/null || true
    fuser -k -9 3001/tcp 2>/dev/null || true
    pkill -9 -f '[n]apcat_daemon' 2>/dev/null || true

    local STOP_CMD='
        # 1. 彻底杀死 QQ 及其全部衍生子进程 (含 node.mojom.NodeService, crashpad, zygote)
        pkill -9 -f "/opt/QQ" 2>/dev/null || true
        pkill -9 -x qq 2>/dev/null || true
        # 2. 彻底杀死 xvfb 虚拟显示与 Xvfb
        pkill -9 -f "xvfb-run.*qq" 2>/dev/null || true
        pkill -9 -f "Xvfb.*auth" 2>/dev/null || true
        # 3. 彻底杀死残留的 NapCat Node 进程
        pkill -9 -f "napcat" 2>/dev/null || true
        pkill -9 -f "loadNapCat" 2>/dev/null || true
        # 4. 彻底强制释放 6099 及 3001 端口
        fuser -k -9 6099/tcp 2>/dev/null || true
        fuser -k -9 3001/tcp 2>/dev/null || true
        # 5. 还原原版 package.json 避免污染
        if [ -f /opt/QQ/resources/app/package.json.orig ]; then
            cp -f /opt/QQ/resources/app/package.json.orig /opt/QQ/resources/app/package.json 2>/dev/null || true
        fi
    '
    if [ "$IS_CONTAINER" -eq 1 ]; then
        eval "$STOP_CMD"
    else
        proot-distro login ubuntu -- bash -c "$STOP_CMD" 2>/dev/null || true
    fi
    fuser -k -9 6099/tcp 2>/dev/null || true
    fuser -k -9 3001/tcp 2>/dev/null || true
    echo "[Hub] NapCatQQ 服务已彻底终止并释放端口。"
}

start_llonebot() {
    echo "[Hub] 正在启动 LuckyLilliaBot (无头 Headless 模式)..."
    sync_timezone
    stop_llonebot >/dev/null 2>&1 || true
    stop_napcat >/dev/null 2>&1 || true
    stop_snowluma >/dev/null 2>&1 || true
    sleep 1

    local START_CMD='
        export HOME=/root
        export TZ=Asia/Shanghai
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
        
        # 优先使用 LuckyLilliaBot 独立 CLI
        if [ -f /root/llonebot/llbot ]; then
            chmod +x /root/llonebot/llbot
            cd /root/llonebot && exec ./llbot > /root/llonebot.log 2>&1
        elif [ -f /root/llonebot/LLBot-CLI* ]; then
            chmod +x /root/llonebot/LLBot-CLI*
            cd /root/llonebot && exec ./LLBot-CLI* > /root/llonebot.log 2>&1
        elif [ -f /root/llonebot/main.js ]; then
            cd /root/llonebot && exec node main.js > /root/llonebot.log 2>&1
        elif [ -f /root/llonebot/index.js ]; then
            cd /root/llonebot && exec node index.js > /root/llonebot.log 2>&1
        elif [ -f /opt/QQ/qq ]; then
            exec xvfb-run -a /opt/QQ/qq --no-sandbox > /root/llonebot.log 2>&1
        fi
    '

    if [ "$IS_CONTAINER" -eq 1 ]; then
        eval "$START_CMD" &
    else
        nohup proot-distro login ubuntu -- bash -c "$START_CMD" > /data/data/com.termux/files/home/llonebot_daemon.log 2>&1 &
    fi
    echo "[Hub] LuckyLilliaBot (无头) 启动指令已下发，请在 App 打开控制端 (WebUI 3080) 扫码登录。"
}

stop_llonebot() {
    echo "[Hub] 正在停止 LuckyLilliaBot 服务..."
    fuser -k -9 3080/tcp 2>/dev/null || true
    fuser -k -9 3001/tcp 2>/dev/null || true
    fuser -k -9 5088/tcp 2>/dev/null || true
    pkill -9 -f '[l]lonebot_daemon' 2>/dev/null || true

    local STOP_CMD='
        pkill -9 -f "/root/llonebot" 2>/dev/null || true
        pkill -9 -f "[l]lbot" 2>/dev/null || true
        pkill -9 -f "[L]LBot-CLI" 2>/dev/null || true
        pkill -9 -f "llbot.js" 2>/dev/null || true
        pkill -9 -f "node.*[l]lonebot" 2>/dev/null || true
        pkill -9 -f "node.*[L]uckyLillia" 2>/dev/null || true
        fuser -k -9 3080/tcp 2>/dev/null || true
        fuser -k -9 3001/tcp 2>/dev/null || true
        fuser -k -9 5088/tcp 2>/dev/null || true
    '
    if [ "$IS_CONTAINER" -eq 1 ]; then
        eval "$STOP_CMD"
    else
        proot-distro login ubuntu -- bash -c "$STOP_CMD" 2>/dev/null || true
    fi
    fuser -k -9 3080/tcp 2>/dev/null || true
    fuser -k -9 3001/tcp 2>/dev/null || true
    fuser -k -9 5088/tcp 2>/dev/null || true
    echo "[Hub] LuckyLilliaBot 服务已彻底终止并释放端口。"
}

start_eridanus() {
    echo "[Hub] 正在启动 Eridanus 智能体核心服务栈..."
    sync_timezone
    stop_eridanus >/dev/null 2>&1 || true
    sleep 1

    if [ "$IS_CONTAINER" -eq 1 ]; then
        export HOME=/root
        export TZ=Asia/Shanghai
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
        if command -v redis-server >/dev/null 2>&1; then
            redis-server --daemonize yes 2>/dev/null || true
        fi
        if [ -d /root/eridanus ]; then
            PY_CMD=python3
            [ -f /root/eridanus/venv/bin/python3 ] && PY_CMD=/root/eridanus/venv/bin/python3
            (cd /root/eridanus && nohup $PY_CMD main.py > /root/eridanus.log 2>&1 &)
        fi
    else
        nohup proot-distro login ubuntu -- bash -c '
            export HOME=/root
            export TZ=Asia/Shanghai
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
            if command -v redis-server >/dev/null 2>&1; then
                redis-server --daemonize yes 2>/dev/null || true
            fi
            if [ -d /root/eridanus ]; then
                PY_CMD=python3
                [ -f /root/eridanus/venv/bin/python3 ] && PY_CMD=/root/eridanus/venv/bin/python3
                cd /root/eridanus && exec $PY_CMD main.py > /root/eridanus.log 2>&1
            fi
        ' > /data/data/com.termux/files/home/eridanus_daemon.log 2>&1 &
    fi
    echo "[Hub] Eridanus 启动命令已下发。"
}

stop_eridanus() {
    echo "[Hub] 正在停止 Eridanus 核心服务..."
    pkill -9 -f 'eridanus_daemon' 2>/dev/null || true
    pkill -9 -f 'eridanus/main.py' 2>/dev/null || true
    pkill -9 -f 'python.*main.py' 2>/dev/null || true
    pkill -9 -f 'redis-server' 2>/dev/null || true

    if [ "$IS_CONTAINER" -eq 0 ]; then
        proot-distro login ubuntu -- bash -c "
            pkill -9 -f 'eridanus/main.py' 2>/dev/null || true
            pkill -9 -f 'main.py' 2>/dev/null || true
            pkill -9 -f 'redis-server' 2>/dev/null || true
        " 2>/dev/null || true
    fi
    echo "[Hub] Eridanus 核心服务已停止。"
}

start_services() {
    echo "[Hub] 正在一键启动全部后台服务..."
    start_snowluma
    sleep 2
    start_eridanus
    echo "[Hub] 全部启动命令已下发，请在 App 查看端口状态。"
}

stop_services() {
    echo "[Hub] 正在一键停止全部后台服务..."
    stop_snowluma
    stop_napcat
    stop_llonebot
    stop_eridanus
    pkill -9 -f 'bot_daemon' 2>/dev/null || true
    echo "[Hub] 所有服务已全部停止。"
}

case "$ACTION" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        stop_services
        sleep 2
        start_services
        ;;
    start_snowluma)
        start_snowluma
        ;;
    stop_snowluma)
        stop_snowluma
        ;;
    start_napcat)
        start_napcat
        ;;
    stop_napcat)
        stop_napcat
        ;;
    start_llonebot)
        start_llonebot
        ;;
    stop_llonebot)
        stop_llonebot
        ;;
    start_eridanus)
        start_eridanus
        ;;
    stop_eridanus)
        stop_eridanus
        ;;
    sync_time|timezone)
        sync_timezone
        echo "[Hub] 时区已同步为北京时间: $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S %Z')"
        ;;
    status)
        echo "=== 系统时间 (北京时间 CST) ==="
        echo "  当前时间: $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "=== 端口活性 ==="
        for port in 6099 3080 5088 5099 3001 6081 5007; do
            if is_port_listening $port; then
                echo "  ✓ 端口 $port: 正在监听 (ACTIVE)"
            else
                echo "  ✗ 端口 $port: 未监听 (INACTIVE)"
            fi
        done
        echo "=== 进程状态 ==="
        if [ "$IS_CONTAINER" -eq 1 ]; then
            ps aux | grep -E 'node|python3|Xvfb|x11vnc|websockify|qq|napcat|llonebot' | grep -v grep || true
        else
            proot-distro login ubuntu -- bash -c "
                ps aux | grep -E 'node|python3|Xvfb|x11vnc|websockify|qq|napcat|llonebot' | grep -v grep
            " 2>/dev/null || true
        fi
        ;;
    *)
        echo "Usage: bot_service.sh {start|stop|restart|status|start_napcat|stop_napcat|start_llonebot|stop_llonebot|start_snowluma|stop_snowluma|start_eridanus|stop_eridanus}"
        exit 1
        ;;
esac

EOF
fi

chmod +x ~/bot_service.sh
mkdir -p "$UBUNTU_DIR/rootfs/root" 2>/dev/null || true
cp -f ~/bot_service.sh "$UBUNTU_DIR/rootfs/root/bot_service.sh" 2>/dev/null || true
echo "✓ bot_service.sh 控制脚本部署完成"

# 立即同步一次北京时间
bash ~/bot_service.sh sync_time 2>/dev/null || true

echo "=========================================================="
echo "  🎉 Eridanus 环境自动化配置完成！"
echo "  当前系统时间: $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S %Z')"
echo "  您可以直接返回 Eridanus App 点击 [启动全部] 开始使用。"
echo "=========================================================="
