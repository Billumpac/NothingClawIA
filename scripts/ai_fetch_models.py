#!/usr/bin/env python3
"""
ai_fetch_models.py — fetch the model list for one provider, print JSON
to stdout.

This helper exists because Quickshell 0.3.0's `Process` element has a
known regression where short-lived `curl` invocations sometimes never
fire `onExited`, which used to leave the model dropdown empty even
when the user had a valid API key. Going through python3 gives the
QML side a single, observable process to listen to, and the python
startup (~30ms) is invisible to the user.

Usage: ai_fetch_models.py <provider> [api_key]

Output: a JSON array of model objects on stdout, matching the shape
that `ai_bridge.py` previously produced and that `Ai.qml`
`_parseFetchResponse` knows how to consume.

Each item:
  { "name": "Display Name",
    "description": "…",
    "endpoint": "https://…",
    "model": "model-id",
    "provider": "deepseek",
    "requires_key": true,
    "key_id": "DEEPSEEK_API_KEY" }
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request


TIMEOUT = 10


def _name(id_, fallback_prefix):
    """Return a display name for a model id, falling back to a
    title-cased version when the id is already a slug like 'gpt-4o'."""
    pretty = id_.replace("-", " ").replace("_", " ").strip()
    if not pretty:
        return id_
    return pretty[:1].upper() + pretty[1:]


def _http_get(url, headers=None, timeout=TIMEOUT):
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return 0, ""


def fetch_ollama(host="http://127.0.0.1:11434"):
    status, body = _http_get(host + "/api/tags", timeout=5)
    if status != 200:
        return []
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return []
    out = []
    for m in (data.get("models") or []):
        name = m.get("name")
        if not name:
            continue
        out.append({
            "name": name,
            "description": "Local Ollama model",
            "endpoint": host,
            "model": name,
            "provider": "ollama",
            "requires_key": False,
            "key_id": "",
        })
    return out


def fetch_openai_compat(base, headers, allow=None):
    status, body = _http_get(base + "/models", headers=headers)
    if status != 200:
        return []
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return []
    items = data.get("data") or []
    if allow:
        items = [m for m in items if m.get("id") in allow or any(
            m.get("id", "").startswith(a + "-") or m.get("id", "") == a for a in allow
        )]
    out = []
    for m in items:
        mid = m.get("id")
        if not mid:
            continue
        provider = (base
                   .replace("https://api.", "")
                   .replace("https://", "")
                   .split("/")[0]
                   .split(".")[0])
        out.append({
            "name": mid,
            "description": f"{provider.title()} model",
            "endpoint": base,
            "model": mid,
            "provider": provider,
            "requires_key": True,
            "key_id": f"{provider.upper()}_API_KEY",
        })
    return out


def fetch_gemini(key):
    status, body = _http_get(
        f"https://generativelanguage.googleapis.com/v1beta/models?key={key}"
    )
    if status != 200:
        return []
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return []
    out = []
    for item in (data.get("models") or []):
        mid = (item.get("name") or "").replace("models/", "")
        if not (mid and ("gemini" in mid or "flash" in mid or "pro" in mid)):
            continue
        out.append({
            "name": item.get("displayName") or mid,
            "description": item.get("description") or "Google Gemini model",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta",
            "model": mid,
            "provider": "gemini",
            "requires_key": True,
            "key_id": "GEMINI_API_KEY",
        })
    return out


def fetch_anthropic(key):
    # Anthropic doesn't expose a /models endpoint; the canonical
    # model set is small and stable, so we just return a curated
    # list. Users can add more via Config.ai.extraModels.
    return [
        {"name": "Claude 3.5 Sonnet", "model": "claude-3-5-sonnet-latest",
         "description": "Anthropic Claude 3.5 Sonnet"},
        {"name": "Claude 3.5 Haiku", "model": "claude-3-5-haiku-latest",
         "description": "Anthropic Claude 3.5 Haiku"},
        {"name": "Claude 3 Opus", "model": "claude-3-opus-latest",
         "description": "Anthropic Claude 3 Opus"},
    ]


def fetch_minimax():
    return [
        {"name": "MiniMax-M2.7", "model": "MiniMax-M2.7",
         "description": "MiniMax M2.7"},
        {"name": "MiniMax-M2.7-highspeed", "model": "MiniMax-M2.7-highspeed",
         "description": "MiniMax M2.7 (faster)"},
        {"name": "MiniMax-M2.5", "model": "MiniMax-M2.5",
         "description": "MiniMax M2.5"},
        {"name": "MiniMax-M2.1", "model": "MiniMax-M2.1",
         "description": "MiniMax M2.1"},
        {"name": "MiniMax-M2", "model": "MiniMax-M2",
         "description": "MiniMax M2"},
    ]


def main():
    if len(sys.argv) < 2:
        print("[]")
        return
    provider = sys.argv[1].lower()
    api_key = sys.argv[2] if len(sys.argv) > 2 else ""

    if provider == "ollama":
        out = fetch_ollama()
    elif provider == "gemini":
        out = fetch_gemini(api_key) if api_key else []
    elif provider == "anthropic":
        out = fetch_anthropic(api_key) if api_key else []
    elif provider == "minimax":
        out = fetch_minimax()
    elif provider == "openai":
        out = fetch_openai_compat("https://api.openai.com/v1",
                                  {"Authorization": f"Bearer {api_key}"},
                                  allow={"gpt-4o", "gpt-4o-mini", "gpt-4-turbo",
                                         "gpt-4", "o1", "o1-mini", "o1-preview",
                                         "o3-mini"}) if api_key else []
    elif provider == "mistral":
        out = fetch_openai_compat("https://api.mistral.ai/v1",
                                  {"Authorization": f"Bearer {api_key}"}) if api_key else []
    elif provider == "groq":
        out = fetch_openai_compat("https://api.groq.com/openai/v1",
                                  {"Authorization": f"Bearer {api_key}"}) if api_key else []
    elif provider == "deepseek":
        out = fetch_openai_compat("https://api.deepseek.com/v1",
                                  {"Authorization": f"Bearer {api_key}"}) if api_key else []
    else:
        out = []

    print(json.dumps(out))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Never crash — return an empty list so the QML side just
        # shows fewer models instead of getting stuck.
        print("[]")
