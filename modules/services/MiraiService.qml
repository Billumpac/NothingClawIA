pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/*!
    MiraiService — Thin client to the [Mirai](https://github.com/leriart/Mirai)
    Miracast daemon.

    Mirai exposes a JSON-over-Unix-socket API plus a `mirai` CLI
    (status / source-scan / source-connect / source-disconnect / sink-start /
    sink-stop / sink-mode / displays). This service wraps the CLI via
    Quickshell.Io.Process and exposes the daemon state as reactive QML
    properties so the panel, bar widget, and IPC handlers can bind to it.

    The daemon must be running for the service to return useful data; if it
    is not, all commands fail gracefully and `daemonRunning` stays false.
    Use `startDaemon()` to ask pkexec/systemd to bring it up.

    State polling: a Timer refreshes `status` every 2s while the service is
    active. Sinks discovered via `scanSinks()` are cached and surface as
    `sinks` until cleared or replaced by a new scan.
*/
Singleton {
    id: root

    // ── Daemon presence ──
    property bool daemonAvailable: false   // `mirai` binary on PATH
    property bool daemonRunning: false     // socket reachable
    property string daemonError: ""

    // ── Mirrored daemon state (parsed from `mirai status`) ──
    property string mode: "idle"           // idle | sink | source
    property bool streaming: false         // source.streaming
    property bool receiving: false         // sink.running
    property string sinkMode: "window"     // window | fullscreen
    property string activeSinkId: ""
    property string activeSinkName: ""
    property string activeDisplay: ""
    property string lastError: ""
    property string statusMessage: "Mirai not running"
    property string daemonVersion: ""
    property string sinkFriendlyName: "Mirai Display"
    property int sinkLinkCount: 0

    // ── Devices / displays ──
    property var displays: []              // [{name, width, height, primary, x, y, refresh, scale}, ...]
    property var sinks: []                 // [{id, name, protocol, address, port}, ...]
    property bool scanning: false
    property int lastScanDurationMs: 0
    property string lastScanTime: ""       // HH:MM:SS of last successful scan

    // ── Recent log lines (from `mirai logs -n`) ──
    property var recentLogs: []            // [{ts, level, msg}, ...]
    property bool logsLoading: false

    // ── User-selected defaults (persisted via StateService on save) ──
    property string preferredDisplay: ""   // last display the user picked for casting
    property string preferredSinkId: ""    // last sink we cast to (for quick reconnect)

    // ── Polling ──
    property bool initialized: false
    property int pollIntervalMs: 2000

    // NOTE: do NOT declare `streamingChanged` / `receivingChanged` /
    // `sinksChanged` signals manually — QML auto-generates them for the
    // properties above. Declaring them again causes "Duplicate signal
    // name" load errors.
    signal errorOccurred(string message)

    Component.onCompleted: {
        root._checkBinary();
        if (root.daemonAvailable) {
            Qt.callLater(root.refreshStatus);
        }
        pollTimer.interval = root.pollIntervalMs;
        pollTimer.start();
    }

    function _checkBinary() {
        binaryCheck.running = true;
    }

    property Process binaryCheck: Process {
        command: ["bash", "-c", "command -v mirai >/dev/null 2>&1 && echo ok || echo missing"]
        running: false
        stdout: SplitParser {
            onRead: line => {
                if (line === "ok") {
                    root.daemonAvailable = true;
                    root.daemonError = "";
                } else {
                    root.daemonAvailable = false;
                    root.daemonRunning = false;
                    root.daemonError = "mirai CLI not found — install Mirai";
                }
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        running: false
        onTriggered: {
            if (root.daemonAvailable) {
                root.refreshStatus();
            }
        }
    }

    // ── Generic one-shot mirai invocation ──
    // Returns the parsed JSON reply via callback, or null on error.
    function _call(args, callback) {
        if (!root.daemonAvailable) {
            if (callback) callback(null);
            return;
        }
        // Stash the callback on the singleton — Quickshell.Io.Process
        // does not accept dynamic properties, so we can't write
        // `proc._callback = …`.
        root._pendingCallback = callback;
        callProc.command = ["mirai"].concat(args);
        callProc.running = true;
    }

    // Last one-shot callback, consumed by callProc.stdout.onStreamFinished.
    property var _pendingCallback: null
    property Process callProc: Process {
        id: callProcImpl
        stdout: StdioCollector {
            id: callStdout
            onStreamFinished: {
                var cb = root._pendingCallback;
                root._pendingCallback = null;
                var text = (callStdout.text || "").trim();
                if (!text) {
                    if (cb) cb(null);
                    return;
                }
                // Mirai prints plain text for `logs`; for everything else
                // a single line of JSON. Try JSON first, fall back to string.
                try {
                    var parsed = JSON.parse(text.split("\n")[0]);
                    if (cb) cb(parsed);
                } catch (e) {
                    if (cb) cb({ raw: text });
                }
            }
        }
        stderr: StdioCollector {
            id: callStderr
            onStreamFinished: {
                var err = (callStderr.text || "").trim();
                if (err) {
                    root.lastError = err.split("\n")[0];
                }
            }
        }
        running: false
    }

    // ── Status refresh (called by pollTimer and after every action) ──
    function refreshStatus() {
        root._call(["status"], function(d) {
            if (!d) {
                root.daemonRunning = false;
                return;
            }
            root.daemonRunning = true;
            root.daemonError = "";

            // `mirai status` returns the full state object.
            root.mode = d.mode || "idle";
            root.statusMessage = d.message || (d.mode === "idle" ? "Idle" : "Active");
            root.daemonVersion = d.version || root.daemonVersion || "";

            if (d.displays && Array.isArray(d.displays)) {
                root.displays = d.displays;
            }

            if (d.sink) {
                root.receiving = !!d.sink.running;
                if (d.sink.friendly_name !== undefined) {
                    root.sinkFriendlyName = d.sink.friendly_name || "Mirai Display";
                }
                if (Array.isArray(d.sink.links)) {
                    root.sinkLinkCount = d.sink.links.length;
                }
            } else {
                root.receiving = false;
            }

            if (d.source) {
                root.streaming = !!d.source.streaming;
                if (d.source.sink_id !== undefined) root.activeSinkId = d.source.sink_id;
                if (d.source.sink_name !== undefined) root.activeSinkName = d.source.sink_name;
                if (d.source.display !== undefined) root.activeDisplay = d.source.display;
            } else {
                root.streaming = false;
                root.activeSinkId = "";
                root.activeSinkName = "";
            }

            if (d.error) {
                root.lastError = d.error;
            } else if (root.streaming || root.receiving) {
                root.lastError = "";
            }

            // Auto-populate preferredDisplay on first successful poll so
            // the source panel has a sensible default.
            if (!root.preferredDisplay && root.displays.length > 0) {
                var primary = null;
                for (var i = 0; i < root.displays.length; i++) {
                    if (root.displays[i].primary) { primary = root.displays[i].name; break; }
                }
                root.preferredDisplay = primary || root.displays[0].name;
            }

            root.initialized = true;
        });
    }

    // ── Public API ──

    // Ask the system to bring up the Mirai daemon.
    //
    // For source/cast mode the daemon runs as the regular user — no
    // privilege escalation needed. Sink mode (this PC as a Miracast
    // display) needs Wi-Fi P2P group ownership, which requires root;
    // the user has to run `sudo mirai daemon` themselves for that.
    //
    // We deliberately do NOT call pkexec from this Process: pkexec
    // requires an open controlling terminal for the password prompt,
    // which a Quickshell.Io.Process does NOT have, so the call always
    // fails with exit 127 ("Error creating textual authentication
    // agent: No such device"). Better to start as the user and let
    // them escalate manually only when needed.
    function startDaemon() {
        if (root.daemonRunning) {
            root.refreshStatus();
            return;
        }
        root.daemonError = "Starting mirai daemon…";
        var proc = daemonStartProc;
        proc.running = true;
    }

    property Process daemonStartProc: Process {
        // Strategy:
        //   1. systemd-user mirai.service (if installed) — survives restarts.
        //   2. Otherwise: `mirai daemon --foreground` with setsid+nohup.
        //
        // Why --foreground: the bare `mirai daemon` invokes the CLI's
        // start_daemon() which prepends pkexec when not root. pkexec needs
        // a TTY for the password prompt and dies with exit 127 in
        // non-interactive contexts (Quickshell.Io.Process, nohup, systemd,
        // etc.). `--foreground` skips start_daemon and runs daemon.main()
        // directly, which is what we want.
        //
        // Why setsid+nohup: the QML Process is short-lived — once the bash
        // command returns, the bash process is reaped. Without detach, the
        // foreground daemon would die with it. setsid puts the daemon in
        // its own session, nohup ignores SIGHUP, and `disown` removes it
        // from this shell's job table.
        command: ["bash", "-c",
            "if [ -f ~/.config/systemd/user/mirai.service ] && command -v systemctl >/dev/null 2>&1 && " +
            "   ! systemctl --user is-active mirai.service >/dev/null 2>&1; then " +
            "  systemctl --user start mirai.service; " +
            "  sleep 1; " +
            "  [ -S /tmp/mirai.sock ] && exit 0 || exit 1; " +
            "else " +
            "  setsid nohup /usr/local/bin/mirai daemon --foreground </dev/null >/tmp/mirai-qml.log 2>&1 & " +
            "  disown; " +
            "  for i in 1 2 3 4 5 6 7 8 9 10; do " +
            "    [ -S /tmp/mirai.sock ] && exit 0; " +
            "    sleep 0.3; " +
            "  done; " +
            "  exit 1; " +
            "fi"]
        running: false
        onExited: code => {
            if (code === 0) {
                // Give the daemon a moment to bind the socket, then poll.
                // Guard against shell teardown — if the user quits the
                // shell while a deferred callback is still pending, the
                // pollTimer may already be destroyed by the time we get
                // here, and `root.pollTimer.start()` would crash with
                // 'Cannot call method start of undefined'.
                Qt.callLater(function() {
                    if (!root.daemonAvailable) return;
                    root.refreshStatus();
                    if (root.pollTimer) root.pollTimer.start();
                });
            } else {
                root.daemonError = "Could not start mirai daemon (exit " + code + "). " +
                    "Try running 'mirai daemon' in a terminal, or 'sudo mirai daemon' for sink mode.";
                root.errorOccurred(root.daemonError);
            }
        }
    }

    // Discover Miracast sinks on the network.
    function scanSinks(timeoutSec) {
        if (!root.daemonRunning) {
            root.errorOccurred("mirai daemon is not running");
            return;
        }
        root.scanning = true;
        var t = timeoutSec || 10;
        var t0 = Date.now();
        root._call(["source-scan", "--timeout", t.toString()], function(d) {
            root.lastScanDurationMs = Date.now() - t0;
            root.scanning = false;
            if (!d) return;
            // Follow up with the list — some daemon versions don't include
            // them in the scan reply.
            root._call(["source-list"], function(list) {
                if (list && Array.isArray(list)) {
                    root.sinks = list;
                } else if (d.sinks && Array.isArray(d.sinks)) {
                    root.sinks = d.sinks;
                } else {
                    root.sinks = [];
                }
                if (root.sinks.length > 0) {
                    var d2 = new Date();
                    var hh = ("0" + d2.getHours()).slice(-2);
                    var mm = ("0" + d2.getMinutes()).slice(-2);
                    var ss = ("0" + d2.getSeconds()).slice(-2);
                    root.lastScanTime = hh + ":" + mm + ":" + ss;
                }
            });
        });
    }

    function clearSinks() {
        root.sinks = [];
    }

    // Cast this screen to a discovered sink.
    function connectToSink(sinkId, displayName) {
        if (!root.daemonRunning) {
            root.errorOccurred("mirai daemon is not running");
            return;
        }
        var display = displayName || root.preferredDisplay || "";
        if (display) root.preferredDisplay = display;
        root.preferredSinkId = sinkId;
        var args = ["source-connect", sinkId];
        if (display && display !== "default") {
            args.push("--display", display);
        }
        root._call(args, function(d) {
            if (d && d.error) {
                root.lastError = d.error;
                root.errorOccurred(d.error);
                return;
            }
            Qt.callLater(root.refreshStatus);
        });
    }

    // Change the display the source streams from, mid-session.
    function setDisplay(displayName) {
        if (!root.daemonRunning) return;
        root.preferredDisplay = displayName;
        root._call(["source-display", displayName], function(d) {
            if (d && d.error) {
                root.lastError = d.error;
                root.errorOccurred(d.error);
                return;
            }
            Qt.callLater(root.refreshStatus);
        });
    }

    function disconnect() {
        if (!root.daemonRunning) return;
        root._call(["source-disconnect"], function() {
            Qt.callLater(root.refreshStatus);
        });
    }

    // Make this machine a Miracast receiver.
    function startSink() {
        if (!root.daemonRunning) {
            root.errorOccurred("mirai daemon is not running");
            return;
        }
        root._call(["sink-start"], function(d) {
            if (d && d.error) {
                root.lastError = d.error;
                root.errorOccurred(d.error);
                return;
            }
            Qt.callLater(root.refreshStatus);
        });
    }

    function stopSink() {
        if (!root.daemonRunning) return;
        root._call(["sink-stop"], function() {
            Qt.callLater(root.refreshStatus);
        });
    }

    function setSinkMode(mode) {
        if (mode !== "window" && mode !== "fullscreen") return;
        root.sinkMode = mode;
        if (!root.daemonRunning) return;
        root._call(["sink-mode", mode], function() {
            Qt.callLater(root.refreshStatus);
        });
    }

    // Helper for the panel: label of the active sink (or none).
    function activeSinkLabel() {
        if (root.streaming && root.activeSinkName) return root.activeSinkName;
        if (root.streaming && root.activeSinkId) return root.activeSinkId;
        return "";
    }

    // ── Daemon control ──

    // Restart the daemon: stop all sessions, quit, then re-spawn. Used by
    // the panel's "Restart" button when a config change requires it.
    function restartDaemon() {
        if (!root.daemonAvailable) {
            root.errorOccurred("mirai binary not found");
            return;
        }
        // First try the polite path: ask the daemon to quit, then respawn.
        root._call(["quit"], function() {
            // Give the socket a moment to disappear, then respawn.
            Qt.callLater(function() {
                var proc = restartProc;
                proc.running = true;
            });
        });
    }

    property Process restartProc: Process {
        command: ["bash", "-c",
            "for i in 1 2 3 4 5 6 7 8 9 10; do " +
            "  [ ! -S /tmp/mirai.sock ] && break; " +
            "  sleep 0.3; " +
            "done; " +
            "setsid nohup /usr/local/bin/mirai daemon --foreground </dev/null >/tmp/mirai-qml.log 2>&1 & " +
            "disown; " +
            "for i in 1 2 3 4 5 6 7 8 9 10; do " +
            "  [ -S /tmp/mirai.sock ] && exit 0; " +
            "  sleep 0.3; " +
            "done; " +
            "exit 1;"]
        running: false
        onExited: code => {
            if (code === 0) {
                // Same teardown guard as daemonStartProc — see comment there.
                Qt.callLater(function() {
                    if (!root.daemonAvailable) return;
                    root.refreshStatus();
                    if (root.pollTimer) root.pollTimer.start();
                });
            } else {
                root.daemonError = "Restart failed (exit " + code + ")";
                root.errorOccurred(root.daemonError);
            }
        }
    }

    // Stop the daemon entirely (used by the panel's "Stop daemon" button).
    function stopDaemon() {
        if (!root.daemonRunning) return;
        root._call(["quit"], function() {
            root.daemonRunning = false;
            root.streaming = false;
            root.receiving = false;
        });
    }

    // ── Logs ──

    // Pull the last N log lines from the daemon. Mirai logs are plain
    // text (one per line), so we parse them into structured records.
    function loadRecentLogs(n) {
        if (!root.daemonRunning) return;
        root.logsLoading = true;
        var count = n || 20;
        root._call(["logs", "-n", String(count)], function(d) {
            root.logsLoading = false;
            if (!d) {
                root.recentLogs = [];
                return;
            }
            // `mirai logs` prints raw text, not JSON — we receive it as
            // { raw: "..." } from the fallback parser.
            var raw = d.raw !== undefined ? d.raw : (d.text || "");
            var lines = String(raw).split("\n").filter(function(l) { return l.trim().length > 0; });
            var out = [];
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i];
                // Expected format: "2026-06-16 11:51:29,880 [INFO] mirai: ..."
                var m = line.match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),\d+\s+\[(\w+)\]\s+(.*)$/);
                if (m) {
                    out.push({ ts: m[1], level: m[2], msg: m[3] });
                } else {
                    out.push({ ts: "", level: "LOG", msg: line });
                }
            }
            root.recentLogs = out;
        });
    }

    // ── Notifications ──

    // Show a quick OSD-style notification via the existing Notifications
    // singleton if present.
    function notify(summary, body) {
        if (typeof Notifications !== "undefined" && Notifications.notifyInternal) {
            Notifications.notifyInternal({ summary: summary, body: body || "", expireTimeout: 3000, popup: true });
        }
    }
}
