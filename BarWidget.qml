import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "DiskIoModel.js" as Io

// Disk status in the bar: one harddisk glyph, tinted by the worst verdict
// across the fixed drives, hosting the CrystalDiskInfo-style detail panel.
//
// This widget reads ONE file — /var/lib/disk-status/disk-status.json,
// written by the privileged collector. It never runs smartctl and never needs
// root. If the file is missing or stale the glyph goes muted and says so:
// unknown is not good.
BarWidget {
  id: root
  moduleName: "denizkin.disk-status"

  readonly property string statePath: setting("statePath", "/var/lib/disk-status/disk-status.json")

  property var healthState: null
  property bool loadFailed: false
  property double nowMs: Date.now()

  readonly property bool stale: loadFailed || Model.isStale(healthState, nowMs)
  readonly property string verdict: (!healthState || stale) ? "unknown" : Model.overallVerdict(healthState)
  readonly property int troubled: stale ? 0 : Model.troubledCount(healthState)

  // ---- live throughput ---------------------------------------------------
  // /proc/diskstats only. Cheap kernel counters, no SMART, no root — which is
  // why this can run at 1 Hz while SMART runs at 1/1800 Hz.
  property var ioPrev: ({})
  property var ioRates: ({})
  property var ioHistory: ({})           // dev -> array of total MB/s
  property double ioPrevMs: 0
  readonly property var ioDevices: {
    var out = []
    if (!healthState) return out
    var all = (healthState.drives || []).concat(healthState.removable || [])
    for (var i = 0; i < all.length; i++) {
      var d = String(all[i].device || "").replace("/dev/", "")
      if (d) out.push(d)
    }
    return out
  }
  readonly property var ioAggregate: Io.aggregate(ioRates, ioDevices)
  readonly property real ioThreshold: {
    try { return healthState.config.thresholds.io_show_mbps || 10 } catch (e) { return 10 }
  }
  readonly property string ioText: (!stale && ioAggregate.total >= ioThreshold)
    ? Io.formatAggregate(ioAggregate) : ""

  function sampleIo(text) {
    var now = Date.now()
    var cur = Io.parse(text)
    var dt = root.ioPrevMs > 0 ? (now - root.ioPrevMs) / 1000 : 0
    if (dt > 0.2) {
      var rates = Io.rates(root.ioPrev, cur, dt, root.ioDevices)
      root.ioRates = rates
      var hist = {}
      for (var k in root.ioHistory) hist[k] = root.ioHistory[k]
      for (var i = 0; i < root.ioDevices.length; i++) {
        var dev = root.ioDevices[i]
        var r = rates[dev]
        hist[dev] = Io.pushHistory(hist[dev], r ? r.readMBps + r.writeMBps : 0)
      }
      root.ioHistory = hist
    }
    root.ioPrev = cur
    root.ioPrevMs = now
  }

  // Colours come from theme ROLES, not hex, so every Omarchy theme works. A
  // user can override any of them in ~/.config/omarchy/shell.toml under
  // [disk-status]; those keys survive theme switches.
  // Color.pick() returns a raw STRING from shell.toml (or the fallback), so it
  // has to go through flatColor() to become a colour — that is also what
  // resolves a bare role name like "accent" against the current theme.
  readonly property color verdictColor: Color.flatColor(
    Color.pick("disk-status." + verdict, Model.colorRole(verdict)),
    Color.foreground)

  function refresh() {
    nowMs = Date.now()
    stateFile.reload()
  }

  // ---- popout contract (Bar.findPanelWidget needs open/close/opened here)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool panelActive: panelLoader.item
    ? (panelLoader.item.opened === true || panelLoader.item.pinned === true) : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("healthState" in target) target.healthState = root.healthState
    if ("stale" in target) target.stale = root.stale
  }

  function injectIo() {
    var target = panelLoader.item
    if (!target || !root.panelActive) return
    if ("ioRates" in target) target.ioRates = root.ioRates
    if ("ioHistory" in target) target.ioHistory = root.ioHistory
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onHealthStateChanged: injectPanel()
  onStaleChanged: injectPanel()
  onIoRatesChanged: injectIo()
  onIoHistoryChanged: injectIo()
  onPanelActiveChanged: { if (panelActive) injectIo() }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root.healthState = JSON.parse(text())
        root.loadFailed = false
      } catch (e) {
        // A parse failure here means we caught the collector mid-write, or the
        // file is damaged. Either way: unknown, not the last good value.
        root.loadFailed = true
      }
      root.nowMs = Date.now()
    }
    onLoadFailed: { root.healthState = null; root.loadFailed = true }
    onFileChanged: reload()
  }

  // /proc/diskstats is a size-0 procfs file. FileView reports its size as 0
  // but text() still returns the generated contents — verified on this box
  // (kernel 7.1.8, Quickshell 0.2). If that ever stops being true the symptom
  // is every drive reading "—" forever, and the fallback is a Process running
  // `cat`; it is not needed today and a bar widget that spawns processes is
  // worth avoiding.
  FileView {
    id: diskstats
    path: "/proc/diskstats"
    watchChanges: false
    printErrors: false
    onLoaded: root.sampleIo(text())
  }

  // Two cadences, one clock: 1 s while popup or pinned rail is visible, 15 s
  // otherwise. The slow background sample preserves the bar activity hint.
  Timer {
    interval: root.panelActive ? 1000 : 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: diskstats.reload()
  }

  // Re-evaluates staleness without re-reading the file: the danger is the
  // collector going quiet, which produces no file change to react to.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      root.injectIo()
      Qt.callLater(root.injectPanel)
    }
  }

  implicitWidth: pill.implicitWidth
  implicitHeight: pill.implicitHeight

  Row {
    id: pill
    spacing: Style.space(2)

    BarIconButton {
      id: button
      bar: root.bar
      text: Model.GLYPH
      slotSize: Style.bar.statusSlot
      fontSize: Style.font.caption
      tooltipText: Model.tooltipFor(root.healthState, root.nowMs)

    // The verdict tint. useActiveColor drives WidgetButton's own colouring,
    // so it is switched on for anything that is not "good" and the colour is
    // supplied per verdict rather than always being `urgent`.
      active: root.verdict !== "good"
      activeColor: root.verdictColor
      foreground: root.verdict === "good" && !root.stale
        ? (root.bar ? root.bar.barForeground : Color.foreground)
        : root.verdictColor

      onPressed: root.togglePanel()
    }

    Text {
      visible: !root.stale && root.troubled > 0
      width: visible ? implicitWidth + Style.space(2) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: String(root.troubled)
      color: root.verdictColor
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption * 0.9
    }

    // Throughput, only while something is actually moving. Idle shows nothing
    // at all rather than a row of zeroes — a bar that always says "0.0 MB/s"
    // is a bar you stop reading.
    Text {
      id: rate
      anchors.verticalCenter: parent.verticalCenter
      visible: root.ioText !== ""
      width: visible ? implicitWidth + Style.space(6) : 0
      text: root.ioText
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption * 0.92
      opacity: 0.85

      MouseArea {
        anchors.fill: parent
        onClicked: root.togglePanel()
      }
    }
  }
}
