.pragma library

// Verdict ranking and presentation, shared by the bar widget and the panel.
// Kept out of QML so both read the same rules and neither re-derives them.

var RANK = { good: 0, caution: 1, unknown: 2, bad: 3 }

function rank(verdict) {
  var r = RANK[String(verdict)]
  return r === undefined ? 2 : r
}

// The bar glyph is always the harddisk icon; only the tint moves. U+F02CA is
// the same codepoint Omarchy uses for its own Disk Speed Test menu entry, so
// the bar reads as one family. The disk-with-badge variants render blank in
// JetBrainsMono Nerd Font — do not reach for them.
var GLYPH = "󰋊"  // U+F02CA nf-md-harddisk

// Role names, not literal colours: Color.qml exposes only foreground /
// accent / urgent / muted (colors.toml `green` and `yellow` are not mapped at
// all), so a theme-independent verdict tint has to be built from roles.
function colorRole(verdict) {
  switch (String(verdict)) {
    case "good":    return "foreground"
    case "caution": return "accent"
    case "bad":     return "urgent"
    default:        return "muted"
  }
}

// Select the worst eligible FIXED drive once for both the bar and panel. Equal
// verdicts use the lowest known percentage so the headline names the most worn.
function overallDrive(state) {
  if (!state || !state.drives) return null
  var chosen = null, chosenRank = -1, chosenPercent = 101
  for (var i = 0; i < state.drives.length; i++) {
    var drive = state.drives[i], health = drive.health || {}
    if (health.affects_overall === false) continue
    var driveRank = rank(health.verdict)
    var percent = health.percent === null || health.percent === undefined ? 101 : Number(health.percent)
    if (!chosen || driveRank > chosenRank || (driveRank === chosenRank && percent < chosenPercent)) {
      chosen = drive; chosenRank = driveRank; chosenPercent = percent
    }
  }
  return chosen
}

function overallVerdict(state) {
  var drive = overallDrive(state)
  return drive ? String((drive.health || {}).verdict || "unknown") : "unknown"
}

// A state file that stopped updating is unknown, never good — the same rule
// the collector and the CLI enforce, applied at the last surface.
function isStale(state, nowMs) {
  if (!state || !state.collected_at) return true
  var limit = 45
  try { limit = state.config.thresholds.stale_minutes || 45 } catch (e) {}
  var then = Date.parse(state.collected_at)
  if (isNaN(then)) return true
  return (nowMs - then) / 60000 > limit
}

function ageMinutes(state, nowMs) {
  if (!state || !state.collected_at) return -1
  var then = Date.parse(state.collected_at)
  return isNaN(then) ? -1 : Math.floor((nowMs - then) / 60000)
}

function tooltipFor(state, nowMs) {
  if (!state) return "DISK STATUS  ·  NO DATA\nCLICK  ·  OPEN DASHBOARD"
  if (isStale(state, nowMs)) {
    var staleAge = ageMinutes(state, nowMs)
    return "DISK STATUS  ·  DATA STALE\n"
         + "HEALTH UNKNOWN" + (staleAge >= 0 ? "  ·  " + staleAge + " MIN OLD" : "") + "\n\n"
         + "CLICK  ·  OPEN DASHBOARD"
  }

  // Match the dashboard's compact terminal grammar. The shell centres each
  // tooltip line, so fixed columns and a real temperature value at the end of
  // every drive row keep the block visually aligned.
  var rows = []
  var i
  var fixed = state.drives || []
  for (i = 0; i < fixed.length; i++) rows.push(rowFor(fixed[i], "INT"))
  var rem = state.removable || []
  for (i = 0; i < rem.length; i++) rows.push(rowFor(rem[i], "EXT"))
  if (rows.length === 0) return "DISK STATUS  ·  NO DRIVES"

  var statusW = 0, nameW = 0, pctW = 0, tempW = 0
  for (i = 0; i < rows.length; i++) {
    if (rows[i].status.length > statusW) statusW = rows[i].status.length
    if (rows[i].name.length > nameW) nameW = rows[i].name.length
    if (rows[i].pct.length > pctW) pctW = rows[i].pct.length
    if (rows[i].temp.length > tempW) tempW = rows[i].temp.length
  }

  var verdict = overallVerdict(state)
  var age = ageMinutes(state, nowMs)
  var summary = "DISK STATUS  ·  " + verdictWord(verdict)
    + "  ·  " + (age <= 0 ? "UPDATED NOW" : "UPDATED " + age + " MIN AGO")
  var inventory = fixed.length + " INTERNAL  ·  " + rem.length + " REMOVABLE"
  var lines = [summary, inventory, ""]
  for (i = 0; i < rows.length; i++) {
    lines.push(padRight(rows[i].status, statusW) + "  "
             + padRight(rows[i].name, nameW) + "  " + rows[i].kind
             + "  " + padLeft(rows[i].pct, pctW)
             + "  " + padLeft(rows[i].temp, tempW))
  }
  var problems = []
  for (i = 0; i < fixed.length; i++) {
    var health = fixed[i].health || {}
    if (rank(health.verdict) > 0) {
      var reason = health.reasons && health.reasons.length ? health.reasons[0] : health.verdict
      problems.push("ALERT  ·  " + configuredLabel(fixed[i]) + "  ·  " + reason)
    }
  }
  if (problems.length) lines = lines.concat([""], problems)
  lines.push("", "CLICK  ·  OPEN DASHBOARD")
  return lines.join("\n")
}

function rowFor(d, kind) {
  var h = d.health || {}
  var t = d.temperature || {}
  return {
    status: verdictWord(h.verdict),
    name: configuredLabel(d),
    kind: kind,
    pct: (h.percent === null || h.percent === undefined) ? "N/A" : Math.floor(h.percent) + "%" + (h.percent_is_derived ? "*" : ""),
    temp: (t.c === null || t.c === undefined) ? "N/A" : t.c + "\u00B0C"
  }
}

function verdictWord(verdict) {
  switch (String(verdict)) {
    case "good": return "OK"
    case "caution": return "CAUTION"
    case "bad": return "FAIL"
    default: return "NO DATA"
  }
}

function configuredLabel(d) {
  var label = String(d.name || d.kind || "DISK").replace(/\s*\(.*\)\s*$/, "")
  return label.toUpperCase()
}

function padRight(s, n) {
  var t = String(s)
  while (t.length < n) t += " "
  return t
}

function padLeft(s, n) {
  var t = String(s)
  while (t.length < n) t = " " + t
  return t
}

// Count of drives that are not good, for the pill suffix. Colour alone is not
// enough: in themes where accent is close to foreground, caution and good tint
// almost identically.
function troubledCount(state) {
  if (!state || !state.drives) return 0
  var n = 0
  for (var i = 0; i < state.drives.length; i++) {
    var health = state.drives[i].health || {}
    if (health.affects_overall !== false && rank(health.verdict) > 0) n++
  }
  return n
}
