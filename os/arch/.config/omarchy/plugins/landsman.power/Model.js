function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

/**
 * One battery, as omarchy-battery-status --shell reports it. Figures stay strings,
 * as printed, and are empty where the firmware does not report them.
 *
 * @typedef {Object} Pack
 * @property {string} name Kernel name, such as BAT0.
 * @property {number} percent Charge from 0 to 100, or -1 when not reported.
 * @property {string} energy Stored energy in Wh.
 * @property {string} full Capacity in Wh.
 * @property {string} watts Current draw or charge rate in W.
 * @property {string} status Kernel status, such as Discharging.
 * @property {string} cycles Charge cycles.
 */

/**
 * Reads the script's `pack` lines and ignores every other line.
 *
 * @param {string} raw Output of omarchy-battery-status --shell.
 * @returns {Pack[]} One per battery, in the order the script listed them.
 */
function parsePacks(raw) {
  var packs = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    if (f[0] !== "pack" || !f[1]) continue
    packs.push({
      name: f[1],
      percent: f[2] === "" || f[2] === undefined ? -1 : Number(f[2]),
      energy: f[3] || "",
      full: f[4] || "",
      watts: f[5] || "",
      status: f[6] || "",
      cycles: f[7] || ""
    })
  }
  return packs
}

/**
 * @param {Pack} pack
 * @returns {number} Charge from 0 to 1 for the progress bar; 0 when not reported.
 */
function packFraction(pack) {
  return pack && pack.percent > 0 ? Math.min(1, pack.percent / 100) : 0
}

/**
 * @param {Pack} pack
 * @returns {string} The line under the battery's bar. Leaves out unreported values and a draw of zero.
 */
function packDetail(pack) {
  var parts = []
  if (pack.energy && pack.full) parts.push(pack.energy + " / " + pack.full + " Wh")
  if (Number(pack.watts) > 0) parts.push(pack.watts + " W")
  if (pack.status) parts.push(pack.status)
  if (pack.cycles) parts.push(pack.cycles + " cycles")
  return parts.join(" · ")
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parsePacks: parsePacks,
    packFraction: packFraction,
    packDetail: packDetail,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel
  }
}
