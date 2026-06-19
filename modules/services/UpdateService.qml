pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.config

Singleton {
    id: root

    readonly property string installPath: Quickshell.env("HOME") + "/.local/src/nothingless"
    readonly property string cliPath: installPath + "/cli.sh"
    readonly property string changelogUrl: "https://github.com/Leriart/NothingLess/releases"
    readonly property string cacheFile: Quickshell.env("HOME") + "/.cache/nothingless/update_check.json"

    property string lastDetectedHash: ""
    property string currentLocalHash: ""
    property string remoteHash: ""
    property string remoteSubject: ""
    property int behindCount: 0
    property double lastCheckTime: 0
    property double nextCheckTime: 0

    property bool updateAvailable: false
    property bool checking: false

    readonly property int checkIntervalMs: Config.system.updateService ? Config.system.updateService.checkIntervalMs : 3600000

    function saveCache() {
        const data = {
            lastCheckTime: root.lastCheckTime,
            nextCheckTime: root.nextCheckTime,
            lastDetectedHash: root.lastDetectedHash
        };
        cacheFileView.setText(JSON.stringify(data));
    }

    FileView {
        id: cacheFileView
        path: root.cacheFile
        onLoaded: {
            try {
                const content = text();
                if (content && content.trim() !== "") {
                    const data = JSON.parse(content);
                    root.lastCheckTime = data.lastCheckTime || 0;
                    root.nextCheckTime = data.nextCheckTime || 0;
                    root.lastDetectedHash = data.lastDetectedHash || data.lastDetectedVersion || "";
                    // Reset if cache is too far in the future (e.g. clock skew)
                    if (root.nextCheckTime > Date.now() + root.checkIntervalMs * 2) {
                        root.nextCheckTime = Date.now();
                    }
                } else {
                    root.nextCheckTime = Date.now();
                }
            } catch (e) {
                root.nextCheckTime = Date.now();
            }
        }
    }

    // Only start checking once config is fully loaded
    Connections {
        target: Config
        function onInitialLoadCompleteChanged() {
            if (Config.initialLoadComplete && !root._started) {
                root._started = true;
                startupDelay.running = true;
            }
        }
    }

    // Fallback: config may already be loaded when singleton is created
    Timer {
        id: configReadyFallback
        interval: 3000
        running: true
        onTriggered: {
            if (!root._started && Config && Config.initialLoadComplete) {
                root._started = true;
                startupDelay.running = true;
            }
        }
    }

    property bool _started: false

    Timer {
        id: startupDelay
        interval: 5000
        running: false
        onTriggered: {
            checkTimer.running = true;
            if (!root.checking) {
                // Safe check: config may still be null-protected
                try {
                    if (Config && Config.system && Config.system.updateService && Config.system.updateService.enabled) {
                        checkUpdates();
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        id: checkTimer
        interval: 60000
        running: false
        repeat: true
        onTriggered: {
            try {
                if (!Config || !Config.system || !Config.system.updateService || !Config.system.updateService.enabled) return;
            } catch (e) { return; }
            if (root.checking) return;
            const now = Date.now();
            if (now >= root.nextCheckTime) checkUpdates();
        }
    }

    function checkUpdates() {
        try {
            if (!Config || !Config.system || !Config.system.updateService || !Config.system.updateService.enabled) return;
        } catch (e) { return; }
        if (root.checking) return;
        root.checking = true;
        root.updateAvailable = false;

        // Step 1: get local HEAD hash
        localHashProcess.running = true;
    }

    function checkNow() {
        root.checking = true;
        root.updateAvailable = false;
        localHashProcess.running = true;
    }

    // ── Step 1: git rev-parse HEAD ──
    property Process localHashProcess: Process {
        id: localHashProcess
        command: ["git", "-C", root.installPath, "rev-parse", "HEAD"]
        running: false
        stdout: StdioCollector { id: localCollector }
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0 || !localCollector.text.trim()) {
                root.checking = false;
                return;
            }
            root.currentLocalHash = localCollector.text.trim();

            // Step 2: git ls-remote origin HEAD
            remoteHashProcess.running = true;
        }
    }

    // ── Step 2: git ls-remote origin HEAD ──
    property Process remoteHashProcess: Process {
        id: remoteHashProcess
        command: ["git", "-C", root.installPath, "ls-remote", "origin", "HEAD"]
        running: false
        stdout: StdioCollector { id: remoteCollector }
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0 || !remoteCollector.text.trim()) {
                root.checking = false;
                return;
            }
            const line = remoteCollector.text.trim();
            const parts = line.split(/\s+/);
            if (parts.length < 1) {
                root.checking = false;
                return;
            }
            root.remoteHash = parts[0];

            if (root.remoteHash === root.currentLocalHash) {
                root.updateAvailable = false;
                finishCheck();
                return;
            }

            // Step 3: count commits behind
            behindCountProcess.command = ["git", "-C", root.installPath,
                "rev-list", "--count", root.currentLocalHash + ".." + root.remoteHash];
            behindCountProcess.running = true;
        }
    }

    // ── Step 3: count how many commits behind ──
    property Process behindCountProcess: Process {
        id: behindCountProcess
        command: []
        running: false
        stdout: StdioCollector { id: behindCollector }
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode === 0) {
                root.behindCount = parseInt(behindCollector.text.trim()) || 0;
            } else {
                root.behindCount = 0;
            }

            if (root.behindCount > 0) {
                root.updateAvailable = true;

                // Step 4: get subject of the top remote commit for the notification
                subjectProcess.command = ["git", "-C", root.installPath,
                    "log", "-1", "--format=%s", root.remoteHash];
                subjectProcess.running = true;
            } else {
                root.updateAvailable = false;
                finishCheck();
            }
        }
    }

    // ── Step 4: get commit subject ──
    property Process subjectProcess: Process {
        id: subjectProcess
        command: []
        running: false
        stdout: StdioCollector { id: subjectCollector }
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode === 0) {
                root.remoteSubject = subjectCollector.text.trim();
            }

            if (root.remoteHash !== root.lastDetectedHash || !isNotificationActive()) {
                root.lastDetectedHash = root.remoteHash;
                saveCache();
                sendUpdateNotification();
            }

            finishCheck();
        }
    }

    function finishCheck() {
        root.checking = false;
        root.lastCheckTime = Date.now();
        if (root.nextCheckTime <= Date.now()) {
            root.nextCheckTime = Date.now() + root.checkIntervalMs;
        }
        root.saveCache();
    }

    function isNotificationActive() {
        if (typeof Notifications === "undefined" || !Notifications.list) return false;
        for (let i = 0; i < Notifications.list.length; i++) {
            const notif = Notifications.list[i];
            if (notif && notif.appName === "NothingLess Update") return true;
        }
        return false;
    }

    function sendUpdateNotification() {
        const shortLocal = root.currentLocalHash.substring(0, 7);
        const shortRemote = root.remoteHash.substring(0, 7);

        const commitInfo = root.behindCount === 1
            ? root.remoteSubject.substring(0, 280)
            : (root.behindCount + " commits behind — " + root.remoteSubject.substring(0, 240));

        try {
            Notifications.notifyInternal({
                "appName": "NothingLess Update",
                "summary": "Update Available  " + shortLocal + " → " + shortRemote,
                "body": commitInfo,
                "urgency": NotificationUrgency.Normal,
                "historyPriority": 90,
                "replaceKey": "nothingless-update",
                "expireTimeout": 0,
                "actions": [
                    {"identifier": "update-now", "text": "Update Now"},
                    {"identifier": "changelog", "text": "Changelog"},
                    {"identifier": "later", "text": "Later"}
                ],
                "actionHandlers": {
                    "update-now": function() { root.performUpdate(); },
                    "changelog": function() {
                        Quickshell.execDetached(["xdg-open", root.changelogUrl]);
                    },
                    "later": function(id) {
                        Notifications.discardNotification(id);
                        root.nextCheckTime = Date.now() + 8 * 3600000;
                        root.saveCache();
                    }
                }
            });
        } catch (e) {
            // Notification system might not be ready yet
        }
    }

    function performUpdate() {
        Quickshell.execDetached(["bash", "-c",
            "nohup " + root.cliPath + " update --pull >/dev/null 2>&1 &"]);
    }

    Component.onDestruction: {
        localHashProcess.running = false;
        remoteHashProcess.running = false;
        behindCountProcess.running = false;
        subjectProcess.running = false;
    }
}
