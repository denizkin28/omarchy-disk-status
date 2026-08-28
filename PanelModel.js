.pragma library

function bytesText(n) {
  if (n === null || n === undefined) return "—"
  var units = ["B", "KB", "MB", "GB", "TB", "PB"], v = n, i = 0
  while (Math.abs(v) >= 1000 && i < units.length - 1) { v /= 1000; i++ }
  if (i > 0 && Math.abs(Math.round(v * 10) / 10) >= 1000 && i < units.length - 1) {
    v /= 1000; i++
  }
  return (i === 0 ? v : v.toFixed(1)) + " " + units[i]
}

function displaySerial(drive) {
  if (drive.disk_serial) return String(drive.disk_serial)
  var serial = String(drive.serial || "")
  var marker = serial.indexOf("@")
  return marker > 0 ? serial.substring(0, marker) : serial
}

function tempText(drive) {
  var t = drive.temperature || {}
  if (t.c === null || t.c === undefined) return "—"
  var s = t.c + " °C"
  if (t.min_c !== null && t.min_c !== undefined && t.max_c !== null && t.max_c !== undefined)
    s += "   " + (t.minmax_scope || "min/max") + " " + t.min_c + "–" + t.max_c + " °C"
  if (t.over_limit_minutes) s += "   " + t.over_limit_minutes + " min over limit"
  return s
}

function featureText(drive) {
  var f = drive.features || {}, on = [], off = []
  var labels = { smart: "S.M.A.R.T.", apm: "APM", aam: "AAM", trim: "TRIM", write_cache: "Write cache" }
  for (var k in labels) {
    if (f[k] === true) on.push(labels[k])
    else if (f[k] === false) off.push(labels[k])
  }
  var bits = []
  if (on.length) bits.push(on.join(", "))
  if (off.length) bits.push("off: " + off.join(", "))
  return bits.join("   ·   ")
}

function nvmeText(drive) {
  var n = drive.nvme
  if (!n) return ""
  var bits = []
  if (n.percentage_used !== null && n.percentage_used !== undefined) bits.push("wear " + n.percentage_used + "%")
  if (n.available_spare !== null && n.available_spare !== undefined) {
    var spare = "spare " + n.available_spare + "%"
    if (n.spare_threshold !== null && n.spare_threshold !== undefined) spare += " (min " + n.spare_threshold + "%)"
    bits.push(spare)
  }
  if (n.media_errors !== null && n.media_errors !== undefined) bits.push("media errors " + n.media_errors)
  if (n.num_err_log_entries !== null && n.num_err_log_entries !== undefined) bits.push("err-log " + n.num_err_log_entries)
  if (n.unsafe_shutdowns !== null && n.unsafe_shutdowns !== undefined) bits.push("unsafe shutdowns " + n.unsafe_shutdowns)
  if (n.temp_sensors_c && n.temp_sensors_c.length) bits.push("sensors " + n.temp_sensors_c.join(" / ") + " °C")
  return bits.join("   ·   ")
}

function scsiText(drive) {
  var s = drive.scsi
  if (!s) return ""
  var bits = []
  if (s.percentage_used !== null && s.percentage_used !== undefined)
    bits.push("wear " + s.percentage_used + "% used")
  if (s.grown_defects !== null && s.grown_defects !== undefined)
    bits.push("grown defects " + s.grown_defects)
  var errors = s.uncorrected_errors || {}
  for (var operation in errors)
    bits.push("uncorrected " + operation + " " + errors[operation])
  return bits.join("   ·   ")
}

function mmcText(drive) {
  var m = drive.mmc
  if (!m) return ""
  var bits = []
  if (m.percentage_used_upper_bound !== null && m.percentage_used_upper_bound !== undefined)
    bits.push("wear at most " + m.percentage_used_upper_bound + "% used")
  if (m.pre_eol !== null && m.pre_eol !== undefined)
    bits.push("pre-EOL " + m.pre_eol)
  return bits.join("   ·   ")
}

function errorLogText(drive) {
  var e = drive.error_log
  if (!e) return ""
  var entries = e.entries || []
  if ((e.count === null || e.count === undefined) && !entries.length) return ""
  var text = e.count === null || e.count === undefined ? "count unavailable" : String(e.count)
  if (typeof e.delta === "number" && e.delta > 0) text += " (+" + e.delta + ")"
  if (e.last_poh !== null && e.last_poh !== undefined) text += "   last at " + e.last_poh + " h"
  for (var i = 0; i < entries.length; i++) {
    var item = entries[i], detail = item.description || item.message || item.status || "error entry"
    if (item.lba !== null && item.lba !== undefined) detail += " at LBA " + item.lba
    if (item.poh !== null && item.poh !== undefined) detail += " (" + item.poh + " h)"
    text += "\n                · " + detail
  }
  return text
}

function trendText(drive) {
  var t = drive.trends || {}, bits = []
  function period(label, p) {
    if (!p || !p.deltas) return
    var changes = []
    for (var key in p.deltas) {
      var value = p.deltas[key]
      changes.push(key.replace(/_/g, " ") + " " + (value > 0 ? "+" : "") + value)
    }
    if (changes.length) bits.push(label + ": " + changes.join(", "))
  }
  period("7d", t.days_7); period("30d", t.days_30)
  return bits.join("   ·   ")
}

