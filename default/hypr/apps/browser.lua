-- Browser tags and styling.
o.window("(google-chrome|google-chrome-stable)", { tag = "+chromium-based-browser" })
o.window({ tag = "chromium-based-browser" }, { tile = true })

-- Hide screen sharing notification windows.
o.window({ title = ".*is sharing.*" }, { workspace = "special silent" })
