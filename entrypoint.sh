#!/bin/bash

NODE_DIR="/home/container/node"
BUN_DIR="/usr/local/bun"
GO_DIR="/usr/local/go"

export HOME="/home/container"
export PLAYWRIGHT_BROWSERS_PATH="/usr/local/share/playwright"

mkdir -p "$NODE_DIR"
export PATH="$NODE_DIR/bin:$BUN_DIR/bin:$GO_DIR/bin:$PATH"

cat > /home/container/.bashrc <<EOF
export PATH="$NODE_DIR/bin:$BUN_DIR/bin:$GO_DIR/bin:\$PATH"
export NODE_PATH="$NODE_DIR/lib/node_modules"
export PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_PATH"
EOF

# ==========================================================
# Node.js runtime
# ==========================================================
if [ -n "${NODE_VERSION}" ]; then
    if [ -x "$NODE_DIR/bin/node" ]; then
        CURRENT_VER="$("$NODE_DIR/bin/node" -v 2>/dev/null || true)"
    else
        CURRENT_VER="none"
    fi

    TARGET_VER="$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | jq -r --arg prefix "v${NODE_VERSION}" '.[] | select(.version | startswith($prefix)) | .version' | head -n 1)"

    if [ -z "$TARGET_VER" ] || [ "$TARGET_VER" = "null" ]; then
        if [[ "${NODE_VERSION}" == v* ]]; then
            TARGET_VER="${NODE_VERSION}"
        else
            TARGET_VER="v${NODE_VERSION}.0.0"
        fi
    fi

    if [ "$CURRENT_VER" != "$TARGET_VER" ]; then
        echo "[Runtime] Installing Node.js $TARGET_VER ..."
        rm -rf "$NODE_DIR"/*
        cd /tmp || exit 1

        if curl -fL "https://nodejs.org/dist/${TARGET_VER}/node-${TARGET_VER}-linux-x64.tar.gz" -o node.tar.gz; then
            tar -xf node.tar.gz --strip-components=1 -C "$NODE_DIR"
            rm -f node.tar.gz

            # Do not force npm@latest: newer npm majors can require newer Node.
            "$NODE_DIR/bin/npm" install -g pm2 pnpm yarn playwright --loglevel=error || true
        else
            echo "[Runtime] Failed to download Node.js $TARGET_VER."
        fi

        cd /home/container || exit 1
    fi
fi

# ==========================================================
# GitHub auto update on every Pterodactyl start/restart
# ==========================================================
cd /home/container || exit 1
git config --global --add safe.directory /home/container >/dev/null 2>&1 || true

echo "----------------------------------------------------------"
echo "                   GITHUB AUTO UPDATE"
echo "----------------------------------------------------------"

if [ "${AUTO_UPDATE:-1}" = "1" ]; then
    if [ -d "/home/container/.git" ]; then
        BRANCH_NAME="${BRANCH:-main}"
        OLD_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
        BEFORE_DEPS="$(cat package.json package-lock.json pnpm-lock.yaml yarn.lock 2>/dev/null | sha256sum | awk '{print $1}')"

        echo "[Git] Branch       : $BRANCH_NAME"
        echo "[Git] Commit lama  : $OLD_COMMIT"
        echo "[Git] Fetch origin/$BRANCH_NAME ..."

        rm -f .git/index.lock

        if git fetch --force --prune origin "$BRANCH_NAME"; then
            if git reset --hard "origin/$BRANCH_NAME"; then
                NEW_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
                AFTER_DEPS="$(cat package.json package-lock.json pnpm-lock.yaml yarn.lock 2>/dev/null | sha256sum | awk '{print $1}')"

                if [ "$OLD_COMMIT" = "$NEW_COMMIT" ]; then
                    echo "[Git] Sudah versi terbaru ($NEW_COMMIT)"
                else
                    echo "[Git] UPDATE BERHASIL: $OLD_COMMIT -> $NEW_COMMIT"
                fi

                if [ "${AUTO_INSTALL_DEPS:-1}" = "1" ] && [ -f package.json ] && { [ ! -d node_modules ] || [ "$BEFORE_DEPS" != "$AFTER_DEPS" ]; }; then
                    echo "[Deps] package/lock berubah. Installing dependencies..."

                    if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
                        pnpm install || echo "[Deps] pnpm install gagal."
                    elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
                        yarn install || echo "[Deps] yarn install gagal."
                    else
                        npm install || echo "[Deps] npm install gagal."
                    fi
                fi
            else
                echo "[Git] ERROR: git reset gagal."
            fi
        else
            echo "[Git] ERROR: git fetch gagal. File lokal tetap digunakan."
        fi
    else
        echo "[Git] .git tidak ditemukan di /home/container."
        echo "[Git] Auto update dilewati."
    fi
else
    echo "[Git] AUTO_UPDATE nonaktif."
fi

echo "----------------------------------------------------------"

# ==========================================================
# Cloudflare Tunnel
# ==========================================================
if [[ "${ENABLE_CF_TUNNEL}" == "true" ]] || [[ "${ENABLE_CF_TUNNEL}" == "1" ]]; then
    if [ -n "${CF_TOKEN}" ]; then
        pkill -f cloudflared 2>/dev/null || true
        nohup cloudflared tunnel run --token "${CF_TOKEN}" > /home/container/.cloudflared.log 2>&1 &
    fi
fi

clear
echo "----------------------------------------------------------"
echo "                       QOUPAY                             "
echo "----------------------------------------------------------"
echo "Location   : $(curl -s ipinfo.io/country 2>/dev/null || echo 'Unknown')"
echo "OS         : $(grep -oP '(?<=^PRETTY_NAME=).+' /etc/os-release | tr -d '\"')"
echo "CPU        : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //') ($(grep -c '^processor' /proc/cpuinfo) Cores)"
echo "Uptime     : $(uptime -p | sed 's/up //')"
echo ""
echo "RAM Usage  : $(free -m | awk '/Mem:/ {print $3" MB / "$2" MB"}')"
echo "Disk Usage : $(df -h / | awk 'NR==2 {print $3" / "$2" ("$5")"}')"
echo "----------------------------------------------------------"
echo "                     RUNTIME VERSIONS                     "
echo "----------------------------------------------------------"
echo "Node.js    : $(node -v 2>/dev/null || echo 'Not Installed')"
echo "Bun        : v$(bun -v 2>/dev/null || echo 'Not Installed')"
echo "Golang     : v$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo 'Not Installed')"
echo "Python     : v$(python3 --version 2>/dev/null | awk '{print $2}' || echo 'Not Installed')"
echo "Playwright : $(playwright --version 2>/dev/null | head -n 1 || echo 'Not Installed')"
echo "----------------------------------------------------------"

exec /bin/bash
