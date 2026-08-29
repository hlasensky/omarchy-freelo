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
                value: String(p.id),
                label: String(p.name || p.title || ("Project " + p.id))
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
                value: String(t.id),
                label: String(t.name || t.title || ("Tasklist " + t.id))
            });
        }
        return rows;
    }

    function isTaskFinished(task) {
        if (!task)
            return false;
        // Confirmed against a real account: freelo-cli's raw task JSON nests
        // state as { id, state } with state.state one of "active"/"finished"/…
        if (task.state && typeof task.state === "object" && String(task.state.state || "").toLowerCase() === "finished")
            return true;
        if (task.finished === true || task.is_finished === true)
            return true;
        return false;
    }

    function dueDateLabel(task) {
        const raw = String((task && (task.due_date || task.dueDate)) || "");
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
            if (needle !== "" && String(task.name || task.title || "").toLowerCase().indexOf(needle) === -1)
                continue;
            rows.push(task);
        }
        return rows;
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
        // would otherwise let quick-add silently target the wrong project.
        persistSettings({
            selectedProjectId: id,
            selectedTasklistId: ""
        });
        if (service)
            service.refresh();
    }

    function selectTasklist(id) {
        persistSettings({
            selectedTasklistId: id
        });
    }

    function submitQuickAdd() {
        const name = String(quickAddText || "").trim();
        if (name === "" || !service)
            return;
        service.createTask(name, "", "");
        quickAddText = "";
    }

    function beginRename(task) {
        renamingTaskId = String(task.id);
        renameText = String(task.name || task.title || "");
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
        pendingDeleteId = String(task.id);
        pendingDeleteName = String(task.name || task.title || ("task " + task.id));
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

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(360))
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
                                const srv = root.service.tracking.server;
                                const name = String((srv && srv.task) ? srv.task.name : "");
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

                    PanelSectionHeader {
                        width: parent.width
                        text: "OPEN TASKS  " + root.openTasks.length
                        foreground: root.foreground
                        fontFamily: root.fontFamily
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

                    Text {
                        visible: root.openTasks.length === 0
                        width: parent.width
                        text: (root.service && root.service.selectedProjectId === "") ? "Pick a project above." : "No open tasks."
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Column {
                        width: parent.width
                        spacing: Style.space(4)

                        Repeater {
                            model: root.openTasks

                            CursorSurface {
                                id: taskRow
                                required property var modelData
                                width: parent.width
                                foreground: root.foreground
                                implicitHeight: rowLayout.implicitHeight + Style.space(14)

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
                                        spacing: 0

                                        Text {
                                            visible: text !== "" || root.priorityLabel(taskRow.modelData.priority) !== ""
                                            text: root.priorityLabel(taskRow.modelData.priority)
                                            color: root.priorityColor(taskRow.modelData.priority)
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: String(taskRow.modelData.name || taskRow.modelData.title || "")
                                            textFormat: Text.PlainText
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.body
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: text !== ""
                                            Layout.fillWidth: true
                                            text: String(taskRow.modelData.tasklist_name || "")
                                            textFormat: Text.PlainText
                                            color: root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            readonly property string dueLabel: root.dueDateLabel(taskRow.modelData)
                                            visible: dueLabel !== "" && root.renamingTaskId !== String(taskRow.modelData.id)
                                            text: dueLabel
                                            color: root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                        }
                                    }

                                    PanelActionButton {
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
