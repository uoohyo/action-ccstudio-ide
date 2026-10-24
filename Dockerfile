# Argument for CCS version (defaults to latest)
# This will be set automatically from the git tag during build
ARG CCS_VERSION=10.3.0.00007

# Base Image with CCS installer pre-extracted
FROM uoohyo/ccstudio-ide:${CCS_VERSION}

# Metadata
LABEL org.opencontainers.image.source="https://github.com/uoohyo/action-ccstudio-ide"
LABEL org.opencontainers.image.description="Build with Code Composer Studio ${CCS_VERSION}"
LABEL org.opencontainers.image.licenses="MIT"

# Pass CCS version to entrypoint
ENV CCS_VERSION=${CCS_VERSION}

# Copy entrypoint script
COPY --chmod=755 entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