function databaseText(drive) {
  var d = drive.drive_database
  if (!d) return ""
  var bits = []
  if (d.known_model === false && drive.type !== "nvme") bits.push("model not recognized")
  if (d.version) bits.push("version " + d.version)
  if (d.age_days !== null && d.age_days !== undefined)
    bits.push((d.age_days > 90 ? "outdated: " : "") + d.age_days + " days old")
  return bits.join("   ·   ")
}

function farmEntries(drive, limit) {
  var f = drive.farm
  if (!f) return []
  var values = f.values || f, keys = []
  for (var key in values) {
    if (typeof values[key] === "object") continue
    keys.push(key)
  }
  function priority(key) {
    var k = key.toLowerCase()
    return /(error|reliab|defect|uncorrect|realloc|pending|head|media|flash|wear|temperature|power_on)/.test(k) ? 0 : 1
  }
  keys.sort(function(a, b) {
    var p = priority(a) - priority(b)
    return p || (a < b ? -1 : a > b ? 1 : 0)
  })
  var max = typeof limit === "number" ? limit : 8, bits = []
  for (var i = 0; i < keys.length && bits.length < max; i++)
    bits.push(keys[i].replace(/_/g, " ") + ": " + values[keys[i]])
  return bits
}

function farmText(drive, limit) {
  return farmEntries(drive, limit).join("\n")
}

function usageText(fs) {
  var used = Number(fs.used_bytes || 0)
  var usable = used + Number(fs.avail_bytes || 0)
  var percent = usable > 0 ? Math.round(used / usable * 100) : null
  return fs.mount + "   " + bytesText(used) + " of " + bytesText(usable)
    + (percent === null ? "" : "   " + percent + "% used")
}

function counterText(drive, movedOnly) {
  var wanted = { 5: "realloc", 187: "reported uncorr", 188: "timeouts",
                 197: "pending", 198: "offline uncorr", 199: "crc" }, bits = []
  var attrs = drive.attributes || []
  for (var i = 0; i < attrs.length; i++) {
    var a = attrs[i], moved = typeof a.delta === "number" && a.delta > 0
    if (!wanted[a.id] || (movedOnly && !moved)) continue
    var raw = a.raw === null || a.raw === undefined ? "—" : a.raw
    bits.push(wanted[a.id] + " " + raw + (moved ? " (+" + a.delta + ")" : ""))
  }
  return bits.join("    ")
}

function hasAttr(drive, ids) {
  var attrs = drive.attributes || []
  for (var i = 0; i < attrs.length; i++) if (ids.indexOf(Number(attrs[i].id)) >= 0) return true
  return false
}

function padField(value, width, right) {
  var text = value === null || value === undefined ? "—" : String(value)
  while (text.length < width) text = right ? " " + text : text + " "
  return text
}

function attributeRowText(a) {
  var moved = a.tripwire && typeof a.delta === "number" && a.delta > 0
  var mark = a.composite_masked ? "~" : (a.tripwire ? (moved ? "!" : "·") : " ")
  var raw = a.raw_decoded !== null && a.raw_decoded !== undefined ? a.raw_decoded : a.raw
  return mark + padField(a.id, 4, true) + " " + padField(a.name || "", 26) + " "
    + padField(a.value, 4, true) + " " + padField(a.worst, 4, true) + " "
    + padField(a.thresh, 4, true) + "   " + (raw === null || raw === undefined ? "—" : raw)
}

