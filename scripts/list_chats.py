#!/usr/bin/env python3
"""
List chat history for NothingLess AI sidebar.
Reads all JSON chat files from the chat directory and outputs
one line per chat: <id>|<title>|<mode>|<agentId>|<model>

Usage: list_chats.py <chat_dir>

The chat envelope format is documented in modules/services/Ai.qml
(_serializeChat). It is:
    { mode, agentId, model, messages: [ {role, content, ...}, ... ] }

We support both the new envelope and the legacy bare-array format
(an array of message objects directly) so the script doesn't
crash on older chat files written before the envelope was added.
"""
import json
import os
import sys
from pathlib import Path


def extract_title(messages: list) -> str:
    """Return a short preview of the first user message, or 'New Chat'."""
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        if msg.get("role") == "user":
            content = msg.get("content", "") or ""
            if not isinstance(content, str):
                content = str(content)
            title = content[:40].replace("\n", " ").strip()
            if len(content) > 40:
                title += "…"
            return title or "New Chat"
    return "New Chat"


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: list_chats.py <chat_dir>", file=sys.stderr)
        sys.exit(1)

    chat_dir = Path(sys.argv[1])
    chat_dir.mkdir(parents=True, exist_ok=True)

    files = sorted(chat_dir.glob("*.json"), key=lambda f: f.stat().st_mtime, reverse=True)

    for f in files:
        chat_id = f.stem
        title = "New Chat"
        mode = ""
        agent_id = ""
        model = ""
        try:
            with open(f) as fp:
                data = json.load(fp)

            # New envelope format
            if isinstance(data, dict):
                mode = data.get("mode", "") or ""
                agent_id = data.get("agentId", "") or ""
                model = data.get("model", "") or ""
                messages = data.get("messages", []) or []
                title = extract_title(messages)
            # Legacy bare-array format
            elif isinstance(data, list):
                title = extract_title(data)
        except (json.JSONDecodeError, OSError):
            # Corrupt or unreadable file — keep the defaults.
            pass

        # Pipe-separated so the consumer (QML) can split on "|".
        # We avoid "| " inside the title (which is a header separator)
        # by replacing any "| " with " / ".
        safe_title = title.replace("|", "/")
        print(f"{chat_id}|{safe_title}|{mode}|{agent_id}|{model}")


if __name__ == "__main__":
    main()
