.pragma library

function litSegments(value, segments) {
  var count = Math.max(1, Math.floor(Number(segments) || 1))
  var fraction = Math.max(0, Math.min(100, Number(value) || 0)) / 100
  return fraction >= 1 ? count : Math.floor(fraction * count)
}
