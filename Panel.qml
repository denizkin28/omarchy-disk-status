import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "DiskIoModel.js" as Io
import "PanelModel.js" as Present

Panel {
  id: root
  moduleName: "denizkin.disk-health"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var healthState: null
  property bool stale: false
  property var ioRates: ({})
  property var ioHistory: ({})
  property string selectedKey: ""
  property int keyboardIndex: 0
  property bool keyboardUsed: false
  property bool pinned: false

  readonly property var drives: healthState && healthState.drives ? healthState.drives : []
  readonly property var removable: healthState && healthState.removable ? healthState.removable : []
  readonly property var allDrives: drives.concat(removable)
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color bg: bar ? bar.background : Color.background
  readonly property string uiFont: bar ? bar.fontFamily : Style.font.family
  readonly property color frameColor: Color.flatColor(Color.pick("disk-health.frame", "accent"), Color.accent)
  readonly property var overallDrive: stale ? null : Model.overallDrive(healthState)
  readonly property int overallScore: root.overallDrive ? root.healthValue(root.overallDrive) : -1
  readonly property string overallVerdict: root.overallDrive ? root.verdictFor(root.overallDrive) : "unknown"
  readonly property bool anyDerived: {
    for (var i = 0; i < allDrives.length; i++) if ((allDrives[i].health || {}).percent_is_derived) return true
    return false
  }
  readonly property int troubledCount: stale ? 0 : Model.troubledCount(healthState)

  function keyFor(d) { return String(d.serial || d.history_id || d.device || "") }
  function verdictColor(v) { return Color.flatColor(Color.pick("disk-health." + v, Model.colorRole(v)), Color.foreground) }
  function verdictFor(d) { return stale ? "unknown" : String((d.health || {}).verdict || "unknown") }
  function tintFor(d) { return verdictColor(verdictFor(d)) }
  function verdictLabel(d) { return stale ? "STALE" : Model.verdictWord(verdictFor(d)) }
  function healthValue(d) {
    var p = (d.health || {}).percent
    return stale || p === null || p === undefined ? -1 : Math.floor(Number(p))
  }
  function healthText(d) {
    var value = healthValue(d), h = d.health || {}
    return value < 0 ? "—" : value + "%" + (h.percent_is_derived ? "*" : "")
  }
  function ioFor(d) { var dev = String(d.device || "").replace("/dev/", ""); return dev ? ioRates[dev] : null }
  function ioHistoryFor(d) { var dev = String(d.device || "").replace("/dev/", ""); return dev && ioHistory[dev] ? ioHistory[dev] : [] }
  function capacityFor(d) {
    var fs = d.filesystems || [], used = 0, usable = 0
    for (var i = 0; i < fs.length; i++) {
      var rowUsed = Number(fs[i].used_bytes || 0)
      used += rowUsed
      usable += rowUsed + Number(fs[i].avail_bytes || 0)
    }
    return { used: used, usable: usable, percent: usable > 0 ? Math.round(used / usable * 100) : -1 }
  }
  function usageColor(pct) { return pct >= 95 ? verdictColor("bad") : pct >= 85 ? verdictColor("caution") : Qt.rgba(fg.r, fg.g, fg.b, 0.55) }
  function temperatureColor(d) {
    var t = d.temperature || {}
    if (t.c === null || t.c === undefined) return Qt.rgba(fg.r, fg.g, fg.b, 0.48)
    if (t.limit_max !== null && t.limit_max !== undefined && t.c >= t.limit_max) return verdictColor("bad")
    if (t.warn_at !== null && t.warn_at !== undefined && t.c >= t.warn_at) return verdictColor("caution")
    return Qt.rgba(fg.r, fg.g, fg.b, 0.75)
  }
  function toggleDetails(d) { var key = keyFor(d); selectedKey = selectedKey === key ? "" : key }
  function cardAt(index) { return index >= 0 && index < allDrives.length ? cardsRepeater.itemAt(index) : null }
  function moveCard(delta) {
    if (!allDrives.length) return
    keyboardUsed = true
    keyboardIndex = Math.max(0, Math.min(allDrives.length - 1, keyboardIndex + delta))
    var card = cardAt(keyboardIndex)
    if (card) scroll.contentY = Math.max(0, Math.min(card.y + cards.y - Style.space(8), Math.max(0, scroll.contentHeight - scroll.height)))
  }
  function expandCard() { keyboardUsed = true; var card = cardAt(keyboardIndex); if (card) selectedKey = keyFor(card.modelData) }
  function collapseCard() { keyboardUsed = true; var card = cardAt(keyboardIndex); if (card && selectedKey === keyFor(card.modelData)) selectedKey = "" }
  function activateCard() { keyboardUsed = true; var card = cardAt(keyboardIndex); if (card) toggleDetails(card.modelData) }
  function copyCard() { keyboardUsed = true; var card = cardAt(keyboardIndex); if (card) card.copyNow() }
  function firstProblemText() {
    for (var i = 0; i < drives.length; i++) {
      var h = drives[i].health || {}
      if (h.affects_overall === false || Model.rank(h.verdict) <= 0) continue
      var reason = h.reasons && h.reasons.length ? String(h.reasons[0]) : String(h.verdict || "needs attention")
      return Model.configuredLabel(drives[i]) + ": " + reason
    }
    return ""
  }
  function summaryText() {
    if (stale || !healthState) return "HEALTH UNKNOWN · COLLECTOR DATA STALE"
    if (troubledCount > 0) return "⚠ " + firstProblemText() + (troubledCount > 1 ? " · +" + (troubledCount - 1) + " MORE" : "")
    return "ALL " + drives.length + " INTERNAL " + (drives.length === 1 ? "DRIVE" : "DRIVES") + " OK · " + removable.length + " REMOVABLE"
  }

  function open() { controller.show() }
  function close() { controller.hide() }
  function toggle() { pinned ? unpin() : (opened ? close() : open()) }
  function pin() { controller.hide(); pinned = true }
  function unpin() { pinned = false }
  function switchPanel(direction) { return bar && typeof bar.switchPanelFrom === "function" ? bar.switchPanelFrom(barIdentity, direction) : false }

  IpcHandler {
    target: "denizkin.disk-health"
    function showPopup(): string { root.unpin(); root.open(); return "ok" }
    function hidePopup(): string { root.close(); return "ok" }
    function showSidebar(): string { root.pin(); return "ok" }
    function hideSidebar(): string { root.unpin(); return "ok" }
    function toggleSidebar(): string { root.pinned ? root.unpin() : root.pin(); return "ok" }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened && !root.pinned
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(760))
    // Six collapsed cards (three rows) fit without scrolling. Expanded
    // diagnostics may exceed this cap and intentionally use the Flickable.
    contentHeight: panel.fittedContentHeight(Math.min(dashboard.implicitHeight, Style.space(720)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCard(dy)
        else if (dx > 0) root.expandCard()
        else if (dx < 0) root.collapseCard()
      }
      onActivateRequested: root.activateCard()
      onTextKey: function(text) { if (text === "c" || text === "C") root.copyCard() }

      Rectangle {
        anchors.fill: parent
        radius: Style.space(10)
        color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.98)
        border.width: 1
        border.color: Qt.rgba(root.frameColor.r, root.frameColor.g, root.frameColor.b, 0.8)

        Flickable {
          id: scroll
          anchors.fill: parent
          anchors.margins: Style.space(12)
          contentWidth: width
          contentHeight: dashboard.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: dashboard
            parent: root.pinned ? pinnedScroll.contentItem : scroll.contentItem
            width: root.pinned ? pinnedScroll.width : scroll.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              height: title.implicitHeight
              Text { id: title; anchors.centerIn: parent; text: "DISK STATUS"; color: root.fg; font.family: root.uiFont; font.pixelSize: Style.font.title; font.weight: Font.DemiBold; font.letterSpacing: 4 }
              Rectangle { anchors.left: parent.left; anchors.right: title.left; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; height: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.32) }
              Rectangle { anchors.left: title.right; anchors.right: pinAction.left; anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; height: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.32) }
              Text {
                id: pinAction
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.pinned ? "󰅖  UNPIN" : "󰐃  PIN"
                color: pinArea.containsMouse ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.caption
                MouseArea { id: pinArea; anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pinned ? root.unpin() : root.pin() }
              }
            }

            RadialGauge {
              visible: root.drives.length !== 1
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(160)
              height: width
              value: root.overallScore < 0 ? 0 : root.overallScore
              segments: 42
              activeColor: root.verdictColor(root.overallVerdict)
              trackColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.stale || root.overallScore < 0 ? 0.18 : 0.10)
              textColor: root.fg
              fontFamily: root.uiFont
              valueText: root.overallScore < 0 ? "—" : String(root.overallScore) + (((root.overallDrive || {}).health || {}).percent_is_derived ? "*" : "")
              caption: root.stale ? "DATA STALE" : !root.overallDrive ? "NO DATA" : "WORST: " + Model.configuredLabel(root.overallDrive)
              valuePixelSize: Style.font.title * 2.55
              captionPixelSize: Style.font.caption * 0.9
            }

            Text {
              width: parent.width
              text: root.summaryText()
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.4
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              color: root.stale ? root.verdictColor("unknown")
                    : root.troubledCount > 0 || root.drives.length === 1 ? root.verdictColor(root.overallVerdict)
                    : root.fg
            }

            Grid {
              id: cards
              width: parent.width
              // The popup can use the wider two-column overview. Pinned mode is
              // deliberately a compact rail, so every disk gets one full row.
              columns: root.pinned ? 1 : (width >= Style.space(580) ? 2 : 1)
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(10)

              Repeater {
                id: cardsRepeater
                model: root.allDrives
                delegate: Rectangle {
                  id: card
                  required property int index
                  required property var modelData
                  property bool copied: false
                  readonly property bool removable: modelData.removable === true
                  readonly property color tint: root.tintFor(modelData)
                  readonly property int healthValue: root.healthValue(modelData)
                  readonly property var capacity: root.capacityFor(modelData)
                  readonly property int usage: capacity.percent
                  readonly property bool expanded: root.selectedKey === root.keyFor(modelData)
                  width: cards.columns === 2 ? (cards.width - cards.columnSpacing) / 2 : cards.width
                  height: expanded ? Math.max(Style.space(330), cardBody.implicitHeight + Style.space(16)) : Style.space(118)
                  radius: Style.space(7)
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, cardArea.containsMouse ? 0.060 : 0.025)
                  border.width: removable ? 0 : (cardArea.containsMouse || expanded || (root.keyboardUsed && root.keyboardIndex === index) ? 2 : 1)
                  border.color: Qt.rgba(tint.r, tint.g, tint.b, cardArea.containsMouse || (root.keyboardUsed && root.keyboardIndex === index) ? 0.78 : 0.34)
                  Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                  function copyNow() {
                    Quickshell.clipboardText = Present.copyText(modelData, root.healthState)
                    copied = true
                    copiedReset.restart()
                  }

                  Timer { id: copiedReset; interval: 1600; onTriggered: card.copied = false }

                  Canvas {
                    id: removableFrame
                    anchors.fill: parent
                    anchors.margins: 2
                    visible: card.removable
                    z: 3
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                      var ctx = getContext("2d"); ctx.reset()
                      ctx.setLineDash([5, 4]); ctx.lineWidth = 1
                      ctx.strokeStyle = root.fg
                      ctx.globalAlpha = cardArea.containsMouse ? 0.72 : 0.40
                      ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
                    }
                  }

                  MouseArea {
                    id: cardArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (card.removable) removableFrame.requestPaint()
                    onClicked: { root.keyboardIndex = card.index; root.keyboardUsed = false; root.toggleDetails(card.modelData) }
                  }

                  Column {
                    id: cardBody
                    anchors.fill: parent
                    anchors.margins: Style.space(8)
                    spacing: Style.space(4)

                    Text {
                      text: card.removable ? "REMOVABLE  ·  ⊘ EXCLUDED FROM SCORE" : "INTERNAL"
                      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, card.removable ? 0.62 : 0.55)
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                    }

                    Row {
                      width: parent.width
                      spacing: Style.space(10)

                      RadialGauge {
                        id: healthGauge
                        width: Style.space(58)
                        height: width
                        value: card.healthValue < 0 ? 0 : card.healthValue
                        segments: 16
                        startDegrees: -205
                        sweepDegrees: 230
                        ringWidth: Style.space(5)
                        activeColor: card.tint
                        trackColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, card.healthValue < 0 ? 0.18 : 0.10)
                        textColor: root.fg
                        fontFamily: root.uiFont
                        valueText: root.healthText(card.modelData)
                        caption: card.healthValue < 0 ? "N/A" : "HEALTH"
                        valuePixelSize: Style.font.body * 0.95
                        captionPixelSize: Style.font.caption * 0.82
                      }

                      Column {
                        width: Math.max(0, parent.width - healthGauge.width - statusColumn.width - parent.spacing * 2)
                        spacing: Style.space(3)
                        Text { width: parent.width; text: Model.configuredLabel(card.modelData) + "  ·  " + (card.modelData.capacity_bytes ? Present.bytesText(card.modelData.capacity_bytes) : "—"); color: root.fg; font.family: root.uiFont; font.pixelSize: Style.font.body; font.weight: Font.DemiBold; font.letterSpacing: 0.7; elide: Text.ElideRight }
                        Text { width: parent.width; text: card.modelData.model || card.modelData.kind || "Unknown drive"; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.62); font.family: root.uiFont; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle }
                        Text { width: parent.width; text: card.copied ? "✓ COPIED" : (Io.isIdle(root.ioFor(card.modelData)) ? "I/O  IDLE" : "I/O  " + Io.formatRate(root.ioFor(card.modelData))); color: card.copied ? card.tint : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.48); font.family: root.uiFont; font.pixelSize: Style.font.caption }
                      }

                      Column {
                        id: statusColumn
                        width: Style.space(72)
                        spacing: Style.space(3)
                        Text { anchors.right: parent.right; text: root.verdictLabel(card.modelData); color: card.tint; font.family: root.uiFont; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
                        Text { anchors.right: parent.right; text: ((card.modelData.temperature || {}).c === null || (card.modelData.temperature || {}).c === undefined) ? "— °C" : card.modelData.temperature.c + " °C"; color: root.temperatureColor(card.modelData); font.family: root.uiFont; font.pixelSize: Style.font.caption }
                        Text { anchors.right: parent.right; text: card.expanded ? "▾" : "▸"; color: cardArea.containsMouse ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45); font.family: root.uiFont; font.pixelSize: Style.font.body }
                      }
                    }

                    Item {
                      width: parent.width
                      height: Style.space(20)
                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: usageText.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        height: Style.space(6)
                        radius: height / 2
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
                        Rectangle {
                          visible: card.usage >= 0
                          width: parent.width * Math.max(0, Math.min(100, card.usage)) / 100
                          height: parent.height
                          radius: height / 2
                          color: root.usageColor(card.usage)
                        }
                      }
                      Text {
                        id: usageText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.usage < 0 ? "USED  —" : "USED  " + Present.bytesText(card.capacity.used) + " / " + Present.bytesText(card.capacity.usable) + "  " + card.usage + "%"
                        color: card.usage < 0 ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45) : root.usageColor(card.usage)
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Loader {
                      id: diagnosticsLoader
                      active: card.expanded
                      width: parent.width
                      sourceComponent: Component { Column {
                      width: diagnosticsLoader.width
                      spacing: Style.space(4)
                      Rectangle { width: parent.width; height: 1; color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.24) }
                      Row {
                        width: parent.width
                        Text { text: "DIAGNOSTICS"; color: root.fg; font.family: root.uiFont; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                        Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - copyAction.implicitWidth); height: 1 }
                        Text { id: copyAction; text: card.copied ? "✓ COPIED" : "󰆏  COPY REPORT"; color: card.copied ? card.tint : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, copyHover.containsMouse ? 0.9 : 0.55); font.family: root.uiFont; font.pixelSize: Style.font.caption
                          MouseArea { id: copyHover; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.copyNow() }
                        }
                      }
                      Text { width: parent.width; text: (card.modelData.mounts || []).length ? "MOUNTED  " + card.modelData.mounts.join(", ") : "NOT MOUNTED"; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.62); font.family: root.uiFont; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle }
                      Text { width: parent.width; text: Present.counterText(card.modelData, true) || (((card.modelData.health || {}).reasons || []).join(" · ") || "No active SMART warnings"); color: card.tint; font.family: root.uiFont; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                      Text { width: parent.width; text: Present.advancedText(card.modelData); visible: text !== ""; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.68); font.family: root.uiFont; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
                      Text { text: "LIVE I/O · 60 SAMPLES"; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45); font.family: root.uiFont; font.pixelSize: Style.font.caption }
                      Canvas {
                        width: parent.width
                        height: Style.space(32)
                        property var samples: root.ioHistoryFor(card.modelData)
                        onSamplesChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: {
                          var ctx = getContext("2d"); ctx.reset()
                          if (samples.length < 2) return
                          var peak = Io.historyMax(samples, 10), step = width / (samples.length - 1)
                          ctx.beginPath()
                          for (var i = 0; i < samples.length; i++) {
                            var y = height - Math.max(0, Math.min(height, samples[i] / peak * height))
                            if (!i) ctx.moveTo(0, y); else ctx.lineTo(i * step, y)
                          }
                          ctx.strokeStyle = root.fg; ctx.globalAlpha = 0.62; ctx.lineWidth = 1.2; ctx.stroke()
                        }
                      }
                      } }
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              text: root.healthState ? "COLLECTED " + String(root.healthState.collected_at || "").substring(0, 19).replace("T", " ")
                    + (root.anyDerived ? "   ·   * DERIVED" : "")
                    + (root.pinned ? "" : "   ·   ↑↓ DRIVE   ·   ⏎ DETAILS   ·   C COPY") : ""
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.42)
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }

  // Persistent right-edge mode. The same `dashboard` item is reparented into
  // this window while pinned, so data bindings, card state and Canvas work are
  // not duplicated. Auto exclusion reserves space instead of covering tiled
  // applications; focus remains on-demand for scrolling and card actions.
  PanelWindow {
    screen: panel.screen
    visible: root.pinned
    color: "transparent"
    exclusionMode: ExclusionMode.Auto
    // Hyprland already places its configured gap between this exclusive zone
    // and tiled windows, so the surface itself must not add a second gutter.
    implicitWidth: Math.min(Style.space(440), Math.max(Style.space(360), screen ? screen.width * 0.23 : Style.space(400)))
    implicitHeight: 0
    anchors { top: true; bottom: true; right: true }
    margins {
      // The bar's exclusive zone is already removed from the available layer
      // area. Adding barSize here pushed the sidebar down a second time.
      top: Style.gapsOut
      bottom: Style.gapsOut
      right: Style.gapsOut
    }
    WlrLayershell.namespace: "denizkin-disk-health-pinned"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      anchors.fill: parent
      radius: Style.space(10)
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.985)
      border.width: 1
      border.color: Qt.rgba(root.frameColor.r, root.frameColor.g, root.frameColor.b, 0.8)

      Flickable {
        id: pinnedScroll
        anchors.fill: parent
        anchors.margins: Style.space(12)
        contentWidth: width
        contentHeight: dashboard.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
      }
    }
  }
}
