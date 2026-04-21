# Base Image
FROM uoohyo/ccstudio-ide:latest

# Entrypoint
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
