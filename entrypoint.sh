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

# Variables
CCS_URL="https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-J1VdearkvK/"
VER="${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}"
# v9+: installs to /opt/ti/ccs/eclipse; v8-: installs to /opt/ti/ccsv<MAJOR>/eclipse
if [ "${MAJOR_VER}" -ge 9 ]; then
    CCS_ECLIPSE_DIR="/opt/ti/ccs/eclipse"
else
    CCS_ECLIPSE_DIR="/opt/ti/ccsv${MAJOR_VER}/eclipse"
fi

# Download and Install CCS
# v20+:  zip package, CCS_ prefix, URL path: MAJOR.MINOR.PATCH
# v12-:  tar.gz package, CCS prefix, URL path: MAJOR.MINOR.PATCH (v12) or MAJOR.MINOR.PATCH.BUILD (v11-)
# v10+:  installer binary is ccs_setup_<VER>.run, supports --enable-components (PF_* IDs)
# v9-:   installer binary is ccs_setup_linux64_<VER>.bin, --enable-components not supported
# v20+: udev stubs required — BlackHawk installer calls udev/kernel commands unavailable in Docker
#       Ref: https://e2e.ti.com/support/tools/code-composer-studio-group/ccs/f/code-composer-studio-forum/1532443
echo "=== CCS Installation ==="
echo "Version    : ${VER}"
echo "Components : ${COMPONENTS}"
echo ""

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

# Download and Install CCS
echo ">>> Downloading CCS ${VER}..."
if [ "${MAJOR_VER}" -ge 20 ]; then
    ln -sf /bin/true /usr/local/bin/udevadm
    ln -sf /bin/true /sbin/start_udev
    ln -sf /bin/true /sbin/udevd
    ln -sf /bin/true /sbin/modprobe
    ln -sf /bin/true /sbin/insmod
    ln -sf /bin/true /sbin/rmmod
    mkdir -p /etc/udev/rules.d /run/udev /lib/modules

    wget --timeout=300 --tries=3 "${CCS_URL}${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}/CCS_${VER}_linux.zip"
    echo ">>> Extracting..."
    unzip "CCS_${VER}_linux.zip"
    chmod -R 755 "CCS_${VER}_linux"
    echo ">>> Installing CCS ${VER} (this may take a while)..."
    cd "CCS_${VER}_linux"
    chmod +x "ccs_setup_${VER}.run"
    "./ccs_setup_${VER}.run" --mode unattended --enable-components "${COMPONENTS}" --prefix /opt/ti 2>&1 | tee "${INSTALL_LOG}"
else
    # v12: URL path is 3-part (MAJOR.MINOR.PATCH); v11 and below: 4-part (MAJOR.MINOR.PATCH.BUILD)
    if [ "${MAJOR_VER}" -ge 12 ]; then
        CCS_DL_PATH="${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}"
    else
        CCS_DL_PATH="${VER}"
    fi
    # Driver install scripts (bh_driver_install.sh for v7-v9, ti_permissions_install.sh for v10-v12)
    # copy udev rules then try to restart the udev service, which doesn't exist in Docker:
    #   v7-v9:   'service udev restart'  → "udev: unrecognized service"
    #   v10-v12: 'systemctl restart udev' → "not booted with systemd"
    # Either failure causes the BitRock/Run installer to roll back the full installation.
    # Fix: create required dirs, stub udev init script, and redirect udev-related commands to /bin/true.
    # /root/.ti is read by the installer's fs --clean step; missing it causes a boost::filesystem crash.
    mkdir -p /etc/init.d /etc/udev/rules.d /root/.ti
    printf '#!/bin/sh\nexit 0\n' > /etc/init.d/udev && chmod 755 /etc/init.d/udev
    ln -sf /bin/true /usr/local/bin/udevadm
    ln -sf /bin/true /usr/local/bin/systemctl
    wget --timeout=300 --tries=3 "${CCS_URL}${CCS_DL_PATH}/CCS${VER}_linux-x64.tar.gz"
    echo ">>> Extracting..."
    tar -zxf "CCS${VER}_linux-x64.tar.gz"
    chmod -R 755 "CCS${VER}_linux-x64"
    echo ">>> Installing CCS ${VER} (this may take a while)..."
    # v10+: new installer (.run, supports --enable-components with PF_* IDs)
    # v9-:  old BitRock installer; binary name varies (linux64_*.bin or *.run), use find to detect
    if [ "${MAJOR_VER}" -ge 10 ]; then
        "./CCS${VER}_linux-x64/ccs_setup_${VER}.run" \
            --mode unattended --enable-components "${COMPONENTS}" --prefix /opt/ti \
            --install-BlackHawk false --install-Segger false 2>&1 | tee "${INSTALL_LOG}"
    else
        echo ">>> Note: --enable-components is not supported for CCS v9 and below. Installing all components."
        INSTALLER_BIN=$(find "./CCS${VER}_linux-x64" -maxdepth 1 \( -name "*.bin" -o -name "*.run" \) | sort | head -1)
        "${INSTALLER_BIN}" \
            --mode unattended --prefix /opt/ti \
            --install-BlackHawk false --install-Segger false 2>&1 | tee "${INSTALL_LOG}"
    fi
