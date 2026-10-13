# Use an official, optimized dev container base image
FROM mcr.microsoft.com/devcontainers/base:ubuntu26.04
# System-wide configuration to dynamically find and source the repo's .env file
RUN echo '\n\
# --- Dynamically Source Repo Root .env --- \n\
# In Codespaces, the workspace directory is always inside /workspaces/ \n\
WORKSPACE_DIR=$(find /workspaces -maxdepth 2 -type d 2>/dev/null | head -n 2 | tail -n 1) \n\
\n\
if [ -f "$WORKSPACE_DIR/.env" ]; then \n\
    export $(grep -v "^#" "$WORKSPACE_DIR/.env" | xargs) \n\
elif [ -f "./.env" ]; then \n\
    export $(grep -v "^#" ./.env | xargs) \n\
fi \n\
' >> /etc/bash.bashrc

