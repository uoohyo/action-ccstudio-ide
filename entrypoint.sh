#!/bin/bash
set -e

# Banner
cat << 'EOF'

 $$$$$$\              $$\     $$\                            $$$$$$\   $$$$$$\   $$$$$$\ $$$$$$$$\ $$\   $$\ $$$$$$$\  $$$$$$\  $$$$$$\        $$$$$$\ $$$$$$$\  $$$$$$$$\
$$  __$$\             $$ |    \__|                          $$  __$$\ $$  __$$\ $$  __$$\\__$$  __|$$ |  $$ |$$  __$$\ \_$$  _|$$  __$$\       \_$$  _|$$  __$$\ $$  _____|
$$ /  $$ | $$$$$$$\ $$$$$$\   $$\  $$$$$$\  $$$$$$$\        $$ /  \__|$$ /  \__|$$ /  \__|  $$ |   $$ |  $$ |$$ |  $$ |  $$ |  $$ /  $$ |        $$ |  $$ |  $$ |$$ |
$$$$$$$$ |$$  _____|\_$$  _|  $$ |$$  __$$\ $$  __$$\       $$ |      $$ |      \$$$$$$\    $$ |   $$ |  $$ |$$ |  $$ |  $$ |  $$ |  $$ |$$$$$$\ $$ |  $$ |  $$ |$$$$$\
$$  __$$ |$$ /        $$ |    $$ |$$ /  $$ |$$ |  $$ |      $$ |      $$ |       \____$$\   $$ |   $$ |  $$ |$$ |  $$ |  $$ |  $$ |  $$ |\______|$$ |  $$ |  $$ |$$  __|
$$ |  $$ |$$ |        $$ |$$\ $$ |$$ |  $$ |$$ |  $$ |      $$ |  $$\ $$ |  $$\ $$\   $$ |  $$ |   $$ |  $$ |$$ |  $$ |  $$ |  $$ |  $$ |        $$ |  $$ |  $$ |$$ |
$$ |  $$ |\$$$$$$$\   \$$$$  |$$ |\$$$$$$  |$$ |  $$ |      \$$$$$$  |\$$$$$$  |\$$$$$$  |  $$ |   \$$$$$$  |$$$$$$$  |$$$$$$\  $$$$$$  |      $$$$$$\ $$$$$$$  |$$$$$$$$\
\__|  \__| \_______|   \____/ \__| \______/ \__|  \__|       \______/  \______/  \______/   \__|    \______/ \_______/ \______| \______/       \______|\_______/ \________|

                                                                                           Texas Instruments CCStudio(tm) for GitHub Actions
                                                                                                                          Creative by Uoohyo
                                                                                                                   https://github.com/uoohyo

EOF

# Parse CCS version from environment variable
# CCS_VERSION format: MAJOR.MINOR.PATCH.BUILD (e.g., 20.5.0.00028)
if [ -z "${CCS_VERSION}" ] || [ "${CCS_VERSION}" = "latest" ]; then
    # Try to detect from pre-extracted installer directory
    if [ -d "/opt/ccs-installer" ]; then
        INSTALLER_DIR=$(find /opt/ccs-installer -maxdepth 1 -type d -name "CCS*" | head -1)
        if [ -n "$INSTALLER_DIR" ]; then
            CCS_VERSION=$(basename "$INSTALLER_DIR" | sed 's/^CCS_\?//' | sed 's/_linux.*//')
        fi
    fi

    # If still not found, fail
    if [ -z "${CCS_VERSION}" ] || [ "${CCS_VERSION}" = "latest" ]; then
        echo "[ERROR] CCS_VERSION not set and could not be detected"
        exit 1
    fi
fi

VER="${CCS_VERSION}"
MAJOR_VER=$(echo "$VER" | cut -d. -f1)
MINOR_VER=$(echo "$VER" | cut -d. -f2)
PATCH_VER=$(echo "$VER" | cut -d. -f3)
BUILD_VER=$(echo "$VER" | cut -d. -f4)

# Determine CCS installation path
# v9+: installs to /opt/ti/ccs/eclipse; v8-: installs to /opt/ti/ccsv<MAJOR>/eclipse
if [ "${MAJOR_VER}" -ge 9 ]; then
    CCS_ECLIPSE_DIR="/opt/ti/ccs/eclipse"
else
    CCS_ECLIPSE_DIR="/opt/ti/ccsv${MAJOR_VER}/eclipse"
fi

# Install CCS
echo "=== CCS Installation ==="
echo "Version    : ${VER}"
echo "Components : ${COMPONENTS}"
echo ""

