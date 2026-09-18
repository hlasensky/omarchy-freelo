pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Freelo dropdown: project/tasklist switcher, quick-add, and the open task
// list with per-row start-tracking/finish/rename/delete. Structurally
// modeled on robzolkos.github/Panel.qml, much smaller since there is no
// multi-section dashboard to lay out.
Panel {
    id: root
    moduleName: "hl.freelo"
    ipcTarget: "hl.freelo"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    property var service: null

    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property color urgent: bar ? bar.urgent : Color.urgent
    readonly property color dim: Qt.darker(foreground, 1.55)
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

    property string taskFilter: ""
    property string selectedTaskTasklistId: ""
    property int spinnerFrame: 0
    property bool tabSwitchFlash: false
    readonly property var spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    property string quickAddText: ""
    property string renamingTaskId: ""
    property string renameText: ""
    property string pendingDeleteId: ""
    property string pendingDeleteName: ""

    readonly property var projectOptions: {
        const rows = [];
        const all = service ? service.projects : [];
        for (let i = 0; i < all.length; i++) {
            const p = all[i];
            rows.push({
                value: p.id,
                label: p.name || ("Project " + p.id)
            });
        }
        return rows;
    }

    readonly property var tasklistOptions: {
        const rows = [];
        const all = service ? service.tasklists : [];
        for (let i = 0; i < all.length; i++) {
            const t = all[i];
            rows.push({
                value: t.id,
                label: t.name || ("Tasklist " + t.id)
            });
        }
        return rows;
    }

    // Tabs above the task list — filters by tasklist instead of showing
    // every open task in one flat list. "All" (empty value) plus one tab
    // per tasklist, reusing the same list tasklistOptions already builds.
    readonly property var taskTabOptions: [
        {
            value: "",
            label: "All"
        }
    ].concat(root.tasklistOptions)

    function isTaskFinished(task) {
        return !!(task && task.finished);
    }

    function dueDateLabel(task) {
        const raw = String((task && task.dueDate) || "");
        if (raw === "")
            return "";
        const datePart = raw.split(" ")[0];
        const d = new Date(datePart);
        if (isNaN(d.getTime()))
            return datePart;
        return Qt.formatDate(d, "d.M.");
    }

    readonly property var openTasks: {
        const all = service ? service.tasks : [];
        const needle = String(taskFilter || "").trim().toLowerCase();
        const rows = [];
        for (let i = 0; i < all.length; i++) {
            const task = all[i];
            if (isTaskFinished(task))
                continue;
            if (root.selectedTaskTasklistId !== "" && task.tasklistId !== root.selectedTaskTasklistId)
                continue;
            if (needle !== "" && task.name.toLowerCase().indexOf(needle) === -1)
                continue;
            rows.push(task);
        }
        // Oldest first, same order Freelo's own task list shows them in.
        rows.sort((a, b) => {
            const ta = Date.parse(a.createdAt);
            const tb = Date.parse(b.createdAt);
            if (!isFinite(ta) || !isFinite(tb))
                return 0;
            return ta - tb;
        });
        return rows;
    }

    function isOverdue(task) {
        const raw = String((task && task.dueDate) || "");
        if (raw === "")
            return false;
        const d = new Date(raw.split(" ")[0]);
        if (isNaN(d.getTime()))
            return false;
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        d.setHours(0, 0, 0, 0);
        return d.getTime() < today.getTime();
    }

    function workerLabel(task) {
        const w = task && task.worker;
        if (!w || typeof w !== "object")
            return "";
        const name = String(w.name || w.fullname || w.full_name || "").trim();
        return name === "" ? "" : name.split(" ")[0];
    }

    // One line combining due date, assignee, and (only when the "All" tab
    // is active, since a specific tab already implies the tasklist) which
    // tasklist the task is on — the per-row detail the old stacked-Text
    // layout couldn't fit without three separate lines per row.
    function metaLabel(task) {
        const parts = [];
        const due = dueDateLabel(task);
        if (due !== "")
            parts.push(due);
        const worker = workerLabel(task);
        if (worker !== "")
            parts.push(worker);
        if (root.selectedTaskTasklistId === "" && task && task.tasklistName)
            parts.push(task.tasklistName);
        return parts.join("  ·  ");
    }

    function priorityLabel(priority) {
        const p = String(priority || "").toLowerCase();
        if (p === "h" || p === "high")
            return "H";
        if (p === "m" || p === "medium")
            return "M";
        if (p === "l" || p === "low")
            return "L";
        return "";
    }

    function priorityColor(priority) {
        const p = String(priority || "").toLowerCase();
        if (p === "h" || p === "high")
            return root.urgent;
        return root.dim;
    }

    // Applied locally first so the panel and bar label update on the click
    // itself; the shell.json write comes back through the bar as the same
    // value. Same shape as omarchy.clock's Panel.qml persistSettings().
    function persistSettings(values) {
        const entry = {
            id: root.moduleName
        };
        for (let existing in root.settings)
            if (existing !== "id")
                entry[existing] = root.settings[existing];
        for (let key in values)
            entry[key] = values[key];

        root.settings = entry;
        if (root.hostWidget && "settings" in root.hostWidget)
            root.hostWidget.settings = entry;
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry);
    }

    function selectProject(id) {
        // A tasklist belongs to exactly one project, so a stale tasklist id
        // would otherwise let quick-add silently target the wrong project,
        // and a stale tab would show an empty list until manually reset.
        persistSettings({
            selectedProjectId: id,
            selectedTasklistId: ""
        });
        root.selectedTaskTasklistId = "";
        if (service)
            service.refresh();
    }

    function selectTasklist(id) {
        persistSettings({
            selectedTasklistId: id
        });
    }

    // Tasklist tabs filter the already-fetched task list locally (no
    // network round-trip), so there's no loading state to animate off of --
    // this flash gives the switch the same brief "content changed" beat the
    // loading spinner gives a real refresh.
    function selectTaskTab(id) {
        root.selectedTaskTasklistId = id;
        root.tabSwitchFlash = true;
        tabFlashTimer.restart();
    }

    function submitQuickAdd() {
        const name = String(quickAddText || "").trim();
        if (name === "" || !service)
            return;
        service.createTask(name, "", "");
        quickAddText = "";
    }

    function beginRename(task) {
        renamingTaskId = task.id;
        renameText = task.name;
    }

    function commitRename() {
        if (renamingTaskId === "" || !service)
            return;
        service.editTaskName(renamingTaskId, renameText);
        renamingTaskId = "";
        renameText = "";
    }

    function cancelRename() {
        renamingTaskId = "";
        renameText = "";
    }

    function requestDelete(task) {
        pendingDeleteId = task.id;
        pendingDeleteName = task.name || ("task " + task.id);
    }

    function confirmDelete() {
        if (pendingDeleteId !== "" && service)
            service.deleteTask(pendingDeleteId);
        pendingDeleteId = "";
        pendingDeleteName = "";
    }

    function cancelDelete() {
        pendingDeleteId = "";
        pendingDeleteName = "";
    }

    function refresh() {
        if (service)
            service.refresh();
    }

    function open() {
        refresh();
        root.controller.show();
        Qt.callLater(function () {
            keyCatcher.forceActiveFocus();
        });
    }

    function close() {
        root.controller.hide();
    }

    function toggle() {
        opened ? close() : open();
    }

    function openTask(task) {
        Quickshell.execDetached(["omarchy-launch-browser", "https://app.freelo.io/task/" + String(task.id)]);
    }

    Timer {
        interval: 80
        repeat: true
        running: !!(root.service && root.service.loading)
        onTriggered: root.spinnerFrame = (root.spinnerFrame + 1) % root.spinnerFrames.length
    }

    Timer {
        id: tabFlashTimer
        interval: 120
        onTriggered: root.tabSwitchFlash = false
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(420))
        contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            z: root.pendingDeleteId !== "" ? 20 : 0
            blocked: quickAdd.activeFocus || filterField.activeFocus || root.renamingTaskId !== "" || root.pendingDeleteId !== ""
            onCloseRequested: root.close()
            onTextKey: function (text) {
                if (text === "r" || text === "R")
                    root.refresh();
                else if (text === "/")
                    Qt.callLater(function () {
                        filterField.forceActiveFocus();
                    });
            }

            ConfirmDialog {
                anchors.fill: parent
                z: 10
                opened: root.pendingDeleteId !== ""
                message: "Delete \"" + root.pendingDeleteName + "\"? This cannot be undone."
                confirmText: "Delete"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onConfirmed: root.confirmDelete()
                onCanceled: root.cancelDelete()
            }

            Flickable {
                id: panelFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                // Flickable's own wheel-to-flick conversion is heavily damped and
                // reads as sluggish for a tall task list. Same fix as tabsFlick's
                // WheelHandler below: move contentY directly off the wheel delta.
                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function (event) {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                        panelFlick.contentY = Math.max(0, Math.min(Math.max(0, panelFlick.contentHeight - panelFlick.height), panelFlick.contentY - delta));
                    }
                }

                Column {
                    id: content
                    width: panelFlick.width
                    spacing: Style.space(12)

                    PanelHero {
                        width: parent.width
                        title: "Freelo"
                        meta: {
                            if (!root.service)
                                return "";
                            if (root.service.loading)
                                return "Refreshing…";
                            if (root.service.state !== "ready")
                                return root.service.message;
                            if (root.service.tracking && root.service.tracking.active) {
                                const name = root.service.tracking.taskName;
                                return name !== "" ? ("Tracking " + name) : "Tracking";
                            }
                            return "Not tracking";
                        }
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        iconComponent: Component {
                            Text {
                                text: ""
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.display
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Button {
                        visible: root.service && root.service.tracking && root.service.tracking.active
                        width: parent.width
                        text: "■  Stop tracking"
                        bordered: true
                        foreground: root.urgent
                        fontFamily: root.fontFamily
                        onClicked: if (root.service)
                            root.service.stopTracking()
                    }

                    BorderSurface {
                        visible: !root.service || root.service.state !== "ready"
                        width: parent.width
                        implicitHeight: statusText.implicitHeight + Style.space(20)
                        color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
                        borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35), 1)
                        radius: Style.cornerRadius

                        Text {
                            id: statusText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Style.space(10)
                            text: root.service ? root.service.message : "Loading…"
                            color: root.urgent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: Text.WordWrap
                        }
                    }

                    PanelSeparator {
                        foreground: root.foreground
                    }

                    Dropdown {
                        width: parent.width
                        label: "PROJECT"
                        value: root.service ? root.service.selectedProjectId : ""
                        options: root.projectOptions
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        onChanged: function (value) {
                            root.selectProject(value);
                        }
                    }

                    Dropdown {
                        width: parent.width
                        label: "TASKLIST (for quick-add)"
                        value: root.service ? root.service.selectedTasklistId : ""
                        options: root.tasklistOptions
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        enabled: root.tasklistOptions.length > 0
                        onChanged: function (value) {
                            root.selectTasklist(value);
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: Style.space(8)

                        TextField {
                            id: quickAdd
                            Layout.fillWidth: true
                            foreground: root.foreground
                            placeholderText: "Add a task…"
                            text: root.quickAddText
                            enabled: root.service && root.service.selectedProjectId !== "" && root.service.selectedTasklistId !== ""
                            onTextChanged: root.quickAddText = text
                            Keys.onReturnPressed: root.submitQuickAdd()
                        }

                        Button {
                            text: "Add"
                            bordered: true
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            enabled: quickAdd.enabled
                            onClicked: root.submitQuickAdd()
                        }
                    }

                    PanelSeparator {
                        foreground: root.foreground
                    }

                    RowLayout {
                        width: parent.width
                        spacing: Style.space(6)

                        PanelSectionHeader {
                            Layout.fillWidth: true
                            text: "OPEN TASKS  " + root.openTasks.length
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }

                        Text {
                            visible: !!(root.service && root.service.loading)
                            textFormat: Text.PlainText
                            text: root.spinnerFrames[root.spinnerFrame]
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                        }
                    }

                    Flickable {
                        id: tabsFlick
                        width: parent.width
                        implicitHeight: taskTabs.implicitHeight
                        contentWidth: taskTabs.implicitWidth
                        contentHeight: taskTabs.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.HorizontalFlick
                        interactive: contentWidth > width

                        // Flickable only maps its own axis to flick/drag,
                        // not the mouse wheel — a vertical wheel scroll
                        // here would otherwise fall through to panelFlick
                        // and scroll the whole panel instead of the tabs.
                        WheelHandler {
                            target: null
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: function (event) {
                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                                tabsFlick.contentX = Math.max(0, Math.min(tabsFlick.contentWidth - tabsFlick.width, tabsFlick.contentX - delta));
                            }
                        }

                        ButtonGroup {
                            id: taskTabs
                            options: root.taskTabOptions
                            value: root.selectedTaskTasklistId
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onChanged: function (value) {
                                root.selectTaskTab(value);
                            }
                        }
                    }

                    TextField {
                        id: filterField
                        width: parent.width
                        foreground: root.foreground
                        placeholderText: "Filter tasks  /"
                        text: root.taskFilter
                        onTextChanged: root.taskFilter = text
                        Keys.onEscapePressed: function (event) {
                            root.taskFilter = "";
                            keyCatcher.forceActiveFocus();
                            event.accepted = true;
                        }
                    }

                    Column {
                        id: resultsArea
                        width: parent.width
                        spacing: Style.space(4)
                        // Dips while a fetch is in flight or a tab/project switch just
                        // landed, so stale rows never sit there looking current.
                        opacity: (!!(root.service && root.service.loading) || root.tabSwitchFlash) ? 0.35 : 1.0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.OutQuad
                            }
                        }

                        Text {
                            visible: root.openTasks.length === 0
                            width: parent.width
                            text: {
                                if (root.service && root.service.loading && root.openTasks.length === 0)
                                    return "Loading tasks…";
                                return (root.service && root.service.selectedProjectId === "") ? "Pick a project above." : "No open tasks.";
                            }
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Repeater {
                            model: root.openTasks

                            CursorSurface {
                                id: taskRow
                                required property var modelData
                                property bool hovered: false
                                readonly property bool isTracking: !!(root.service && root.service.tracking && root.service.tracking.active && root.service.tracking.taskId === modelData.id)
                                readonly property bool actionsVisible: hovered || root.renamingTaskId === String(modelData.id)
                                width: parent.width
                                foreground: root.foreground
                                current: isTracking
                                implicitHeight: rowLayout.implicitHeight + Style.space(14)

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: taskRow.hovered = containsMouse
                                    onClicked: root.openTask(taskRow.modelData)
                                }

                                RowLayout {
                                    id: rowLayout
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Style.space(9)
                                    anchors.rightMargin: Style.space(9)
                                    spacing: Style.space(8)

                                    TextField {
                                        id: renameField
                                        visible: root.renamingTaskId === String(taskRow.modelData.id)
                                        Layout.fillWidth: true
                                        foreground: root.foreground
                                        text: root.renameText
                                        onTextChanged: root.renameText = text
                                        Keys.onReturnPressed: root.commitRename()
                                        Keys.onEscapePressed: root.cancelRename()
                                    }

                                    ColumnLayout {
                                        visible: root.renamingTaskId !== String(taskRow.modelData.id)
                                        Layout.fillWidth: true
                                        spacing: Style.space(2)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(6)

                                            BorderSurface {
                                                readonly property string label: root.priorityLabel(taskRow.modelData.priority)
                                                readonly property color tint: root.priorityColor(taskRow.modelData.priority)
                                                visible: label !== ""
                                                Layout.alignment: Qt.AlignVCenter
                                                implicitWidth: priorityText.implicitWidth + Style.space(8)
                                                implicitHeight: priorityText.implicitHeight + Style.space(3)
                                                radius: Style.cornerRadius
                                                color: Qt.rgba(tint.r, tint.g, tint.b, 0.16)
                                                borderSpec: Border.flat(Qt.rgba(tint.r, tint.g, tint.b, 0.4), 1)

                                                Text {
                                                    id: priorityText
                                                    anchors.centerIn: parent
                                                    text: parent.label
                                                    textFormat: Text.PlainText
                                                    color: parent.tint
                                                    font.family: root.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: true
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: taskRow.modelData.name
                                                textFormat: Text.PlainText
                                                color: root.foreground
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.body
                                                font.bold: taskRow.isTracking
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            readonly property string label: root.metaLabel(taskRow.modelData)
                                            visible: label !== ""
                                            Layout.fillWidth: true
                                            text: label
                                            textFormat: Text.PlainText
                                            color: root.isOverdue(taskRow.modelData) ? root.urgent : root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            elide: Text.ElideRight
                                        }
                                    }

                                    RowLayout {
                                        // Stays in layout (reserves its width) even when hidden, so
                                        // showing/hiding actions on hover never reflows the row --
                                        // only opacity/enabled change, not visible.
                                        opacity: taskRow.actionsVisible ? 1 : 0
                                        enabled: taskRow.actionsVisible
                                        spacing: Style.space(4)

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: 80
                                            }
                                        }

                                        PanelActionButton {
                                            visible: !taskRow.isTracking
                                            iconText: "▶"
                                            tooltipText: "Start tracking"
                                            foreground: root.foreground
                                            fontFamily: root.fontFamily
                                            onClicked: if (root.service)
                                                root.service.startTracking(taskRow.modelData.id)
                                        }

                                        PanelActionButton {
                                            iconText: "✓"
                                            tooltipText: "Finish"
                                            foreground: root.foreground
                                            fontFamily: root.fontFamily
                                            onClicked: if (root.service)
                                                root.service.finishTask(taskRow.modelData.id)
                                        }

                                        PanelActionButton {
                                            iconText: "✎"
                                            tooltipText: "Rename"
                                            foreground: root.foreground
                                            fontFamily: root.fontFamily
                                            onClicked: {
                                                if (root.renamingTaskId === String(taskRow.modelData.id))
                                                    root.cancelRename();
                                                else
                                                    root.beginRename(taskRow.modelData);
                                            }
                                        }

                                        PanelActionButton {
                                            iconText: "✕"
                                            tooltipText: "Delete"
                                            foreground: root.foreground
                                            hoverColor: root.urgent
                                            fontFamily: root.fontFamily
                                            onClicked: root.requestDelete(taskRow.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
