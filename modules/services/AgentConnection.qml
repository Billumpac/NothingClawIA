import QtQuick

/*!
    AgentConnection — In-memory mirror of a single agent profile.

    One instance per saved agent profile. The connection holds the
    static configuration (endpoint, command, headers, etc.) plus
    live status fields (status, statusMessage, discoveredTools) that
    get mutated as the agent client connects and discovers tools.

    AgentManager.reloadFromStore() creates one of these per
    profile via agentConnectionFactory.createObject(); the client
    (HttpAgentClient / CommandAgentClient / McpStdioClient) writes
    `status` and `discoveredTools` back into the connection. The
    AgentToolRegistry reads `discoveredTools` to populate the
    in-memory tool list that the AI sees.
*/
QtObject {
    id: root

    // ── Static profile (set once at creation, never mutated) ──
    property string id: ""
    property string name: ""
    property string type: ""             // http-bridge | mcp-sse | command | mcp-stdio
    property bool enabled: true
    property string command: ""
    property var args: []
    property string endpoint: ""
    property var headers: ({})
    property string toolsPath: "/tools"
    property string invokePath: "/invoke"

    // ── Live state (mutated by the client) ──
    // status: "connecting" | "connected" | "disconnected" | "error"
    property string status: "disconnected"
    property string statusMessage: ""
    property var discoveredTools: []
}
