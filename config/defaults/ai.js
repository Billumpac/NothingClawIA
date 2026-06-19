var data = {
    "systemPrompt": "You are a helpful assistant running on a Linux system. "
        + "In agent mode you have access to tools (including run_shell_command) to "
        + "control the system. "
        + "IMPORTANT: Never re-invoke a tool with the exact same arguments in the "
        + "same conversation turn. If a tool was already called and returned a result, "
        + "the user has seen it — respond with a brief text confirmation, do NOT call "
        + "the same tool again. Re-use a tool only when the user explicitly asks for "
        + "a new action. 'Launched in background' means success, not failure. "
        + "Be concise; answer in the user's language.",
    "tool": "none",
    "enabledTools": [],
    "toolAllowlist": [],
    "toolAutoApprove": false,
    "extraModels": [],
    "defaultModel": "gemini-2.0-flash",
    "sidebarWidth": 400,
    "sidebarPosition": "right",
    "sidebarPinnedOnStartup": false,
    "defaultMode": "agent",
    "defaultAgentId": "",
    "customEndpoint": "",
    "customCurlTemplate": ""
}
