# NothingClaw MCP Server

This is a lightweight HTTP bridge designed to connect the **NothingClaw** AI assistant to Lerit's **Mirai** bar. It handles the communication between the AI and your system via a local HTTP server, bypassing the stability issues often found with standard stdio pipes on Linux.

## Features
- **HTTP-based communication:** Uses Starlette/Uvicorn for a reliable connection, avoiding common pipe synchronization errors.
- **System Integration:** Comes with built-in tools to check for installed apps, manage processes, and control window management via `axctl`.
- **Easy Deployment:** Includes a setup script to handle dependencies and service configuration automatically.

