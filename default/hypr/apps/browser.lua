-- Browser tags and styling.
o.window("(google-chrome|google-chrome-stable)", { tag = "+chrome-browser" })
o.window({ tag = "chrome-browser" }, { tile = true })

-- Hide screen sharing notification windows.
o.window({ title = ".*is sharing.*" }, { workspace = "special silent" })
