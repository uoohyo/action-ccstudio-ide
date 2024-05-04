# Base Image
FROM uoohyo/ccstudio-ide:latest

# File Copy
COPY entrypoint.sh /entrypoint.sh

# Set execute permission for the entrypoint script
RUN chmod +x /entrypoint.sh

# Entry Point
ENTRYPOINT ["/entrypoint.sh"]