# Docker-specific stubs for installer compatibility
if [ "${MAJOR_VER}" -ge 20 ]; then
    # v20+: BlackHawk installer calls udev/kernel commands
    ln -sf /bin/true /usr/local/bin/udevadm 2>/dev/null || true
    ln -sf /bin/true /sbin/start_udev 2>/dev/null || true
    ln -sf /bin/true /sbin/udevd 2>/dev/null || true
    ln -sf /bin/true /sbin/modprobe 2>/dev/null || true
    ln -sf /bin/true /sbin/insmod 2>/dev/null || true
    ln -sf /bin/true /sbin/rmmod 2>/dev/null || true
    mkdir -p /etc/udev/rules.d /run/udev /lib/modules 2>/dev/null || true
fi

# Start Xvfb for v7-v8 BitRock installers (GUI framework support)
XVFB_PID=""
if [ "${MAJOR_VER}" -le 8 ]; then
    echo ">>> Starting virtual display for v${MAJOR_VER} BitRock installer..."
    export DISPLAY=:99
    export GDK_BACKEND=x11
    export GTK_MODULES=""
    export NO_AT_BRIDGE=1
    export LIBGL_ALWAYS_INDIRECT=1
    Xvfb :99 -ac -screen 0 1024x768x24 -nolisten tcp > /dev/null 2>&1 &
    XVFB_PID=$!
    sleep 2
    echo ">>> Virtual display ready (DISPLAY=${DISPLAY}, PID=${XVFB_PID})"
fi

# Cleanup function for Xvfb
cleanup_xvfb() {
    if [ -n "$XVFB_PID" ]; then
        echo ">>> Stopping virtual display..."
        kill $XVFB_PID 2>/dev/null || true
        wait $XVFB_PID 2>/dev/null || true
    fi
}
trap cleanup_xvfb EXIT

# Create temporary directory for installation
INSTALL_LOG="/tmp/ccs_install.log"
mkdir -p /ccs_install
cd /ccs_install

_show_install_logs() {
    echo ""
    echo "=== Installer Output ==="
    cat "${INSTALL_LOG}" 2>/dev/null || echo "(no output captured)"
    echo ""
    echo "=== TI Installer Logs ==="
    find /root/.ti /tmp /opt/ti -name "*.log" 2>/dev/null | while read -r f; do
        echo "--- ${f} ---"
        cat "${f}"
    done
    echo "========================"
}

# Install CCS from pre-downloaded and extracted files
echo ">>> Using pre-downloaded CCS ${VER} installer..."
if [ "${MAJOR_VER}" -ge 20 ]; then
    echo ">>> Installing CCS ${VER} (this may take a few minutes)..."
    cd "/opt/ccs-installer/CCS_${VER}_linux"
    chmod +x "ccs_setup_${VER}.run"
    "./ccs_setup_${VER}.run" --mode unattended --enable-components "${COMPONENTS}" --prefix /opt/ti 2>&1 | tee "${INSTALL_LOG}"
else
    # Driver install scripts fix for v7-v19
    mkdir -p /etc/init.d /etc/udev/rules.d /root/.ti
    printf '#!/bin/sh\nexit 0\n' > /etc/init.d/udev && chmod 755 /etc/init.d/udev
    ln -sf /bin/true /usr/local/bin/udevadm 2>/dev/null || true
    ln -sf /bin/true /usr/local/bin/systemctl 2>/dev/null || true

    echo ">>> Installing CCS ${VER} (this may take a few minutes)..."
    if [ "${MAJOR_VER}" -ge 10 ]; then
        # v10+: new installer (.run, supports --enable-components)
        "/opt/ccs-installer/CCS${VER}_linux-x64/ccs_setup_${VER}.run" \
            --mode unattended --enable-components "${COMPONENTS}" --prefix /opt/ti \
            --install-BlackHawk false --install-Segger false 2>&1 | tee "${INSTALL_LOG}"
    else
        # v7-v9: old BitRock installer
        echo ">>> Note: --enable-components is not supported for CCS v9 and below. Installing all components."
        INSTALLER_BIN=$(find "/opt/ccs-installer/CCS${VER}_linux-x64" -maxdepth 1 \( -name "*.bin" -o -name "*.run" \) | sort | head -1)
        if [ "${MAJOR_VER}" -le 8 ]; then
            export JAVA_TOOL_OPTIONS=-Xss1280k
            DISPLAY=:99 "${INSTALLER_BIN}" \
                --mode unattended --prefix /opt/ti \
                --install-BlackHawk false --install-Segger false 2>&1 | tee "${INSTALL_LOG}"
        else
            "${INSTALLER_BIN}" \
                --mode unattended --prefix /opt/ti \
                --install-BlackHawk false --install-Segger false 2>&1 | tee "${INSTALL_LOG}"
        fi
    fi
