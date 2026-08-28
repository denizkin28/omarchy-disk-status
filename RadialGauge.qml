import QtQuick

Item {
  id: root
  property real value: 0
  property int segments: 36
  property real startDegrees: -225
  property real sweepDegrees: 270
  property color activeColor: "#9bd67d"
  property color trackColor: "#243023"
  property real ringWidth: Math.max(5, width * 0.105)
  property string valueText: "" // Live call sites supply an explicit label.
  property string caption: ""
  property color textColor: "#eef0d0"
  property string fontFamily: "monospace"
  property real valuePixelSize: width * 0.23
  property real captionPixelSize: width * 0.075
  onValueChanged: dial.requestPaint()
  onSegmentsChanged: dial.requestPaint()
  onActiveColorChanged: dial.requestPaint()
  onTrackColorChanged: dial.requestPaint()
  onWidthChanged: dial.requestPaint()
  onHeightChanged: dial.requestPaint()

  Canvas {
    id: dial
    anchors.fill: parent
    antialiasing: true
    onPaint: {
      var ctx = getContext("2d"); ctx.reset()
      var cx = width / 2, cy = height / 2
      var radius = Math.min(width, height) / 2 - root.ringWidth
      var fraction = Math.max(0, Math.min(100, root.value)) / 100

      // A one-segment gauge is a smooth donut. Drawing it through the
      // segmented path would round every value to either empty or full.
      if (root.segments <= 1) {
        var start = root.startDegrees * Math.PI / 180
        var end = (root.startDegrees + root.sweepDegrees) * Math.PI / 180
        ctx.lineWidth = root.ringWidth
        ctx.lineCap = "butt"
        ctx.beginPath()
        ctx.arc(cx, cy, radius, start, end, false)
        ctx.strokeStyle = root.trackColor
        ctx.stroke()
        if (fraction > 0) {
          ctx.beginPath()
          ctx.arc(cx, cy, radius, start,
                  start + root.sweepDegrees * fraction * Math.PI / 180, false)
          ctx.strokeStyle = root.activeColor
          ctx.stroke()
        }
        return
      }

      var gap = Math.min(3.2, root.sweepDegrees / root.segments * 0.30)
      var step = root.sweepDegrees / root.segments
      // A completely lit segmented ring is reserved for a true 100%.
      var lit = fraction >= 1 ? root.segments : Math.floor(fraction * root.segments)
      ctx.lineWidth = root.ringWidth; ctx.lineCap = "butt"
      for (var i = 0; i < root.segments; i++) {
        ctx.beginPath()
        ctx.arc(cx, cy, radius,
                (root.startDegrees + i * step + gap / 2) * Math.PI / 180,
                (root.startDegrees + (i + 1) * step - gap / 2) * Math.PI / 180, false)
        ctx.strokeStyle = i < lit ? root.activeColor : root.trackColor
        ctx.stroke()
      }
    }
  }
  Column {
    anchors.centerIn: parent
    width: root.width * 0.68
    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.valueText; color: root.textColor; font.family: root.fontFamily; font.pixelSize: root.valuePixelSize; font.weight: Font.Medium }
    Text { visible: text !== ""; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: root.caption; color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.78); font.family: root.fontFamily; font.pixelSize: root.captionPixelSize; font.letterSpacing: 0.8 }
  }
}
