import std/[unicode, strutils]

# Hawaiian consonants (ASCII) and okina variants (Unicode glottal stop)
const consonants = {'h', 'k', 'l', 'm', 'n', 'p', 'w'}
const okinas     = [Rune(0x02BB), Rune(0x02BC), Rune(0x2018), Rune(0x0027)]
const vowelsAscii = {'a', 'e', 'i', 'o', 'u'}
# ā ē ī ō ū (lower) + Ā Ē Ī Ō Ū (upper, just in case)
const macronVowels = [0x0101, 0x0113, 0x012B, 0x014D, 0x016B,
                      0x0100, 0x0112, 0x012A, 0x014C, 0x016A]

proc isConsonant(r: Rune): bool =
  if r.ord < 128: char(r.ord) in consonants
  else: r in okinas

proc isVowel(r: Rune): bool =
  if r.ord < 128: char(r.ord) in vowelsAscii
  else: r.ord in macronVowels

proc syllabify*(word: string): seq[string] =
  ## Split a Hawaiian word into its CV/V syllables.
  let runes = word.toRunes
  var i = 0
  while i < runes.len:
    if isConsonant(runes[i]):
      if i + 1 < runes.len and isVowel(runes[i + 1]):
        result.add($runes[i] & $runes[i + 1])
        i += 2
      else:
        i += 1  # bare consonant — skip (malformed input)
    elif isVowel(runes[i]):
      result.add($runes[i])
      i += 1
    else:
      i += 1  # punctuation or unknown — skip

proc candidates*(word: string): seq[string] =
  ## All candidate sub-units for the word-game lookup.
  ## Includes individual syllables, doubled syllables, and all contiguous
  ## multi-syllable substrings (plus their doubled forms).
  let sylls = syllabify(word)
  if sylls.len == 0:
    return @[]

  var seen: seq[string]

  proc add(s: string) =
    if s notin seen: seen.add(s)

  for length in 1..sylls.len:
    for start in 0..sylls.len - length:
      let sub = sylls[start ..< start + length].join("")
      add(sub)
      add(sub & sub)  # doubled form

  result = seen

proc effectiveSyl*(word: string): tuple[count: int, root: string, doubled: bool] =
  ## If `word` is a clean doubling (its syllables split into two equal halves),
  ## returns (half-count, root, true) — e.g. wehewehe → (2, "wehe", true),
  ## lolo → (1, "lo", true). Otherwise returns (full-count, word, false).
  ## Used to sort doubled forms next to their root.
  let sylls = syllabify(word)
  let n = sylls.len
  if n >= 2 and n mod 2 == 0:
    let half = n div 2
    if sylls[0 ..< half] == sylls[half ..< n]:
      return (half, sylls[0 ..< half].join(""), true)
  (n, word, false)

proc normalizeKey*(s: string): string =
  ## Produce the headword_norm key: lowercase, macrons stripped, okina removed.
  ## Must match the normalization used when building dict.db.
  result = s.toLower
  for pair in [("ā","a"),("ē","e"),("ī","i"),("ō","o"),("ū","u")]:
    result = result.replace(pair[0], pair[1])
  for ok in ["ʻ","ʼ","'","ʻ"]:
    result = result.replace(ok, "")
