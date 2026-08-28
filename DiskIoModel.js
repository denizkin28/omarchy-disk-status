.pragma library

// Live per-drive throughput from /proc/diskstats.
//
// This is cheap kernel data: no SMART, no smartctl, no root, and no reason to
// be shy about a 1-second cadence. SMART is the opposite on both counts, which
// is why the two are wired to completely separate clocks — the collector runs
// every 30 minutes, this runs every second while you are looking at it.
//
// Kernel field layout (post-5.5, 20 fields per line):
//   [0] major  [1] minor  [2] name
//   [5] sectors read   [9] sectors written   [12] io_ticks (ms spent doing I/O)
//
// Sectors here are ALWAYS 512 bytes, regardless of the drive's physical sector
// size. That is a kernel contract, not an assumption — the Exos drives are
// 4K-physical and still report 512-byte sectors here. Do not "fix" it.

var SECTOR_BYTES = 512
var HISTORY = 60          // samples kept per drive for the sparkline

function parse(text) {
  var stats = {}
  if (!text) return stats
  var lines = String(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length < 14) continue
    stats[f[2]] = {
      read: parseInt(f[5], 10),
      written: parseInt(f[9], 10),
      ticks: parseInt(f[12], 10)
    }
  }
  return stats
}

// Returns { dev: {readMBps, writeMBps, busy} } for the devices we care about.
// A missing device (unplugged mid-sample) is skipped rather than reported as
// zero — zero is a claim about an idle drive, absence is not.
function rates(prev, cur, dtSeconds, devices) {
  var out = {}
  if (!prev || !cur || !(dtSeconds > 0)) return out
  for (var i = 0; i < devices.length; i++) {
    var dev = devices[i]
    var a = prev[dev], b = cur[dev]
    if (!a || !b) continue
    var dr = b.read - a.read
    var dw = b.written - a.written
    var dt = b.ticks - a.ticks
    // Counters wrap or reset (device re-enumerated); a negative delta is not
    // a negative transfer rate, it is a sample to throw away.
    if (dr < 0 || dw < 0 || dt < 0) continue
    out[dev] = {
      readMBps: dr * SECTOR_BYTES / 1e6 / dtSeconds,
      writeMBps: dw * SECTOR_BYTES / 1e6 / dtSeconds,
      busy: Math.min(100, dt / (dtSeconds * 1000) * 100)
    }
  }
  return out
}

function isIdle(rate) {
  return !rate || (rate.readMBps < 0.05 && rate.writeMBps < 0.05)
}

function formatRate(rate) {
  if (isIdle(rate)) return "—"
  return "R " + rate.readMBps.toFixed(1) + "   W " + rate.writeMBps.toFixed(1)
         + " MB/s   " + rate.busy.toFixed(0) + "%"
}

// Total across the fixed drives, for the bar readout.
function aggregate(rateMap, devices) {
  var r = 0, w = 0
  for (var i = 0; i < devices.length; i++) {
    var x = rateMap[devices[i]]
    if (x) { r += x.readMBps; w += x.writeMBps }
  }
  return { readMBps: r, writeMBps: w, total: r + w }
}

// Compact enough to sit next to a bar glyph without pushing the clock around.
function formatAggregate(agg) {
  function unit(v) {
    if (v >= 1000) return (v / 1000).toFixed(1) + "G"
    if (v >= 100) return v.toFixed(0)
    return v.toFixed(1)
  }
  var bits = []
  if (agg.readMBps >= 0.5) bits.push("↓" + unit(agg.readMBps))
  if (agg.writeMBps >= 0.5) bits.push("↑" + unit(agg.writeMBps))
  return bits.join(" ")
}

// Rolling history, newest last. Returns a NEW array so QML property bindings
// actually re-evaluate — mutating in place would leave the sparkline frozen.
function pushHistory(history, value) {
  var next = history ? history.slice(-(HISTORY - 1)) : []
  next.push(value)
  return next
}

function historyMax(history, floor) {
  var m = floor || 1
  for (var i = 0; i < history.length; i++) if (history[i] > m) m = history[i]
  return m
}
