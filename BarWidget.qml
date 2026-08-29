import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Freelo time-tracking + task bar widget. Left click opens the task panel;
// the bar label itself shows the live-ticking elapsed time and task name
// while a timer is running, and just the icon otherwise. Modeled on
// omarchy.clock's BarWidget.qml (bar-label root + lazily-loaded Panel.qml).
BarWidget {
  id: root
  moduleName: "hl.freelo"

  readonly property int refreshIntervalSec: {
    let value = parseInt(String(setting("refreshIntervalSec", 30)), 10)
    if (!isFinite(value)) value = 30
    return Math.max(10, Math.min(300, value))
  }

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property date now: new Date()
  readonly property bool tracking: !!(service.tracking && service.tracking.active)
  // Confirmed against a live `freelo tracking status --agent` call: an
  // active tracker nests everything under .server (.server.task.name,
  // .server.date_reported) rather than at the top level.
  readonly property string trackingTaskName: tracking
    ? String((service.tracking.server && service.tracking.server.task) ? service.tracking.server.task.name : "")
    : ""
  readonly property string trackingStartedAt: tracking
    ? String((service.tracking.server && service.tracking.server.date_reported) || "")
    : ""
  readonly property int elapsedSeconds: {
    if (!tracking || trackingStartedAt === "") return 0
    const started = Date.parse(trackingStartedAt)
    if (!isFinite(started)) return 0
    return Math.max(0, Math.floor((now.getTime() - started) / 1000))
  }

  function pad(n) { return (n < 10 ? "0" : "") + n }

  function formatElapsed(totalSeconds) {
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    return hours > 0 ? (hours + ":" + pad(minutes) + ":" + pad(seconds)) : (pad(minutes) + ":" + pad(seconds))
  }

  readonly property string displayText: tracking
    ? (" " + formatElapsed(elapsedSeconds) + (trackingTaskName !== "" ? " · " + trackingTaskName : ""))
    : ""

  function refresh() {
    service.refresh()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  // ---- Popup contract mirrored from omarchy.clock's BarWidget.qml.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    const target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = service
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Service {
    id: service
    settings: root.settings
    refreshIntervalSec: root.refreshIntervalSec
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.tracking
    onTriggered: root.now = new Date()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "hl.freelo"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    fontFamily: root.fontFamily
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tracking ? ("Tracking: " + root.trackingTaskName) : "Freelo"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.togglePanel()
    }
  }
}
