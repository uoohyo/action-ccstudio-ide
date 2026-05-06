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

# Detect CCS installation path
# docker-ccstudio-ide pre-installs CCS at a fixed location
# v20+: /opt/ti/ccs/eclipse (Theia-based)
# v9-19: /opt/ti/ccs/eclipse (Eclipse-based)
# v7-8: /opt/ti/ccsv<MAJOR>/eclipse
if [ -d "/opt/ti/ccs/eclipse" ]; then
    CCS_ECLIPSE_DIR="/opt/ti/ccs/eclipse"
elif [ -d "/opt/ti/ccsv8/eclipse" ]; then
    CCS_ECLIPSE_DIR="/opt/ti/ccsv8/eclipse"
elif [ -d "/opt/ti/ccsv7/eclipse" ]; then
    CCS_ECLIPSE_DIR="/opt/ti/ccsv7/eclipse"
else
    echo "[ERROR] CCS installation not found"
    echo "Expected locations:"
    echo "  - /opt/ti/ccs/eclipse (v9+)"
    echo "  - /opt/ti/ccsv8/eclipse (v8)"
    echo "  - /opt/ti/ccsv7/eclipse (v7)"
    exit 1
fi

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

# Parse arguments
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
# CCS may return exit code 0 even on build failure — also check output
if [ "${BUILD_FAILED}" -ne 0 ] || grep -qE "[1-9][0-9]* out of .* projects have errors" "${BUILD_LOG}"; then
    rm -f "${BUILD_LOG}"
    echo "[ERROR] Build failed."
    exit 1
fi

rm -f "${BUILD_LOG}"
echo ""
echo "=== Build complete ==="
