import QtQuick
import Quickshell
import qs.config

/*!
    AgentManager — In-memory registry of active AI agent connections.

    Source of truth for the *list of agents* is `AgentStore` (per-file
    JSON in `~/.local/share/nothingless/agents/<id>.json`). This service
    is responsible for:
      - Subscribing to AgentStore.profilesChanged and rebuilding the
        in-memory `AgentConnection` objects when profiles appear, change
        or disappear.
      - Spawning the appropriate client (HTTP / MCP / command) for
        each enabled profile.
      - Forwarding tool invocations to the live client.

    Note: `AgentStore.writeProfile` is the only path that touches the
    disk. This service never writes files directly.
*/
QtObject {
    id: root

    property var connections: [] // AgentConnection objects
    property var _clients: ({})  // agentId -> client QtObject
    property QtObject toolRegistry: null

    signal statusChanged(string agentId, string status, string message)

    property Component agentConnectionFactory: Component {
        AgentConnection {}
    }

    property Component httpClientFactory: Component {
        HttpAgentClient {}
    }

    property Component commandClientFactory: Component {
        CommandAgentClient {}
    }

    property Component mcpStdioClientFactory: Component {
        McpStdioClient {}
    }

    Component.onCompleted: {
        reloadFromStore();
    }

    // Tear down all live clients — called before a full rebuild.
    function _teardownAll() {
        for (let id in _clients) {
            try {
                if (_clients[id]) {
                    _clients[id].stop();
                    _clients[id].destroy();
                }
            } catch (e) {
                // already destroyed
            }
        }
        _clients = {};
    }

    // Full rebuild from AgentStore. Guarded against re-entrancy: if
    // two profile-change signals arrive before the first reload
    // completes, we defer the second. Without this, overlapping
    // _connectAgent / _teardownAll calls can keep the shell main
    // thread busy and cause the "se queda trabado" (stuck/frozen)
    // user experience.
    property bool _storeReloading: false
    function reloadFromStore() {
        if (_storeReloading) {
            Qt.callLater(root.reloadFromStore);
            return;
        }
        _storeReloading = true;
        _teardownAll();

        let store = AgentStore.listProfiles();
        let newConnections = [];
        for (let i = 0; i < store.length; i++) {
            let c = store[i];
            if (!c) continue;
            let conn = agentConnectionFactory.createObject(root, {
                id: c.id,
                name: c.name,
                type: c.type,
                enabled: c.enabled !== false,
                command: c.command || "",
                args: c.args || [],
                endpoint: c.endpoint || "",
                headers: c.headers || {},
                toolsPath: c.toolsPath || "/tools",
                invokePath: c.invokePath || "/invoke"
            });
            if (!conn) {
                console.warn("AgentManager: failed to create AgentConnection for", c.id,
                    "— missing AgentConnection.qml?");
                continue;
            }
            newConnections.push(conn);

            if (conn.enabled) {
                _connectAgent(conn);
            }
        }
        connections = newConnections;
        _storeReloading = false;
    }

    // Re-read a single profile from the store and apply it. Used when
    // the user edits a profile from the editor and the FileView
    // triggers a refresh — we want to re-spawn the client if the
    // connection params changed.
    function refreshOne(profileId) {
        let p = AgentStore.getProfile(profileId);
        if (!p) {
            // Profile was deleted — drop the connection.
            _teardownOne(profileId);
            let arr = [];
            for (let i = 0; i < connections.length; i++) {
                if (connections[i] && connections[i].id !== profileId) arr.push(connections[i]);
            }
            connections = arr;
            return;
        }
        // Find existing conn; if found, tear down its client and
        // replace the in-memory object.
        let existingIdx = -1;
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === profileId) {
                existingIdx = i;
                break;
            }
        }
        if (existingIdx >= 0) {
            _teardownOne(profileId);
        }
        let conn = agentConnectionFactory.createObject(root, {
            id: p.id,
            name: p.name,
            type: p.type,
            enabled: p.enabled !== false,
            command: p.command || "",
            args: p.args || [],
            endpoint: p.endpoint || "",
            headers: p.headers || {},
            toolsPath: p.toolsPath || "/tools",
            invokePath: p.invokePath || "/invoke"
        });
        let arr = connections.slice();
        if (existingIdx >= 0) {
            arr[existingIdx] = conn;
        } else {
            arr.push(conn);
        }
        connections = arr;
        if (conn.enabled) {
            _connectAgent(conn);
        }
    }

    function _teardownOne(agentId) {
        if (_clients[agentId]) {
            try {
                _clients[agentId].stop();
                _clients[agentId].destroy();
            } catch (e) {}
            delete _clients[agentId];
        }
        if (root.toolRegistry) root.toolRegistry.unregister(agentId);
    }

    // Subscribe to AgentStore: rebuild on full change, refresh one on
    // single save/delete.
    property Connections storeWatcher: Connections {
        target: AgentStore
        function onProfilesChanged() {
            Qt.callLater(root.reloadFromStore);
        }
        function onProfileSaved(id) {
            Qt.callLater(function() { root.refreshOne(id); });
        }
        function onProfileDeleted(id) {
            Qt.callLater(function() { root.refreshOne(id); });
        }
    }

    function _connectAgent(conn) {
        conn.status = "connecting";
        conn.statusMessage = "";
        statusChanged(conn.id, "connecting", "");

        let client;
        if (conn.type === "http-bridge" || conn.type === "mcp-sse") {
            client = httpClientFactory.createObject(root, {});
            _wireClientSignals(client, conn);
            client.start(conn.endpoint, conn.headers, conn.toolsPath, conn.invokePath);
        } else if (conn.type === "command") {
            client = commandClientFactory.createObject(root, {});
            _wireClientSignals(client, conn);
            client.start(conn.command, conn.args);
        } else if (conn.type === "mcp-stdio") {
            client = mcpStdioClientFactory.createObject(root, {});
            _wireClientSignals(client, conn);
            client.start(conn.command, conn.args);
        } else {
            conn.status = "error";
            conn.statusMessage = "Unsupported agent type: " + conn.type;
            statusChanged(conn.id, "error", conn.statusMessage);
            return;
        }

        _clients[conn.id] = client;
    }

    function _wireClientSignals(client, conn) {
        client.connected.connect(() => {
            conn.status = "connected";
            statusChanged(conn.id, "connected", "");
        });
        client.disconnected.connect(() => {
            conn.status = "disconnected";
            statusChanged(conn.id, "disconnected", "");
        });
        client.error.connect(msg => {
            conn.status = "error";
            conn.statusMessage = msg;
            statusChanged(conn.id, "error", msg);
        });
        client.toolsDiscovered.connect(tools => {
            conn.discoveredTools = tools || [];
            if (root.toolRegistry) root.toolRegistry.register(conn.id, conn, tools);
        });
    }

    // Disconnect (stop the client, mark disabled). The next time the
    // profile is reloaded (e.g. on shell restart), the disabled state
    // is honored.
    function disconnectAgent(agentId) {
        _teardownOne(agentId);
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === agentId) {
                if (connections[i].enabled) {
                    connections[i].enabled = false;
                    // Persist the disabled state via the store.
                    let p = AgentStore.getProfile(agentId);
                    if (p) {
                        p.enabled = false;
                        AgentStore.saveProfile(p);
                    }
                }
                connections[i].status = "disconnected";
                break;
            }
        }
    }

    // Reconnect: re-enable the profile and spawn the client.
    function reconnectAgent(agentId) {
        _teardownOne(agentId);
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === agentId) {
                connections[i].enabled = true;
                let p = AgentStore.getProfile(agentId);
                if (p) {
                    p.enabled = true;
                    AgentStore.saveProfile(p);
                }
                if (connections[i].enabled) _connectAgent(connections[i]);
                break;
            }
        }
    }

    // ── Migration shim ──
    // Kept for back-compat with anything in the dashboard that still
    // calls these. They all delegate to AgentStore.
    function addConnection(config) {
        if (!config || !config.id) {
            console.warn("AgentManager.addConnection: invalid config, missing id");
            return;
        }
        AgentStore.saveProfile(config);
    }

    function removeConnection(agentId) {
        // Tear down the live client, then remove the file.
        _teardownOne(agentId);
        AgentStore.deleteProfile(agentId);
    }

    function saveConnections() {
        // Force a re-snapshot from in-memory connections back to disk.
        for (let i = 0; i < connections.length; i++) {
            AgentStore.saveProfile(connections[i]);
        }
    }

    // Agent tool invocation dispatcher
    property Connections invokeDispatcher: Connections {
        target: root.toolRegistry
        function onToolInvokeRequested(agentId, tool, args, callback) {
            let client = root._clients[agentId];
            if (!client) {
                if (callback) callback({ content: "", error: "Agent not connected", done: true });
                return;
            }
            if (typeof client.invokeTool === "function") {
                client.invokeTool(tool.name, args, callback);
            } else if (typeof client.sendRequest === "function") {
                client.sendRequest("tools/call", { name: tool.name, arguments: args || {} }, function(err, result) {
                    if (err) {
                        let msg = err.message || (typeof err === "string" ? err : JSON.stringify(err));
                        callback({ content: "", error: msg, done: true });
                        return;
                    }
                    let content = "";
                    if (result) {
                        if (typeof result === "string") content = result;
                        else if (result.content !== undefined) content = typeof result.content === "string" ? result.content : JSON.stringify(result.content);
                        else if (result.result !== undefined) content = typeof result.result === "string" ? result.result : JSON.stringify(result.result);
                        else content = JSON.stringify(result);
                    }
                    let isError = !!(result && result.isError);
                    callback({ content: content, error: isError ? content : null, done: true });
                });
            } else {
                if (callback) callback({ content: "", error: "Client does not support tool invocation", done: true });
            }
        }
    }
}
