# Regenerate the vendored Andrews 1865 dictionary from Internet Archive OCR.
# Output is a sorted plain-text master that gets staticRead-embedded into the
# binary at compile time. Run only when updating the dictionary itself.
#
# Generates:
#   src-asset/andrews1865.txt — vendored, hand-editable, embedded at build
#
# Usage: nimble importAndrews

import std/[httpclient, strutils, os, tables, algorithm, sequtils]
import wehe/decompose

const
  djvuUrl  = "https://archive.org/download/dictionaryofhawa00andrrich/dictionaryofhawa00andrrich_djvu.txt"
  rawCache = ".cache/andrews1865_djvu.txt"
  txtOut   = "src-asset/andrews1865.txt"

# POS abbreviations found in Andrews 1865
const posAbbrevs = [
  "s.", "v.", "adj.", "adv.", "prep.", "conj.", "int.", "num.",
  "pron.", "part.", "interj.", "Ss.", "Sv.", "S.", "V.",  # OCR variants
]

proc looksLikePOS(s: string): bool =
  let t = s.strip
  for p in posAbbrevs:
    if t.startsWith(p): return true
  false

proc isEntryLine(line: string): bool =
  ## True when a line opens a dictionary entry.
  ## Pattern: HEADWORD, pos. definition
  ## where HEADWORD starts uppercase and contains mostly letters+hyphens.
  if line.len < 4 or not line[0].isUpperAscii: return false
  # First word (before comma): must look like a Hawaiian headword
  let commaPos = line.find(',')
  if commaPos < 1: return false
  let head = line[0 ..< commaPos]
  # Must consist only of letters and hyphens (no spaces inside headword)
  if head.contains(' '): return false
  for c in head:
    if c notin {'A'..'Z', 'a'..'z', '-', '\''}: return false
  # After comma: must be a POS abbreviation
  looksLikePOS(line[commaPos + 1 .. ^1])

proc cleanHeadword(raw: string): string =
  ## Normalize OCR small-caps headword to plain lowercase.
  ## Hawaiian has no V; 'V' in small-caps OCR is always misread 'U'.
  var s = raw.replace("-", "")
  # In the headword context: v/V → u (Hawaiian has no 'v')
  # Apply to uppercase then lowercase to catch both OCR renderings
  s = s.toUpperAscii.replace("V", "U").toLower
  s

proc isPageHeader(line: string): bool =
  ## Section headers like "AUP" or "HAW" that appear as pagination artifacts.
  ## Filter: short, all-uppercase, no punctuation.
  if line.len > 6 or line.len < 2: return false
  for c in line:
    if not c.isUpperAscii: return false
  true

proc fetchOrLoad(): string =
  if fileExists(rawCache):
    stderr.writeLine "using cached " & rawCache
    return readFile(rawCache)
  stderr.writeLine "downloading Andrews 1865 OCR..."
  let client = newHttpClient()
  client.headers = newHttpHeaders({
    "User-Agent": "wehe/1.0 (personal research; andrews1865 public domain)"
  })
  defer: client.close()
  result = client.getContent(djvuUrl)
  createDir(".cache")
  writeFile(rawCache, result)
  stderr.writeLine "cached to " & rawCache

proc parseAndrews(text: string): OrderedTable[string, seq[string]] =
  ## Returns: normalized_key → seq[full_entry_text]
  ## (multiple senses of same headword are separate seq items)
  var entries = initOrderedTable[string, seq[string]]()
  var curKey = ""
  var curLines: seq[string]

  proc commit() =
    if curKey.len == 0 or curLines.len == 0: return
    let def = curLines.join(" ").strip
    if def.len < 5: return  # skip noise
    if curKey notin entries:
      entries[curKey] = @[]
    entries[curKey].add(def)

  for raw in text.splitLines:
    let line = raw.strip
    if line.len == 0: continue
    if isPageHeader(line): continue

    if isEntryLine(line):
      commit()
      let commaPos = line.find(',')
      let rawHw = line[0 ..< commaPos]
      curKey = normalizeKey(cleanHeadword(rawHw))
      curLines = @[line]
    elif curKey.len > 0:
      curLines.add(line)

  commit()
  entries

proc writeTxt(entries: OrderedTable[string, seq[string]]) =
  var f = open(txtOut, fmWrite)
  f.writeLine "# Andrews 1865 Hawaiian Dictionary"
  f.writeLine "# Lorrin Andrews. Honolulu: Henry M. Whitney, 1865."
  f.writeLine "# Public domain. OCR: Internet Archive / dictionaryofhawa00andrrich."
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
  let text = fetchOrLoad()
  stderr.writeLine "parsing..."
  let entries = parseAndrews(text)
  let total = entries.len
  let senses = toSeq(entries.values).mapIt(it.len).foldl(a + b, 0)
  stderr.writeLine $total & " headwords, " & $senses & " total senses"
  writeTxt(entries)
  echo "done"

main()