fi

# Verify Installation
echo ">>> Verifying CCS installation..."
if [ "${MAJOR_VER}" -ge 20 ]; then
    if ! test -x "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh"; then
        echo "[ERROR] CCS installation failed: ccs-server-cli.sh not found"
        _show_install_logs
        exit 1
    fi
else
    if ! test -x "${CCS_ECLIPSE_DIR}/eclipse"; then
        echo "[ERROR] CCS installation failed: eclipse not found"
        _show_install_logs
        exit 1
    fi
fi
echo ">>> CCS ${VER} installation complete."

# Cleanup
echo ">>> Cleaning up installer files..."
cd /home
rm -rf /opt/ccs-installer /ccs_install

echo ""
echo "=== CCS ${VER} is ready. ==="
echo ""

# Export CCS to PATH
export PATH="${CCS_ECLIPSE_DIR}:${PATH}"

# Determine CCS version for logging
if [ -x "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh" ]; then
    CCS_TYPE="Theia-based (v20+)"
elif [ -x "${CCS_ECLIPSE_DIR}/eclipse" ]; then
    CCS_TYPE="Eclipse-based (v7-19)"
else
    CCS_TYPE="Unknown"
fi

echo "=== CCS Environment ==="
echo "Installation : ${CCS_ECLIPSE_DIR}"
echo "Type         : ${CCS_TYPE}"
echo "Components   : ${COMPONENTS}"
echo ""

# Parse arguments for project build
PROJECT_PATH="/github/workspace/$1"
PROJECT_NAME="$2"
BUILD_CONFIG="$3"
AUTO_IMPORT="${4:-false}"

echo "=== Project Build ==="
echo "Project Path  : ${PROJECT_PATH}"
echo "Project Name  : ${PROJECT_NAME}"
echo "Configuration : ${BUILD_CONFIG}"
echo "Auto Import   : ${AUTO_IMPORT}"
echo ""

# Import project
echo ">>> Importing project..."
if [ "${AUTO_IMPORT}" = "true" ]; then
    IMPORT_FLAGS=(-ccs.autoImport -ccs.location "${PROJECT_PATH}")
else
    IMPORT_FLAGS=(-ccs.location "${PROJECT_PATH}")
fi

if [ -x "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh" ]; then
    # v20+ (Theia-based)
    "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh" -noSplash -workspace /tmp/workspace \
        -application com.ti.ccs.apps.importProject \
        "${IMPORT_FLAGS[@]}"
else
    # v7-19 (Eclipse-based)
    "${CCS_ECLIPSE_DIR}/eclipse" -noSplash -data /tmp/workspace \
        -application com.ti.ccstudio.apps.projectImport \
        "${IMPORT_FLAGS[@]}"
fi

# Build project
echo ">>> Building project..."
BUILD_LOG=$(mktemp)
BUILD_FAILED=0

if [ -x "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh" ]; then
    # v20+ (Theia-based)
    "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh" -noSplash -workspace /tmp/workspace \
        -application com.ti.ccs.apps.buildProject \
        -ccs.projects "${PROJECT_NAME}" \
        -ccs.configuration "${BUILD_CONFIG}" \
        -ccs.listErrors 2>&1 | tee "${BUILD_LOG}" || BUILD_FAILED=1
elif [ -d "/opt/ti/ccs/eclipse" ]; then
    # v11-19 (Eclipse-based, with -ccs.listErrors)
    "${CCS_ECLIPSE_DIR}/eclipse" -noSplash -data /tmp/workspace \
        -application com.ti.ccstudio.apps.projectBuild \
        -ccs.projects "${PROJECT_NAME}" \
        -ccs.configuration "${BUILD_CONFIG}" \
        -ccs.listErrors 2>&1 | tee "${BUILD_LOG}" || BUILD_FAILED=1
else
    # v7-10 (Eclipse-based, without -ccs.listErrors)
    "${CCS_ECLIPSE_DIR}/eclipse" -noSplash -data /tmp/workspace \
        -application com.ti.ccstudio.apps.projectBuild \
        -ccs.projects "${PROJECT_NAME}" \
        -ccs.configuration "${BUILD_CONFIG}" \
        2>&1 | tee "${BUILD_LOG}" || BUILD_FAILED=1
fi

# Check build result
if [ "${BUILD_FAILED}" -ne 0 ] || grep -qE "[1-9][0-9]* out of .* projects have errors" "${BUILD_LOG}"; then
    rm -f "${BUILD_LOG}"
    echo "[ERROR] Build failed."
    exit 1
fi

rm -f "${BUILD_LOG}"
echo ""
echo "=== Build complete ==="
