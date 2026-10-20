#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# --- Catalog completeness, placeholder parity, and menu translation logic ---

run_node_test <<'JS'
const fs = require('fs')
const MenuModel = requireFromRoot('shell/plugins/menu/MenuModel.js')

const i18nDir = path.join(root, 'default/i18n')
const readJson = (rel) => JSON.parse(fs.readFileSync(path.join(i18nDir, rel), 'utf8'))

const registry = readJson('locales.json')
const codes = Object.keys(registry)
assertEqual(codes.length, 1, 'i18n registry holds 1 language')
assert(codes[0] === 'en', 'i18n registry lists English first (the default)')
const badRegistry = codes.filter((code) => !/^[a-z]{2,3}(-[A-Za-z]{2})?$/.test(code)
  || ['name', 'englishName', 'formatLocale', 'locale'].some((f) => typeof registry[code][f] !== 'string' || registry[code][f].length === 0)
  || !/\.UTF-8$/.test(registry[code].locale))
assert(badRegistry.length === 0, 'every registry entry is complete with a UTF-8 locale', JSON.stringify(badRegistry))

// The English menu catalog must mirror the shipped menu definition, so a
// relabeled row cannot leave translations pointing at stale English.
const enMenu = readJson('en/menu.json')
const menuItems = MenuModel.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
assertEqual(enMenu.root.label, 'Go', 'English menu catalog carries the injected root label')
assert(menuItems.some((item) => item.id === 'setup.language' && item.provider === 'languages'), 'Setup > Language row uses the languages provider')
const staleMenu = menuItems.filter((item) => !enMenu[item.id] || enMenu[item.id].label !== item.label || (item.title && enMenu[item.id].title !== item.title) || (item.description && enMenu[item.id].description !== item.description))
assert(staleMenu.length === 0, 'English menu catalog mirrors the menu definition', JSON.stringify(staleMenu.map((i) => i.id)))
const orphanMenu = Object.keys(enMenu).filter((id) => id !== 'root' && !menuItems.some((item) => item.id === id))
assert(orphanMenu.length === 0, 'English menu catalog has no orphan ids', JSON.stringify(orphanMenu))

// I18N_STRUCTURAL=1 is the pull-request gate: individual PRs only add the
// English side, so missing translations are pending work for the sync
// workflow rather than failures. So are translations the manifest marks
// stale (their English changed since) and orphans awaiting pruning —
// an English-only edit must never wedge on 49 other languages. Structure
// of what IS current must still hold either way.
const structural = process.env.I18N_STRUCTURAL === '1'
const crypto = require('crypto')
const manifest = fs.existsSync(path.join(i18nDir, 'translation-manifest.json')) ? readJson('translation-manifest.json') : {}
// A plural entry hashes as Python's json.dumps(sort_keys=True) writes it.
const canonical = (value) => typeof value === 'string' ? value
  : '{' + Object.keys(value).sort().map((k) => `${JSON.stringify(k)}: ${JSON.stringify(value[k])}`).join(', ') + '}'
