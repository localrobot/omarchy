# Browsers

Omarchy ships with [Google Chrome](https://www.google.com/chrome/) as the exclusive, system-default browser. It is themed to match the rest of your system, opens via `Super + Shift + Return` (or `Super + Shift + B`), and powers all [web apps](25-web-apps.md). Launch an incognito session at any time with `Super + Shift + Alt + B`.

## Copy URL and Download Video

Google Chrome comes pre-configured with two Omarchy extensions that integrate directly into the desktop environment:

**Copy URL** puts the current tab's address on your clipboard with `Alt + Shift + L`. That's faster than clicking into the address bar and copying, and because it goes through the system clipboard rather than the browser's, you get an Omarchy notification confirming it and the URL is immediately available in [clipboard history](08-unified-clipboard-history.md) and every other app. There's a toolbar button too, if you prefer clicking.

**Download Video** grabs the video playing on the page you're looking at with `Alt + Shift + D`. It hands the URL to [yt-dlp](https://github.com/yt-dlp/yt-dlp), so it works on far more than YouTube, and the download lands in `~/Videos`. Progress shows up in the same on-screen display that volume and brightness use, updating in place rather than stacking up notifications. Set `OMARCHY_YTDLP_DIR` if you'd rather the files went somewhere else — see the [FAQ](46-faq.md) for where to put environment variables.

Both extensions communicate with Omarchy through a small native messaging host configured automatically on the workstation.
