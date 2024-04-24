# Base Image
FROM uoohyo/ccstudio-ide:latest

# File Copy
COPY entrypoint.sh /entrypoint.sh

# Entry Point
ENTRYPOINT ["/entrypoint.sh"]