const sourceHash = (value) => crypto.createHash('sha256').update(canonical(value), 'utf8').digest('hex').slice(0, 12)
const Plural = requireFromRoot('shell/Commons/Plural.js')
const isStale = (code, unit, englishValue) => !manifest[code] || manifest[code][unit] !== sourceHash(englishValue)
// Only %1-style tokens count, as in scripts/i18n-sync.py: nothing escapes a
// percent sign, and Turkish writes it before the number ("%%2" shows "%80").
const placeholders = (value) => (String(value).match(/%\d/g) || []).sort().join(' ')
function assertCatalogMirrors(kind, english, catalog, code) {
  const problems = []
  const enKeys = Object.keys(english).sort()
  if (!structural && JSON.stringify(Object.keys(catalog).sort()) !== JSON.stringify(enKeys)) problems.push('key set differs')
  if (!structural)
    for (const key of Object.keys(catalog))
      if (!Object.hasOwn(english, key)) problems.push(`${key}: not in the English catalog`)
  for (const key of enKeys) {
    if (!Object.hasOwn(catalog, key)) continue
    if (kind === 'menu') {
      const staleField = (f) => structural && Object.hasOwn(english[key], f) && isStale(code, `menu:${key}.${f}`, english[key][f])
      if (!structural && JSON.stringify(Object.keys(catalog[key]).sort()) !== JSON.stringify(Object.keys(english[key]).sort())) problems.push(`${key}: fields differ`)
      else if (Object.keys(catalog[key]).some((f) => (Object.hasOwn(english[key], f) || !structural) && (typeof catalog[key][f] !== 'string' || catalog[key][f].length === 0))) problems.push(`${key}: invalid field`)
      else if (Object.keys(catalog[key]).some((f) => Object.hasOwn(english[key], f) && placeholders(catalog[key][f]) !== placeholders(english[key][f]) && !staleField(f))) problems.push(`${key}: placeholders differ`)
      else if (!structural && Object.keys(english[key]).some((f) => typeof catalog[key][f] !== 'string' || catalog[key][f].length === 0)) problems.push(`${key}: untranslated field`)
    } else if (english[key] && typeof english[key] === 'object') {
      // A plural entry: the language's categories, "other" with every
      // placeholder, and no form inventing one.
      const stale = structural && isStale(code, `${kind}:${key}`, english[key])
      const forms = catalog[key]
      const expected = placeholders(english[key].other)
      if (!forms || typeof forms !== 'object') { if (!stale) problems.push(`${key}: not plural forms`) }
      else if (!structural && JSON.stringify(Object.keys(forms).sort()) !== JSON.stringify(Plural.categories(code).slice().sort())) problems.push(`${key}: plural categories differ`)
      else if (Object.values(forms).some((form) => typeof form !== 'string' || form.length === 0)) problems.push(`${key}: empty plural form`)
      else if (!stale && (placeholders(forms.other || '') !== expected || Object.values(forms).some((form) => placeholders(form).split(' ').some((p) => p && !expected.split(' ').includes(p))))) problems.push(`${key}: placeholders differ`)
    } else if (typeof catalog[key] !== 'string' || catalog[key].length === 0) problems.push(`${key}: untranslated`)
    else if (placeholders(catalog[key]) !== placeholders(english[key]) && !(structural && isStale(code, `${kind}:${key}`, english[key]))) problems.push(`${key}: placeholders differ`)
    if (problems.length > 5) break
  }
  assert(problems.length === 0, `${code}/${kind}.json ${structural ? 'is structurally sound' : 'mirrors the English catalog'}`, JSON.stringify(problems))
}

const enShell = readJson('en/shell.json')
const enCli = readJson('en/cli.json')
const enKeybindings = readJson('en/keybindings.json')
const readOptional = (rel) => fs.existsSync(path.join(i18nDir, rel)) ? readJson(rel) : {}
for (const code of codes) {
  if (code === 'en') continue
  assertCatalogMirrors('menu', enMenu, readJson(`${code}/menu.json`), code)
  assertCatalogMirrors('shell', enShell, readJson(`${code}/shell.json`), code)
  assertCatalogMirrors('cli', enCli, readJson(`${code}/cli.json`), code)
  assertCatalogMirrors('keybindings', enKeybindings, readOptional(`${code}/keybindings.json`), code)
}

