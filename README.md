# wehe

Hawaiian word decomposition. Uncovers the hidden — that's what *wehe* means,
and it's also what the tool does to a word.

Hawaiian phonology is regular: every syllable is CV or V, every word a stack
of them. So given `haipule`, the interesting question isn't "what does it
mean" — your dictionary already knows. The interesting question is what
sub-words live inside it, and what *they* mean.

```
$ curl 'localhost:8765/api/lookup?q=haipule'
{"query":"haipule","syllables":["ha","i","pu","le"],"matches":[
  {"word":"ha","definition":"Ha, num. adj. The number four ..."},
  {"word":"i","definition":"I, prep. ..."},
  {"word":"pule","definition":"Pule, s. A prayer ..."},
  {"word":"ipu","definition":"Ipu, s. A general name for vessels ..."},
  ...
]}
```

## Install

```
nimble install https://github.com/capocasa/wehe
wehe --port 8765
```

JSON daemon — bring your own frontend. The dictionary is baked in at
compile time, so there are no data files, no setup, no flags to point at
anything. Just the binary.

## Endpoints

- `GET /api/lookup?q=haipule` — syllabification + every matching sub-word
- `GET /api/autocomplete?q=hai` — top 10 prefix matches

CORS defaults to wide open. It's a dictionary, not a bank. If you'd
rather pin it to one or more frontends, pass `--origin` (repeatable):

```
wehe --origin https://hawaiian.example --origin https://other.example
```

## Dictionary

The bundled dictionary is Lorrin Andrews, *A Dictionary of the Hawaiian
Language* (Honolulu: Henry M. Whitney, 1865) — about 15,500 headwords and
40,000 senses. **Public domain.** Andrews predates the modern okina/kahakō
orthography, so headwords are bare ASCII; the lookup is fuzzy on okina and
macrons regardless.

Source text comes from the Internet Archive OCR of the original
([dictionaryofhawa00andrrich](https://archive.org/details/dictionaryofhawa00andrrich)).
The vendored copy lives at `src-asset/andrews1865.txt` and is `staticRead`-
embedded into the binary; edit it directly to fix OCR sins (the OCR has
many — small-caps `V` was always a misread `U`, for instance, and the
importer rewrites those, but plenty slip through).

To regenerate from upstream:

```
nimble importAndrews
```

That re-fetches the OCR, re-parses, and overwrites
`src-asset/andrews1865.txt`. Commit the diff if it improves things.

## License

MIT. The dictionary itself is public domain.
