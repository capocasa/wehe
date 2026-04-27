import std/[os, strutils, terminal, tables, algorithm, sequtils,
            asynchttpserver, asyncdispatch, json, uri]
import wehe/decompose

type
  Match* = tuple[word: string; definition: string]
  Dict   = object
    tab:  Table[string, seq[Match]]
    keys: seq[string]   # sorted, for prefix search

# ─── Dictionary ───────────────────────────────────────────────────────────────

proc loadDict*(path: string): Dict =
  var tab = initTable[string, seq[Match]]()
  var cur = ""
  for line in path.lines:
    if line.len == 0 or line.startsWith('#'):
      cur = ""; continue
    if line.startsWith("  "):
      if cur.len > 0:
        let def = line.strip
        if def.len > 0:
          tab.mgetOrPut(cur, @[]).add((cur, def))
    else:
      cur = line.strip
  result.tab  = tab
  result.keys = toSeq(tab.keys).sorted

proc lookup*(d: Dict; word: string): seq[Match] =
  let key = normalizeKey(word)
  if key in d.tab: result = d.tab[key]

proc decomposeLookup*(d: Dict; word: string): seq[Match] =
  for cand in candidates(word):
    result.add lookup(d, cand)

# ─── CLI display ──────────────────────────────────────────────────────────────

proc wordWrap(text: string; width: int; indent: int): string =
  let pad = ' '.repeat(indent)
  var line = pad
  for word in text.splitWhitespace():
    if line.len + word.len + 1 > width and line.strip.len > 0:
      result.add(line.strip(trailing = false) & "\n")
      line = pad & word
    else:
      if line == pad: line.add(word)
      else: line.add(" " & word)
  if line.strip.len > 0:
    result.add(line.strip(trailing = false))

proc printMatch(m: Match; width: int; color: bool) =
  if color: stdout.styledWriteLine(styleBright, m.word)
  else: echo m.word
  echo wordWrap(m.definition, width, 2)

# ─── HTTP daemon ──────────────────────────────────────────────────────────────

proc jhdr(): HttpHeaders =
  newHttpHeaders([
    ("Content-Type", "application/json; charset=utf-8"),
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Methods", "GET, OPTIONS"),
  ])

proc fhdr(ct: string): HttpHeaders =
  newHttpHeaders([("Content-Type", ct), ("Access-Control-Allow-Origin", "*")])

proc qparam(query, key: string): string =
  for (k, v) in decodeQuery(query):
    if k == key: return v

proc apiLookup(d: Dict; q: string): string =
  var sylls = newJArray()
  for s in syllabify(q): sylls.add(%s)
  var hits = newJArray()
  for m in decomposeLookup(d, q):
    hits.add(%*{"word": m.word, "definition": m.definition})
  $(%*{"query": q, "syllables": sylls, "matches": hits})

proc apiAutocomplete(d: Dict; prefix: string): string =
  if prefix.len == 0: return "[]"
  let norm = normalizeKey(prefix)
  # Binary search for first key >= norm
  var lo = 0; var hi = d.keys.len
  while lo < hi:
    let mid = (lo + hi) div 2
    if d.keys[mid] < norm: lo = mid + 1
    else: hi = mid
  var words = newJArray()
  var i = lo
  while i < d.keys.len and words.len < 10:
    if d.keys[i].startsWith(norm):
      words.add(%d.keys[i])
      inc i
    else: break
  $words

proc serveStatic(path, webDir: string): (HttpCode, string, string) =
  var rel = if path == "" or path == "/": "index.html" else: path[1..^1]
  if ".." in rel: return (Http404, "{}", "application/json")
  let full = webDir / rel
  if not fileExists(full): return (Http404, "{}", "application/json")
  let ct = case full.splitFile.ext.toLowerAscii
    of ".html": "text/html; charset=utf-8"
    of ".css":  "text/css; charset=utf-8"
    of ".js":   "application/javascript"
    of ".svg":  "image/svg+xml"
    of ".png":  "image/png"
    of ".ico":  "image/x-icon"
    else:       "application/octet-stream"
  (Http200, readFile(full), ct)

proc serveMode(port: int; dictPath, webDir: string) =
  if not fileExists(dictPath):
    stderr.writeLine "error: dictionary not found at " & dictPath
    stderr.writeLine "run: nimble importAndrews"
    quit(1)
  let d = loadDict(dictPath)
  stderr.writeLine "loaded " & $d.keys.len & " headwords"
  var server = newAsyncHttpServer()

  proc cb(req: Request) {.async.} =
    if req.reqMethod == HttpOptions:
      await req.respond(Http200, "", jhdr()); return
    case req.url.path
    of "/api/lookup":
      await req.respond(Http200, apiLookup(d, qparam(req.url.query, "q")), jhdr())
    of "/api/autocomplete":
      await req.respond(Http200, apiAutocomplete(d, qparam(req.url.query, "q")), jhdr())
    else:
      if webDir.len > 0:
        let (code, body, ct) = serveStatic(req.url.path, webDir)
        await req.respond(code, body, fhdr(ct))
      else:
        await req.respond(Http404, "{}", jhdr())

  stderr.writeLine "wehe listening on :" & $port
  waitFor server.serve(Port(port), cb)

# ─── CLI ──────────────────────────────────────────────────────────────────────

proc main() =
  if paramCount() >= 1 and paramStr(1) == "serve":
    var port     = 8765
    var dictPath = "build/andrews1865.txt"
    var webDir   = ""
    var i = 2
    while i <= paramCount():
      case paramStr(i)
      of "--port": inc i; port = parseInt(paramStr(i))
      of "--db":   inc i; dictPath = paramStr(i)
      of "--web":  inc i; webDir = paramStr(i)
      else: discard
      inc i
    serveMode(port, dictPath, webDir)
    return

  if paramCount() < 1:
    stderr.writeLine "usage: wehe <word> [dict]"
    stderr.writeLine "       wehe serve [--port N] [--db PATH] [--web DIR]"
    quit(1)

  let word     = paramStr(1)
  let dictPath = if paramCount() >= 2: paramStr(2) else: "build/andrews1865.txt"
  if not fileExists(dictPath):
    stderr.writeLine "error: dictionary not found at " & dictPath
    stderr.writeLine "run: nimble importAndrews"
    quit(1)

  let d = loadDict(dictPath)
  let matches = decomposeLookup(d, word)
  if matches.len == 0:
    echo "(no matches)"
    return

  let width = if isatty(stdout): terminalWidth() else: 80
  let color = isatty(stdout)
  for i, m in matches:
    if i > 0: echo ""
    printMatch(m, width, color)

when isMainModule:
  main()