fi

# Verify Installation
echo ">>> Verifying CCS installation..."
if [ "${MAJOR_VER}" -ge 20 ]; then
    test -x "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh" || { echo "[ERROR] CCS installation failed: ccs-server-cli.sh not found"; exit 1; }
else
    test -x "${CCS_ECLIPSE_DIR}/eclipsec" || { echo "[ERROR] CCS installation failed: eclipsec not found"; exit 1; }
fi
echo ">>> CCS ${VER} installation complete."

# Cleanup
echo ">>> Cleaning up..."
cd /home
rm -rf /ccs_install

echo ""
echo "=== CCS ${VER} is ready. ==="
echo ""

echo "=== Project Build ==="
echo "Project Path  : $1"
echo "Project Name  : $2"
echo "Configuration : $3"
echo ""

echo ">>> Importing project..."
if [ "${MAJOR_VER}" -ge 20 ]; then
    "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh" -noSplash -workspace /tmp/workspace \
        -application com.ti.ccs.apps.importProject \
        -ccs.location "$1"
else
    "${CCS_ECLIPSE_DIR}/eclipsec" -noSplash -data /tmp/workspace \
        -application com.ti.ccstudio.apps.projectImport \
        -ccs.location "$1"
fi

echo ">>> Building project..."
BUILD_LOG=$(mktemp)
BUILD_FAILED=0

if [ "${MAJOR_VER}" -ge 20 ]; then
    "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh" -noSplash -workspace /tmp/workspace \
        -application com.ti.ccs.apps.buildProject \
        -ccs.projects "$2" \
        -ccs.configuration "$3" \
        -ccs.listErrors 2>&1 | tee "${BUILD_LOG}" || BUILD_FAILED=1
elif [ "${MAJOR_VER}" -ge 11 ]; then
    "${CCS_ECLIPSE_DIR}/eclipsec" -noSplash -data /tmp/workspace \
        -application com.ti.ccstudio.apps.projectBuild \
        -ccs.projects "$2" \
        -ccs.configuration "$3" \
        -ccs.listErrors 2>&1 | tee "${BUILD_LOG}" || BUILD_FAILED=1
else
    "${CCS_ECLIPSE_DIR}/eclipsec" -noSplash -data /tmp/workspace \
        -application com.ti.ccstudio.apps.projectBuild \
        -ccs.projects "$2" \
        -ccs.configuration "$3" \
        2>&1 | tee "${BUILD_LOG}" || BUILD_FAILED=1
fi

# CCS may return exit code 0 even on build failure — also check output
if [ "${BUILD_FAILED}" -ne 0 ] || grep -qE "[1-9][0-9]* out of .* projects have errors" "${BUILD_LOG}"; then
    rm -f "${BUILD_LOG}"
    echo "[ERROR] Build failed."
    exit 1
fi

rm -f "${BUILD_LOG}"
echo ""
echo "=== Build complete ==="