function advancedText(drive) {
  var L = []
  function add(k, v) { if (v !== null && v !== undefined && v !== "") L.push(k + v) }
  var hardware = []
  if (drive.capacity_bytes) hardware.push(bytesText(drive.capacity_bytes))
  if (drive.interface) hardware.push(drive.interface)
  if (drive.form_factor) hardware.push(drive.form_factor)
  if (drive.rotation_rpm) hardware.push(drive.rotation_rpm + " rpm")
  else if (drive.type !== "nvme" && drive.rotation_rpm === 0) hardware.push("solid state")
  if (drive.standard) hardware.push(drive.standard)
  add("Hardware:      ", hardware.join(" · "))
  if (drive.power_state && drive.power_state !== "unknown") add("Power state:   ", drive.power_state)
  add("Firmware:      ", drive.firmware)
  add("Transfer:      ", drive.transfer_mode)
  add("Features:      ", featureText(drive))
  if (!hasAttr(drive, [190, 194])) add("Temperature:   ", tempText(drive) === "—" ? "" : tempText(drive))
  if (!hasAttr(drive, [9]) && drive.power_on_hours !== null && drive.power_on_hours !== undefined)
    add("Power-on:      ", drive.power_on_hours + " h" + (drive.power_on_pretty ? " (" + drive.power_on_pretty + ")" : ""))
  if (!hasAttr(drive, [12])) add("Power cycles:  ", drive.power_cycles)
  if (!hasAttr(drive, [241, 242]) && (drive.host_writes_bytes !== null || drive.host_reads_bytes !== null))
    add("Host totals:   ", "written " + bytesText(drive.host_writes_bytes) + "   read " + bytesText(drive.host_reads_bytes))
  if (drive.endurance && !hasAttr(drive, [177, 231, 232, 233]))
    add("Endurance:     ", drive.endurance.written_tb + " TB of " + drive.endurance.rated_tbw + " TBW rated (" + drive.endurance.used_pct + "%)")
  add("NVMe:          ", nvmeText(drive))
  add("SCSI:          ", scsiText(drive))
  add("eMMC:          ", mmcText(drive))
  add("Error log:     ", errorLogText(drive))
  add("Trends:        ", trendText(drive))
  add("Drive DB:      ", databaseText(drive))
  add("SMART access:  ", drive.smart_capability)
  if (drive.probe) {
    var probe = drive.probe.selected || "unknown"
    if (drive.probe.attempts && drive.probe.attempts.length > 1)
      probe += " (tried " + drive.probe.attempts.join(", ") + ")"
    if (drive.probe_ms !== null && drive.probe_ms !== undefined)
      probe += "   " + drive.probe_ms + " ms"
    add("SMART probe:   ", probe)
  }
  add("Last read:     ", drive.read_at)
  var st = drive.selftest || {}
  if (st.status && st.status !== "unknown") add("Self-test:     ", st.status + (st.last_kind ? " (" + st.last_kind + ")" : "") + (st.last_poh !== null && st.last_poh !== undefined ? " at " + st.last_poh + " h" : ""))
  add("Source:        ", drive.source)
  return L.join("\n")
}

function copyText(drive, state) {
  var L = []
  function add(k, v) { if (v !== null && v !== undefined && v !== "") L.push(k + ": " + v) }
  var h = drive.health || {}
  L.push((drive.title || drive.model || drive.kind || "Unknown drive")
    + "  —  " + String(h.verdict || "unknown").toUpperCase(), "")
  add("Model", (drive.model || "—") + (drive.firmware ? "   fw " + drive.firmware : ""))
  add("Serial", displaySerial(drive)); add("Note", drive.note); add("Capacity", bytesText(drive.capacity_bytes))
  add("Interface", (drive.interface || "") + (drive.transfer_mode ? "   (" + drive.transfer_mode + ")" : ""))
  add("Standard", drive.standard); if (drive.rotation_rpm) add("Rotation", drive.rotation_rpm + " rpm")
  add("Power state", drive.power_state); add("Features", featureText(drive)); add("Mounted", (drive.mounts || []).join(", ") || "not mounted")
  var fs = drive.filesystems || []; for (var f = 0; f < fs.length; f++) add("Space", usageText(fs[f]))
  add("Health", (h.percent === null || h.percent === undefined ? "—" : h.percent + "%" + (h.percent_is_derived ? "*" : "")) + (h.percent_basis ? "   basis: " + h.percent_basis : ""))
  add("Temperature", tempText(drive))
  if (drive.power_on_hours !== null && drive.power_on_hours !== undefined) add("Power-on", drive.power_on_hours + " h" + (drive.power_on_pretty ? "   " + drive.power_on_pretty : ""))
  add("Power cycles", drive.power_cycles)
  if (drive.host_writes_bytes !== null || drive.host_reads_bytes !== null) add("Host totals", "written " + bytesText(drive.host_writes_bytes) + "   read " + bytesText(drive.host_reads_bytes))
  if (drive.endurance) add("Endurance", drive.endurance.written_tb + " TB of " + drive.endurance.rated_tbw + " TBW rated (" + drive.endurance.used_pct + "%)")
  add("NVMe", nvmeText(drive)); add("SCSI", scsiText(drive)); add("eMMC", mmcText(drive)); add("Error log", errorLogText(drive)); add("Counters", counterText(drive, false))
  add("Trends", trendText(drive)); add("Drive database", databaseText(drive)); add("Seagate FARM", farmText(drive, 40)); add("SMART access", drive.smart_capability)
  var st = drive.selftest || {}; if (st.status) add("Last self-test", st.status + (st.last_kind ? " (" + st.last_kind + ")" : "") + (st.last_poh !== null && st.last_poh !== undefined ? " at " + st.last_poh + " h" : ""))
  if (drive.source)
    add("Data source", drive.source + (drive.data_stale_since ? "   stale since " + drive.data_stale_since : ""))
  var reasons = h.reasons || []; for (var r = 0; r < reasons.length; r++) L.push("! " + reasons[r])
  var attrs = drive.attributes || []
  if (attrs.length) {
    L.push("", "  ID  ATTRIBUTE                   VAL  WST  THR   RAW")
    for (var i = 0; i < attrs.length; i++) {
      L.push(attributeRowText(attrs[i]))
    }
  }
  L.push("", "collected " + (state && state.collected_at ? state.collected_at : "?")
    + " by omarchy-disk-status on " + (state && state.host ? state.host : "?"))
  return L.join("\n")
}
