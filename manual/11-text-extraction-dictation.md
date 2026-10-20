# Text Extraction & Dictation

### Text Extraction

Hit `Super + Ctrl + PrtScr` to select a region on the screen for text extraction. The tesseract open source OCR model will then quickly convert that selection into text and place it on the clipboard. Then you just hit `Super + V` to paste.

This is very helpful for grabbing addresses out of image footers or phone numbers embedded in website headlines.

 ![text-extraction](images/text-extraction.webp)

### Dictation

On fresh installs, [Voxtype](https://voxtype.io/) is the default inline dictation backend, providing private, local speech-to-text processing using Whisper models without cloud dependencies. Voxtype loads an English model; change the model with `voxtype setup model` and configure settings through `~/.config/voxtype/config.toml`. For transcribing pre-recorded audio files and meetings, `whisper.cpp` (`whisper-cli`) is available with CUDA acceleration.

You dictate by holding down `Right Alt` or `F9`, or by toggling with `Super + Ctrl + X`, and the dictated text will appear in the focused input area. Right Alt also starts dictation when used in a modifier chord; use Left Alt for those chords. On keyboard layouts where Right Alt is AltGr, use `F9` to keep AltGr available for typing.

Run `omarchy default dictation` to see the configured backend. The selection is saved in `~/.config/omarchy/defaults/dictation`. Fresh installs select Voxtype automatically.

Custom bindings and scripts can use `omarchy dictation start`, `omarchy dictation stop`, and `omarchy dictation toggle`. Voxtype handles the recording and transcription directly into the active window.

Additional backends can integrate without changing Omarchy. Provide an executable named `omarchy-dictation-<backend>` on PATH that accepts `start`, `stop`, and `toggle` and returns promptly, with a nonzero status on failure. Its installer configures the provider and calls `omarchy-dictation-use <backend>` after successful setup. This stops the previous backend and saves the selection atomically; `stop` must succeed when the provider is idle or unavailable. Backend names use lowercase letters, digits, and hyphens. Provide `omarchy-install-dictation-<backend>` for setup; `omarchy default dictation <backend>` launches it. Optional desktop integration can live in `${XDG_CONFIG_HOME:-$HOME/.config}/<backend>/shortcuts.lua`.
