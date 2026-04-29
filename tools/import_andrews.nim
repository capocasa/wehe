# Regenerate the vendored Andrews-Parker 1922 dictionary from Internet Archive
# OCR. Output is a sorted plain-text master that gets staticRead-embedded into
# the binary at compile time. Run only when updating the dictionary itself.
#
# Source: Lorrin Andrews, A Dictionary of the Hawaiian Language, revised by
# Henry H. Parker. Honolulu: Board of Commissioners of Public Archives, 1922.
# Public domain (US, pre-1923). Internet Archive: ofhawadictionary00andrrich.
#
# Generates:
#   src-asset/andrews1922.txt — vendored, hand-editable, embedded at build
#
# Usage: nimble importAndrews

import std/[httpclient, strutils, tables, algorithm, sequtils]
import wehe/decompose

const
  djvuUrl = "https://archive.org/download/ofhawadictionary00andrrich/ofhawadictionary00andrrich_djvu.txt"
  txtOut  = "src-asset/andrews1922.txt"
  bodyStartMarker = "HAWAIIAN  LANGUAGE"   # second occurrence: just before "A (a). ..."
  bodyEndMarker   = "HAWAIIAN    PLACE    NAMES"

proc isEntryLine(line: string): bool =
  ## True when a line opens a dictionary entry.
  ## Pattern: `Headword  (syl-la'-bi-fi'-ca'-tion)[,.] [pos.] ...`
  ## Headword starts uppercase ASCII, is one word, followed by spaces and an
  ## opening paren. Inside the parens is the syllable/stress notation.
  if line.len < 5 or not line[0].isUpperAscii: return false
  # First token must be alphabetical (Hawaiian headword, no spaces or digits)
  var i = 0
  while i < line.len and line[i] in {'A'..'Z', 'a'..'z'}: inc i
  if i < 2: return false                             # need at least 2 letters
  if i >= line.len or line[i] != ' ': return false   # must be followed by space
  # Skip whitespace, expect '('
  while i < line.len and line[i] == ' ': inc i
  if i >= line.len or line[i] != '(': return false
  # Find the closing ')'
  let close = line.find(')', i)
  if close < 0: return false
  # After ')' we expect ',' or '.' (some entries use '.', e.g. `A (a). ...`)
  if close + 1 >= line.len: return false
  if line[close + 1] notin {',', '.'}: return false
  true

proc extractHeadword(line: string): string =
  ## Pull the first token (the raw headword) off an entry line.
  var i = 0
  while i < line.len and line[i] in {'A'..'Z', 'a'..'z'}: inc i
  line[0 ..< i]

proc isPageHeader(line: string): bool =
  ## OCR pagination artifact: short, all-uppercase, no punctuation.
  if line.len > 8 or line.len < 2: return false
  for c in line:
    if not c.isUpperAscii: return false
  true

proc collapseSpaces(s: string): string =
  ## OCR has runs of whitespace; squash them.
  result = newStringOfCap(s.len)
  var prevSpace = false
  for c in s:
    if c == ' ' or c == '\t':
      if not prevSpace:
        result.add ' '
        prevSpace = true
    else:
      result.add c
      prevSpace = false

proc fetch(): string =
  stderr.writeLine "downloading Andrews-Parker 1922 OCR..."
  let client = newHttpClient()
  client.headers = newHttpHeaders({
    "User-Agent": "wehe/1.0 (personal research; andrews-parker 1922 public domain)"
  })
  defer: client.close()
  client.getContent(djvuUrl)

proc parseAndrews(text: string): OrderedTable[string, seq[string]] =
  ## Returns: normalized_key → seq[full_entry_text]
  ## (multiple senses of same headword become separate seq items)
  var entries = initOrderedTable[string, seq[string]]()
  var curKey = ""
  var curLines: seq[string]
  var inBody = false
  var bodyStartHits = 0

  proc commit() =
    if curKey.len == 0 or curLines.len == 0: return
    let def = collapseSpaces(curLines.join(" ")).strip
    if def.len < 5: return
    if curKey notin entries:
      entries[curKey] = @[]
    entries[curKey].add(def)

  for raw in text.splitLines:
    let line = raw.strip
    if line.len == 0: continue

    if not inBody:
      # Skip front matter; body starts at the SECOND `HAWAIIAN  LANGUAGE`
      # header (the first is on the title page).
      if line == bodyStartMarker:
        inc bodyStartHits
        if bodyStartHits >= 2: inBody = true
      continue

    # Stop at place-names section (different format).
    if line.startsWith(bodyEndMarker):
      break

    if isPageHeader(line): continue

    if isEntryLine(line):
      commit()
      curKey = normalizeKey(extractHeadword(line).toLower)
      curLines = @[line]
    elif curKey.len > 0:
      curLines.add(line)

  commit()
  entries

proc writeTxt(entries: OrderedTable[string, seq[string]]) =
  var f = open(txtOut, fmWrite)
  f.writeLine "# Andrews-Parker 1922 Hawaiian Dictionary"
  f.writeLine "# Lorrin Andrews, revised by Henry H. Parker."
  f.writeLine "# Honolulu: Board of Commissioners of Public Archives, 1922."
  f.writeLine "# Public domain. OCR: Internet Archive / ofhawadictionary00andrrich."
  f.writeLine ""
  let keys = toSeq(entries.keys).sorted
  for key in keys:
    f.writeLine key
    for sense in entries[key]:
      f.writeLine "  " & sense
    f.writeLine ""
  f.close()
  stderr.writeLine "wrote " & txtOut

proc main() =
  let text = fetch()
  stderr.writeLine "parsing..."
  let entries = parseAndrews(text)
  let total = entries.len
  let senses = toSeq(entries.values).mapIt(it.len).foldl(a + b, 0)
  stderr.writeLine $total & " headwords, " & $senses & " total senses"
  writeTxt(entries)
  echo "done"

main()
