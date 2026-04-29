import std/[os, strutils, tables, algorithm, sequtils, json, uri]
import mummy, mummy/routers
import wehe/decompose

const Version = staticRead("../wehe.nimble").splitLines().filterIt(it.startsWith("version")).
    mapIt(it.split("=")[1].strip().strip(chars = {'"'}))[0]

const Usage = """
wehe, Hawaiian word decomposition daemon

Usage:
  wehe [--port N] [--origin URL ...]
  wehe -h | --help
  wehe -v | --version

Options:
  --port N        Port to listen on (default: 8765)
  --origin URL    Allowed CORS origin (repeatable). Default: * (any).
                  Pass an exact origin like https://example.com to restrict.
  -h, --help      Show this help and exit
  -v, --version   Show version and exit

Endpoints:
  GET /api/lookup?q=WORD         syllabification + sub-word matches
  GET /api/autocomplete?q=PFX    top 10 prefix matches
"""

proc die(msg: string, code = 2) {.noreturn.} =
  stderr.writeLine "wehe: " & msg
  quit code

type
  Match* = tuple[word: string; definition: string]
  Dict   = object
    tab:  Table[string, seq[Match]]
    keys: seq[string]   # sorted, for prefix search

const embeddedDict = staticRead("../src-asset/andrews1922.txt")

proc parseDict(text: string): Dict =
  var tab = initTable[string, seq[Match]]()
  var cur = ""
  for line in text.splitLines:
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
  for m in lookup(d, word):
    result.add m
  var rest: seq[Match]
  let key = normalizeKey(word)
  for cand in candidates(word):
    if normalizeKey(cand) == key: continue
    rest.add lookup(d, cand)
  rest.sort(proc(a, b: Match): int =
    cmp(syllabify(b.word).len, syllabify(a.word).len))
  result.add rest

let dict = parseDict(embeddedDict)

var allowedOrigins: seq[string] = @[]

proc corsHeaders(request: Request): HttpHeaders =
  result.add(("Access-Control-Allow-Methods", "GET, OPTIONS"))
  if allowedOrigins.len == 0:
    result.add(("Access-Control-Allow-Origin", "*"))
    return
  result.add(("Vary", "Origin"))
  let origin = request.headers["Origin"]
  if origin.len > 0 and origin in allowedOrigins:
    result.add(("Access-Control-Allow-Origin", origin))

proc jsonHeaders(request: Request): HttpHeaders =
  result = corsHeaders(request)
  result.add(("Content-Type", "application/json; charset=utf-8"))

proc qparam(request: Request, name: string): string =
  let parts = request.uri.split('?', 1)
  if parts.len < 2: return ""
  for pair in parts[1].split('&'):
    let kv = pair.split('=', 1)
    if kv.len == 2 and kv[0] == name:
      return decodeUrl(kv[1])

proc apiLookup(request: Request) {.gcsafe.} =
  {.cast(gcsafe).}:
    let q = request.qparam("q")
    var sylls = newJArray()
    for s in syllabify(q): sylls.add(%s)
    var hits = newJArray()
    for m in decomposeLookup(dict, q):
      hits.add(%*{"word": m.word, "definition": m.definition})
    request.respond(200, jsonHeaders(request),
      $(%*{"query": q, "syllables": sylls, "matches": hits}))

proc apiAutocomplete(request: Request) {.gcsafe.} =
  {.cast(gcsafe).}:
    let prefix = request.qparam("q")
    if prefix.len == 0:
      request.respond(200, jsonHeaders(request), "[]"); return
    let norm = normalizeKey(prefix)
    var lo = 0; var hi = dict.keys.len
    while lo < hi:
      let mid = (lo + hi) div 2
      if dict.keys[mid] < norm: lo = mid + 1
      else: hi = mid
    var words = newJArray()
    var i = lo
    while i < dict.keys.len and words.len < 10:
      if dict.keys[i].startsWith(norm):
        words.add(%dict.keys[i])
        inc i
      else: break
    request.respond(200, jsonHeaders(request), $words)

proc handleOptions(request: Request) {.gcsafe.} =
  {.cast(gcsafe).}:
    var headers = corsHeaders(request)
    let reqHeaders = request.headers["Access-Control-Request-Headers"]
    if reqHeaders.len > 0:
      headers.add(("Access-Control-Allow-Headers", reqHeaders))
    request.respond(204, headers, "")

var port = 8765
var i = 1
while i <= paramCount():
  case paramStr(i)
  of "-h", "--help":
    stdout.write Usage
    quit 0
  of "-v", "--version":
    echo "wehe " & Version
    quit 0
  of "--port":
    inc i
    if i > paramCount(): die "--port requires a value"
    try: port = parseInt(paramStr(i))
    except ValueError: die "--port: not an integer: " & paramStr(i)
  of "--origin":
    inc i
    if i > paramCount(): die "--origin requires a value"
    allowedOrigins.add paramStr(i)
  else:
    die "unknown argument: " & paramStr(i)
  inc i

var router: Router
router.get("/api/lookup", apiLookup)
router.get("/api/autocomplete", apiAutocomplete)
router.options("/api/lookup", handleOptions)
router.options("/api/autocomplete", handleOptions)

let server = newServer(router)
let originMsg =
  if allowedOrigins.len == 0: "any origin"
  else: "origins: " & allowedOrigins.join(", ")
stderr.writeLine "wehe loaded " & $dict.keys.len & " headwords, listening on :" &
  $port & " (" & originMsg & ")"
server.serve(Port(port))
