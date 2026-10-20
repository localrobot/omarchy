function authorizationLabel(message, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  var text = String(message || "")
  var match = text.match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i)
  return match ? t("polkit.authorizeRunning", "Authorize running '%1'").replace("%1", match[1]) : text
}

if (typeof module !== "undefined") {
  module.exports = {
    authorizationLabel: authorizationLabel
  }
}