// Every catalog key must be referenced by the code that displays it, and
// every referenced key must exist in the English catalog.
function collectKeys(dir, extensions, pattern) {
  const found = new Set()
  const walk = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name)
      if (entry.isDirectory()) { if (entry.name !== '__pycache__') walk(full) }
      else if (extensions.some((ext) => entry.name.endsWith(ext))) {
        for (const match of fs.readFileSync(full, 'utf8').matchAll(pattern)) found.add(match[1])
      }
    }
  }
  walk(dir)
  return found
}
const shellKeys = collectKeys(path.join(root, 'shell'), ['.qml', '.js'], /(?:I18n\.tn?|[^a-zA-Z_.]tn?|translator\(tr\))\("([a-z][a-zA-Z0-9]*(?:\.[a-zA-Z0-9]+)+)"/g)
const unreferencedShell = Object.keys(enShell).filter((key) => !shellKeys.has(key))
assert(unreferencedShell.length === 0, 'every shell catalog key is referenced', JSON.stringify(unreferencedShell))
const unknownShell = [...shellKeys].filter((key) => !Object.hasOwn(enShell, key))
assert(unknownShell.length === 0, 'every referenced shell key exists in the English catalog', JSON.stringify(unknownShell))

const cliKeys = collectKeys(path.join(root, 'bin'), [''], /omarchy-i18n (?:--count \S+ )?([a-z][a-zA-Z0-9]*(?:\.[a-zA-Z0-9]+)+)/g)
const unreferencedCli = Object.keys(enCli).filter((key) => !cliKeys.has(key))
assert(unreferencedCli.length === 0, 'every cli catalog key is referenced', JSON.stringify(unreferencedCli))
const unknownCli = [...cliKeys].filter((key) => !Object.hasOwn(enCli, key))
assert(unknownCli.length === 0, 'every referenced cli key exists in the English catalog', JSON.stringify(unknownCli))

// applyTranslations: translated labels win, English stays searchable,
// untranslated rows pass through, and nothing mutates the source items.
const defaults = MenuModel.parseMenuJsonc(JSON.stringify({
  setup: { label: 'Setup', aliases: ['settings'] },
  'setup.language': { label: 'Language', provider: 'languages' }
}))
const translated = MenuModel.applyTranslations(defaults, { setup: { label: 'Opsætning' } })
assertEqual(translated[0].label, 'Opsætning', 'applyTranslations replaces the label')
assert(translated[0].searchTerms.includes('Setup') && translated[0].aliases.includes('settings') && !translated[0].aliases.includes('Setup'), 'applyTranslations keeps English searchable but not routable')
assertEqual(translated[1].label, 'Language', 'applyTranslations leaves untranslated rows in English')
assertEqual(defaults[0].label, 'Setup', 'applyTranslations does not mutate its input')
const merged = MenuModel.mergeMenuSources(translated, MenuModel.parseMenuJsonc(JSON.stringify({ setup: { label: 'My Setup' } })))
assertEqual(merged.items.setup.label, 'My Setup', 'a user retitle wins over the translation')
const customRoot = MenuModel.mergeMenuSources(translated, MenuModel.parseMenuJsonc(JSON.stringify({ root: { label: 'My Menu' } })), 'Gå')
assertEqual(customRoot.items.root.label, 'My Menu', 'a user-supplied root heading wins over the catalog label')
const injectedRoot = MenuModel.mergeMenuSources(translated, [], 'Gå')
assertEqual(injectedRoot.items.root.label, 'Gå', 'the injected root heading uses the catalog label')
assertEqual(MenuModel.mergeMenuSources(translated, []).items.root.label, 'Go', 'the injected root heading defaults to Go without a catalog')
assertDeepEqual(MenuModel.applyTranslations(defaults, null), defaults, 'a missing catalog degrades to English')

// Routing must not depend on the display language: English labels live in
// searchTerms, which resolveRoute never reads, so a word that is inert in
// English cannot become a command in another language.
const sampleMenu = { ...enMenu, setup: { label: 'Indstillinger' } }
const enMerged = MenuModel.mergeMenuSources(menuItems, [])
const sampleMerged = MenuModel.mergeMenuSources(MenuModel.applyTranslations(menuItems, sampleMenu), [])
for (const route of ['reboot', 'shutdown', 'logout', 'hibernate', 'lock', 'clock', 'setup', 'settings', 'power-menu', 'language'])
  assertEqual(MenuModel.resolveRoute(sampleMerged.items, sampleMerged.itemOrder, route), MenuModel.resolveRoute(enMerged.items, enMerged.itemOrder, route), `route "${route}" resolves the same when translated as in English`)
assert(MenuModel.nameSearchText(sampleMerged.items.setup).includes('setup'), 'English labels remain searchable when translated')

// JS models translate through the optional tr argument and stay English
// without one (the audio/monitor/clipboard tests assert the same English).
const sampleShell = { ...enShell, 'audio.level.muted': 'Muted (Test)', 'clipboard.screenshotFrom': 'Screenshot from %1 (Test)' }
const tr = (key, english) => sampleShell[key] || english
const audio = requireFromRoot('shell/plugins/panels/audio/Model.js')
assertEqual(audio.outputVolumeName(0.5, true, tr), sampleShell['audio.level.muted'], 'audio levels translate through tr')
const clipboard = requireFromRoot('shell/plugins/clipboard/ClipboardHistory.js')
const sampleRow = clipboard.displayRows([{ type: 'image', path: '/tmp/a.png', mime: 'image/png', capturedAt: 'Friday 14:42' }], '', 50, tr)[0]
assertEqual(sampleRow.previewText, sampleShell['clipboard.screenshotFrom'].replace('%1', 'Friday 14:42'), 'clipboard previews translate through tr')

JS

# --- Plural rules and number formatting agree between shell and CLI ---

# Plural.js (shell) and plural.jq (omarchy-i18n) hold the same CLDR rules;
# compare every language over every count a UI is likely to show, and the
# number formatting the two sides share.
require_command jq
counts='[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,19,20,21,22,25,100,101,102,103,111,112,121,1000,1001,1000000,2000000]'
codes_json=$(jq -c 'keys' "$ROOT/default/i18n/locales.json")
jq_categories=$(jq -c -n -L "$ROOT/default/i18n" --argjson codes "$codes_json" --argjson counts "$counts" \
  'include "plural"; [$codes[] as $c | $counts[] as $n | plural_category($c; $n)]')
jq_numbers=$(jq -c -n -L "$ROOT/default/i18n" --slurpfile registry "$ROOT/default/i18n/locales.json" \
  'include "plural"; [$registry[0] | to_entries[] | .value as $r | ("13.1", "2026", "-0.5") | localize_number($r.decimal; $r.zeroDigit)]')
JQ_CATEGORIES=$jq_categories JQ_NUMBERS=$jq_numbers CODES=$codes_json COUNTS=$counts run_node_test <<'JS'
const fs = require('fs')
const Plural = requireFromRoot('shell/Commons/Plural.js')
const Numbers = requireFromRoot('shell/Commons/Numbers.js')
const codes = JSON.parse(process.env.CODES)
const counts = JSON.parse(process.env.COUNTS)
const shell = codes.flatMap((code) => counts.map((n) => Plural.category(code, n)))
const cli = JSON.parse(process.env.JQ_CATEGORIES)
const disagree = shell.map((c, i) => c === cli[i] ? null : `${codes[Math.floor(i / counts.length)]}:${counts[i % counts.length]} ${c}/${cli[i]}`).filter(Boolean)
assert(disagree.length === 0, 'shell and CLI plural rules agree for every language', JSON.stringify(disagree.slice(0, 5)))

assertEqual(['one', 'few', 'many'].map((_, i) => Plural.category('ru', [21, 22, 25][i])).join(), 'one,few,many', 'Russian counts take one, few, and many')
assertEqual([0, 1, 2, 3, 11, 100].map((n) => Plural.category('ar', n)).join(), 'zero,one,two,few,many,other', 'Arabic counts take all six forms')
assertEqual(Plural.category('fr', 1000000), 'many', 'French millions take their own form')
assertEqual(Plural.categories('ja').join(), 'other', 'Japanese has one form')
assertEqual(Plural.categories('pl').join(), 'one,few,many,other', 'Polish needs one, few, many, and other')
assertEqual(Plural.pick({ one: '%1 file', other: '%1 files' }, 'en', 1), '%1 file', 'pick chooses the form for the count')
assertEqual(Plural.pick({ other: '%1 files' }, 'ru', 2), '%1 files', 'a missing form falls back to other')
assertEqual(Plural.pick('plain', 'ru', 2), 'plain', 'a plain string ignores the count')

const registry = JSON.parse(fs.readFileSync(path.join(root, 'default/i18n/locales.json'), 'utf8'))
const shellNumbers = Object.values(registry).flatMap((r) => ['13.1', '2026', '-0.5'].map((v) => Numbers.format(v, undefined, r.decimal, r.zeroDigit)))
assertDeepEqual(shellNumbers, JSON.parse(process.env.JQ_NUMBERS), 'shell and CLI write numbers the same way in every language')
assertEqual(Numbers.format(13.14, 1, ',', '0'), '13,1', 'formatNumber rounds and uses the decimal separator')
assertEqual(Numbers.format(13.5, 1, '٫', '۰'), '۱۳٫۵', 'formatNumber writes native digits')
assertEqual(Object.values(registry).filter((r) => typeof r.decimal !== 'string' || typeof r.zeroDigit !== 'string').length, 0, 'every registry entry says how it writes numbers')
JS

# --- omarchy-language and omarchy-i18n behavior ---

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export OMARCHY_PATH=$ROOT
export PATH="$ROOT/bin:$PATH"
export OMARCHY_LANGUAGE_FILE=$work/language
export OMARCHY_LOCALE_GEN=$work/locale.gen
export OMARCHY_LOCALE_REGISTRY=$ROOT/default/i18n/locales.json
export XDG_CONFIG_HOME=$work/config
session_env=$XDG_CONFIG_HOME/uwsm/env.d/50-omarchy-language
printf '#en_US.UTF-8 UTF-8\n' >"$OMARCHY_LOCALE_GEN"

# Stub the outside world: locale-gen records its argument, notifications
# record their text, and omarchy-language itself is the real one via PATH.
mkdir -p "$work/stubs"
cat >"$work/stubs/locale-gen" <<'STUB'
#!/bin/bash
echo "$@" >>"$LOCALE_GEN_LOG"
STUB
cat >"$work/stubs/omarchy-notification-send" <<'STUB'
#!/bin/bash
echo "$@" >>"$NOTIFY_LOG"
STUB
cat >"$work/stubs/locale" <<'STUB'
#!/bin/bash
if [[ $1 == "-a" ]]; then echo "en_GB.utf8"; else echo "LANG=en_GB.UTF-8"; fi
STUB
# A fake Hyprland session: the compositor and the shell restart record what
# they were asked, so the test never touches a desktop it runs inside.
cat >"$work/stubs/hyprctl" <<'STUB'
#!/bin/bash
echo "$@" >>"$SESSION_ENV_LOG"
STUB
cat >"$work/stubs/omarchy-restart-shell" <<'STUB'
#!/bin/bash
echo "restart" >>"$SESSION_ENV_LOG"
STUB
# sudo and pkexec record which one elevated and what it ran, then run it
# as-is. sudo answers the long listing (`sudo -n -l -l`) with the
# passwordless grant only when TEST_SUDO_GRANT is set, the way a machine with
# etc/sudoers.d/omarchy-locale-generate installed does.
cat >"$work/stubs/sudo" <<'STUB'
#!/bin/bash
if [[ $1 == "-n" && $2 == "-l" ]]; then
  [[ -n ${TEST_SUDO_GRANT:-} ]] && echo "    Options: !authenticate"
  exit 0
fi
flag=""
if [[ $1 == "-n" ]]; then flag=" -n"; shift; fi
echo "sudo$flag $(basename "$1") $2" >>"$ELEVATE_LOG"
exec "$@"
STUB
cat >"$work/stubs/pkexec" <<'STUB'
#!/bin/bash
echo "pkexec $(basename "$1") $2" >>"$ELEVATE_LOG"
exec "$@"
STUB
chmod +x "$work/stubs/"*
export PATH="$work/stubs:$PATH"
export LOCALE_GEN_LOG=$work/locale-gen.log NOTIFY_LOG=$work/notify.log ELEVATE_LOG=$work/elevate.log SESSION_ENV_LOG=$work/session-env.log
export HYPRLAND_INSTANCE_SIGNATURE=test
: >"$LOCALE_GEN_LOG"; : >"$NOTIFY_LOG"; : >"$ELEVATE_LOG"; : >"$SESSION_ENV_LOG"

assert_bash_equal() {
  if [[ $1 != "$2" ]]; then
    fail "$3" "expected [$2], got [$1]"
  fi
  pass "$3"
}

assert_bash_equal "$(omarchy-language)" "en" "omarchy-language defaults to English with no language file"
echo "bogus" >"$OMARCHY_LANGUAGE_FILE"
assert_bash_equal "$(omarchy-language)" "en" "omarchy-language falls back to English for an unknown code"
rm -f "$OMARCHY_LANGUAGE_FILE"

list=$(omarchy-language list)
assert_bash_equal "$(printf '%s\n' "$list" | wc -l)" "1" "omarchy-language list prints 1 row"
assert_bash_equal "$(printf '%s\n' "$list" | head -n 1 | cut -f2)" "en" "omarchy-language list puts English first"
assert_bash_equal "$(omarchy-language locale en)" "en_US.UTF-8" "omarchy-language locale maps en to its glibc locale"

# stdin is not a tty here, as when picked from the menu, and this machine has
# no passwordless grant, so generating the locale asks through polkit.
omarchy-language en </dev/null
assert_bash_equal "$(cat "$ELEVATE_LOG")" "pkexec omarchy-locale-generate en" "without the grant, the menu generates the locale through pkexec"
assert_bash_equal "$(cat "$OMARCHY_LANGUAGE_FILE")" "en" "omarchy-language persists the choice"
assert_bash_equal "$(omarchy-language)" "en" "omarchy-language reads the persisted choice"
assert_bash_equal "$(grep '^export LANG=' "$session_env")" "export LANG=en_US.UTF-8" "omarchy-language sets the session LANG through uwsm for the next login"
assert_bash_equal "$(cat "$SESSION_ENV_LOG")" $'eval hl.env("LANG", "en_US.UTF-8", true)\nrestart' "omarchy-language hands the new LANG to Hyprland and services, then respawns the shell from it"
assert_bash_equal "$(grep '^en_US' "$OMARCHY_LOCALE_GEN")" "en_US.UTF-8 UTF-8" "omarchy-language enables the locale in locale.gen"
assert_bash_equal "$(cat "$LOCALE_GEN_LOG")" "en_US.UTF-8" "omarchy-language generates the locale"

if omarchy-language xx </dev/null 2>/dev/null; then
  fail "omarchy-language rejects unknown codes"
else
  pass "omarchy-language rejects unknown codes"
fi

en_changed=$(jq -r '."language.changed"' "$ROOT/default/i18n/en/cli.json" | sed 's/%1/English/')
assert_bash_equal "$(omarchy-i18n language.changed 'English')" "$en_changed" "omarchy-i18n prints the current language with substitution"
assert_bash_equal "$(omarchy-i18n missing.key)" "missing.key" "omarchy-i18n passes unknown keys through"

grep -q "$en_changed" "$NOTIFY_LOG" && pass "the language-change notification arrives in the new language" || fail "the language-change notification arrives in the new language" "notify log: $(cat "$NOTIFY_LOG")"

en_battery=$(jq -r '."battery.lowBody"' "$ROOT/default/i18n/en/cli.json" | sed 's/%1/12/')
assert_bash_equal "$(omarchy-i18n battery.lowBody 12)" "$en_battery" "omarchy-i18n substitutes %1 and keeps a literal percent sign"

# Plural entries pick their form by count, and plain-number arguments take
# the language's decimal separator and digits.
plural_root=$work/plural-root
mkdir -p "$plural_root/default/i18n/en" "$plural_root/default/i18n/ru" "$plural_root/default/i18n/fa"
cp "$ROOT/default/i18n/plural.jq" "$plural_root/default/i18n/"
cat >"$plural_root/default/i18n/locales.json" <<'EOF'
{
  "en": {"name": "English", "locale": "en_US.UTF-8", "decimal": ".", "zeroDigit": "0"},
  "ru": {"name": "Russian", "locale": "ru_RU.UTF-8", "decimal": ",", "zeroDigit": "0"},
  "fa": {"name": "Persian", "locale": "fa_IR.UTF-8", "decimal": "٫", "zeroDigit": "۰"}
}
EOF
printf '{"files.count": {"one": "%%1 file", "other": "%%1 files"}, "power.rate": "%%1 W"}\n' >"$plural_root/default/i18n/en/cli.json"
printf '{"files.count": {"one": "%%1 файл", "few": "%%1 файла", "many": "%%1 файлов", "other": "%%1 файла"}, "power.rate": "%%1 Вт"}\n' >"$plural_root/default/i18n/ru/cli.json"
printf '{}\n' >"$plural_root/default/i18n/fa/cli.json"
plural() { echo "$1" >"$work/plural-language"; OMARCHY_PATH=$plural_root OMARCHY_LANGUAGE_FILE=$work/plural-language omarchy-i18n "${@:2}"; }
assert_bash_equal "$(plural en --count 1 files.count 1)" "1 file" "omarchy-i18n --count picks the English singular"
assert_bash_equal "$(plural en --count 3 files.count 3)" "3 files" "omarchy-i18n --count picks the English plural"
assert_bash_equal "$(plural ru --count 21 files.count 21) / $(plural ru --count 22 files.count 22) / $(plural ru --count 25 files.count 25)" "21 файл / 22 файла / 25 файлов" "omarchy-i18n --count follows Russian plural rules"
assert_bash_equal "$(plural ru files.count 5)" "5 файла" "a plural entry without --count reads its other form"
assert_bash_equal "$(plural ru power.rate 13.1)" "13,1 Вт" "a number argument takes the language's decimal separator"
assert_bash_equal "$(plural fa --count 2 files.count 13.5)" "۱۳٫۵ files" "a number argument takes the language's digits, with the English entry as fallback"
assert_bash_equal "$(plural ru power.rate 10.0.0.1)" "10.0.0.1 Вт" "an argument that is not a plain number passes through"
assert_bash_equal "$(plural ru --number 13.1) $(plural fa --number 13.5)" "13,1 ۱۳٫۵" "omarchy-i18n --number writes one number in the language"
assert_bash_equal "$(plural en power.rate --foo) | $(plural en power.rate -n)" "--foo W | -n W" "an argument that starts with a dash is text, not a jq option"
if plural en --count many files.count 2>/dev/null; then
  fail "omarchy-i18n rejects a non-numeric count"
else
  pass "omarchy-i18n rejects a non-numeric count"
fi

en_changed_raw=$(jq -r '."language.changed"' "$ROOT/default/i18n/en/cli.json")
assert_bash_equal "$(omarchy-i18n language.changed 'Research & Development')" "${en_changed_raw//%1/"Research & Development"}" "omarchy-i18n keeps ampersands in arguments literal"

# With the locale already generated, picking the language needs no
# privilege at all: no password prompt, no locale-gen.
cat >"$work/stubs/locale" <<'STUB'
#!/bin/bash
if [[ $1 == "-a" ]]; then printf 'en_US.utf8\n'; else echo "LANG=en_US.UTF-8"; fi
STUB
chmod +x "$work/stubs/locale"
: >"$LOCALE_GEN_LOG"; : >"$ELEVATE_LOG"; : >"$SESSION_ENV_LOG"
rm -f "$OMARCHY_LANGUAGE_FILE"
omarchy-language en </dev/null
assert_bash_equal "$(cat "$OMARCHY_LANGUAGE_FILE")" "en" "already-applied locale switches without elevating"
assert_bash_equal "$(cat "$LOCALE_GEN_LOG")" "" "already-generated locale is not regenerated"
assert_bash_equal "$(cat "$ELEVATE_LOG")" "" "no password prompt when nothing privileged is needed"
assert_bash_equal "$(head -n 1 "$SESSION_ENV_LOG")" 'eval hl.env("LANG", "en_US.UTF-8", true)' "an already-generated locale still reaches the session"

# With etc/sudoers.d/omarchy-locale-generate installed, a language whose locale
# isn't generated yet still switches from the menu without any password
# prompt: the helper runs through sudo -n, never polkit.
cat >"$work/stubs/locale" <<'STUB'
#!/bin/bash
if [[ $1 == "-a" ]]; then echo "en_GB.utf8"; else echo "LANG=en_GB.UTF-8"; fi
STUB
: >"$LOCALE_GEN_LOG"; : >"$ELEVATE_LOG"
TEST_SUDO_GRANT=1 omarchy-language en </dev/null
assert_bash_equal "$(cat "$ELEVATE_LOG")" "sudo -n omarchy-locale-generate en" "with the grant, a new language generates its locale without a password prompt"
assert_bash_equal "$(cat "$LOCALE_GEN_LOG")" "en_US.UTF-8" "the passwordless helper generates the language's locale"
assert_bash_equal "$(cat "$OMARCHY_LANGUAGE_FILE")" "en" "the passwordless switch persists the choice"

# A non-CJK language leaves the CJK glyph forms alone.
cjk_font=$XDG_CONFIG_HOME/fontconfig/conf.d/50-omarchy-input-method.conf
[[ ! -e $cjk_font ]] && pass "a non-CJK language leaves the CJK glyph forms alone" || fail "a non-CJK language leaves the CJK glyph forms alone"

# A cancelled polkit prompt must not persist the choice, or the interface
# would switch with LANG left behind.
cat >"$work/stubs/pkexec" <<'STUB'
#!/bin/bash
exit 126
STUB
cat >"$work/stubs/locale" <<'STUB'
#!/bin/bash
if [[ $1 == "-a" ]]; then echo "en_GB.utf8"; else echo "LANG=en_GB.UTF-8"; fi
STUB
rm -f "$OMARCHY_LANGUAGE_FILE" "$session_env"
if omarchy-language en </dev/null 2>/dev/null; then
  fail "a cancelled password prompt fails the switch"
else
  pass "a cancelled password prompt fails the switch"
fi
[[ ! -f $OMARCHY_LANGUAGE_FILE && ! -f $session_env ]] && pass "the choice is not persisted before the locale exists" || fail "the choice is not persisted before the locale exists"

# Every registry locale must be one glibc can actually generate.
if [[ -f /usr/share/i18n/SUPPORTED ]]; then
  unsupported=""
  while read -r loc; do
    grep -qE "^${loc%.UTF-8}(\.UTF-8)? UTF-8" /usr/share/i18n/SUPPORTED || unsupported="$unsupported $loc"
  done < <(jq -r '.[].locale' "$ROOT/default/i18n/locales.json")
  assert_bash_equal "$unsupported" "" "every registry locale exists in glibc SUPPORTED"
else
  skip "every registry locale exists in glibc SUPPORTED"
fi
