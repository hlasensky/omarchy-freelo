import QtQuick
import Quickshell
import Quickshell.Io

// Freelo data service. Shells out to freelo-cli (the official CLI), which
// owns auth (OS keyring) and the API surface — same delegation the GitHub
// bar widget makes to `gh`. The helper script aggregates one dashboard
// payload; this item schedules it and runs individual write actions.
Item {
    id: root

    property var settings: ({})
    property int refreshIntervalSec: 30
    property bool loading: false
    property string state: "loading"
    property string message: "Loading Freelo…"
    property var projects: []
    property var tasklists: []
    property var tasks: []
    property var tracking: null
    property string _stdout: ""
    property string _stderr: ""
    property bool refreshQueued: false
    readonly property bool busy: actionProcess.running

    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null || value === "" ? fallback : value;
    }

    readonly property string selectedProjectId: String(setting("selectedProjectId", ""))
    readonly property string selectedTasklistId: String(setting("selectedTasklistId", ""))

    function helperPath() {
        return Qt.resolvedUrl("omarchy-freelo-refresh").toString().replace(/^file:\/\//, "");
    }

    function refresh() {
        if (fetchProcess.running || actionProcess.running) {
            refreshQueued = true;
            return;
        }
        refreshQueued = false;
        loading = true;
        _stdout = "";
        _stderr = "";
        const args = [helperPath()];
        if (selectedProjectId !== "")
            args.push("--project", selectedProjectId);
        fetchProcess.command = args;
        fetchProcess.running = true;
    }

    function apply(raw) {
        try {
            const data = JSON.parse(String(raw || ""));
            state = String(data.state || "error");
            message = String(data.message || "");
            projects = Array.isArray(data.projects) ? data.projects : [];
            tasklists = Array.isArray(data.tasklists) ? data.tasklists : [];
            tasks = Array.isArray(data.tasks) ? data.tasks : [];
            tracking = data.tracking && typeof data.tracking === "object" ? data.tracking : null;
        } catch (error) {
            state = "error";
            message = "Freelo returned an unreadable response.";
        }
    }

    // Generic write-action runner shared by create/edit/finish/delete/start/
    // stop, so each doesn't need its own near-identical Process block.
    function runAction(args, onDone) {
        if (actionProcess.running)
            return;
        actionProcess.onDoneCallback = onDone || null;
        actionProcess.command = ["freelo"].concat(args).concat(["--agent"]);
        actionProcess.running = true;
    }

    function createTask(name, dueDate, priority) {
        if (selectedProjectId === "" || selectedTasklistId === "" || String(name || "").trim() === "")
            return;
        const args = ["tasks", "create", "--project", selectedProjectId, "--tasklist", selectedTasklistId, "--name", String(name).trim()];
        if (dueDate)
            args.push("--due-date", dueDate);
        if (priority)
            args.push("--priority", priority);
        runAction(args);
    }

    function editTaskName(taskId, name) {
        if (String(name || "").trim() === "")
            return;
        runAction(["tasks", "edit", String(taskId), "--name", String(name).trim()]);
    }

    function finishTask(taskId) {
        runAction(["tasks", "finish", String(taskId)]);
    }

    function deleteTask(taskId) {
        // No dedicated "tasks delete" subcommand exists in freelo-cli; the raw
        // `api` passthrough is what it documents for endpoints without one.
        runAction(["api", "delete", "/task/" + String(taskId)]);
    }

    function startTracking(taskId) {
        // Switching the active tracker is not destructive (the previous entry's
        // time is preserved server-side once stopped), so this always replaces
        // whatever is running without asking first — like any stopwatch app.
        if (root.tracking && root.tracking.active) {
            runAction(["tracking", "stop"], function () {
                runAction(["tracking", "start", "--task", String(taskId)], function () {
                    tracking = {
                        active: true,
                        server: {
                            task: {
                                id: taskId,
                                name: tasks.find(t => String(t.id) === String(taskId))?.name || ""
                            },
                            date_reported: new Date().toISOString()
                        }
                    };
                });
            });
        } else {
            runAction(["tracking", "start", "--task", String(taskId)], function () {
                tracking = {
                    active: true,
                    server: {
                        task: {
                            id: taskId,
                            name: tasks.find(t => String(t.id) === String(taskId))?.name || ""
                        },
                        date_reported: new Date().toISOString()
                    }
                };
            });
        }
    }

    function stopTracking() {
        runAction(["tracking", "stop"], function () {
            tracking = {
                active: false,
                server: null
            };
        });
    }

    visible: false

    Timer {
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: fetchProcess

        running: false
        command: []
        onExited: function (exitCode) {
            root.loading = false;
            const stdout = String(output.text || root._stdout || "");
            const stderr = String(errors.text || root._stderr || "").trim();
            if (stdout.trim() !== "") {
                root.apply(stdout);
            } else {
                root.state = "error";
                root.message = stderr !== "" ? stderr : "Freelo data refresh failed.";
            }
            if (root.refreshQueued) {
                root.refreshQueued = false;
                Qt.callLater(root.refresh);
            }
        }

        stdout: StdioCollector {
            id: output

            waitForEnd: true
            onStreamFinished: root._stdout = text
        }

        stderr: StdioCollector {
            id: errors

            waitForEnd: true
            onStreamFinished: root._stderr = text
        }
    }

    Process {
        id: actionProcess

        property var onDoneCallback: null

        running: false
        command: []
        onExited: function (exitCode) {
            const callback = actionProcess.onDoneCallback;
            actionProcess.onDoneCallback = null;
            if (callback)
                callback();
            root.refreshQueued = false;
            Qt.callLater(root.refresh);
        }

        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            waitForEnd: true
        }
    }
}
