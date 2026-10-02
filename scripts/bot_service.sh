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

eridanus_tool() {
    local SUB_ACTION="$1"
    [ -z "$SUB_ACTION" ] && SUB_ACTION="update_code"
    echo "[Hub] 正在执行 Eridanus 维护与工具任务: $SUB_ACTION..."

    local CMD='
        export HOME=/root
        export TZ=Asia/Shanghai
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
        cd /root/eridanus || exit 1
        
        PY_CMD=python3
        [ -f /root/eridanus/venv/bin/python3 ] && PY_CMD=/root/eridanus/venv/bin/python3
        PIP_CMD=pip3
        [ -f /root/eridanus/venv/bin/pip ] && PIP_CMD=/root/eridanus/venv/bin/pip
        
        case "'"$SUB_ACTION"'" in
            update_code|update|2)
                echo "-> [1/2] 正在拉取 Eridanus 最新核心代码..."
                git pull origin master 2>/dev/null || git pull https://github.com/12214376/Eridanus.git || git pull || true
                echo "-> [2/2] 正在检查并更新依赖清单..."
                if [ -f requirements.txt ]; then
                    $PIP_CMD install --upgrade -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple || true
                fi
                echo "✓ Eridanus 代码与核心依赖更新完成！"
                ;;
            install_playwright|playwright|3)
                echo "-> 正在安装 Playwright 工具及 Chromium 内核..."
                $PIP_CMD install playwright -i https://pypi.tuna.tsinghua.edu.cn/simple || true
                $PY_CMD -m playwright install chromium || true
                echo "✓ Playwright 工具安装完成！"
                ;;
            install_ai|ai|5)
                echo "-> 正在安装/更新 AI 检测依赖库 (如奶龙检测)..."
                $PIP_CMD install opencv-python-headless pillow torchvision -i https://pypi.tuna.tsinghua.edu.cn/simple || true
                echo "✓ AI 库安装完成！"
                ;;
            update_jmcomic|jmcomic|9)
                echo "-> 正在升级 jmcomic 库..."
                $PIP_CMD install --upgrade jmcomic -i https://pypi.tuna.tsinghua.edu.cn/simple || true
                echo "✓ jmcomic 库更新完成！"
                ;;
            export_config|7)
                echo "-> 正在备份导出配置文件..."
                mkdir -p /root/eridanus/backup_yamls
                cp -rf config/* /root/eridanus/backup_yamls/ 2>/dev/null || true
                echo "✓ 配置文件已备份至 /root/eridanus/backup_yamls"
                ;;
            import_config|8)
                echo "-> 正在恢复导入配置文件..."
                if [ -d /root/eridanus/backup_yamls ]; then
                    cp -rf /root/eridanus/backup_yamls/* config/ 2>/dev/null || true
                    echo "✓ 配置文件已成功恢复！"
                else
                    echo "✗ 未找到备份配置文件目录 (/root/eridanus/backup_yamls)"
                fi
                ;;
            interactive|tool|run_tool)
                if [ -f tool.py ]; then
                    $PY_CMD tool.py
                else
                    echo "tool.py 未找到，直接执行代码更新"
                    git pull
                fi
                ;;
            *)
                echo "用法: bot_service.sh eridanus_tool {update_code|install_playwright|install_ai|update_jmcomic|export_config|import_config|interactive}"
                ;;
        esac
    '

    if [ "$IS_CONTAINER" -eq 1 ]; then
        eval "$CMD"
    else
        proot-distro login ubuntu -- bash -c "$CMD"
    fi
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
    eridanus_tool|tool|update_eridanus)
        shift
        eridanus_tool "$@"
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
