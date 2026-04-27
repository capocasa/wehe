# wehe

Hawaiian word decomposition. Uncovers the hidden — that's what *wehe* means,
and it's also what the tool does to a word.

Hawaiian phonology is regular: every syllable is CV or V, every word a stack
of them. So given `haipule`, the interesting question isn't "what does it
mean" — your dictionary already knows. The interesting question is what
sub-words live inside it, and what *they* mean.

```
$ wehe haipule
ha
  Ha, num. adj. The number four ...

i
  I, prep. ...

pule
  Pule, s. A prayer ...

ipu
  Ipu, s. A general name for vessels ...

# ... and so on, for every valid sub-syllable run
```

## Install

```
nimble install https://github.com/capocasa/wehe
wehe haipule
```

The dictionary is baked into the binary at compile time. No data files,
no setup, no `--db` to point at. Just the binary.

## Serve

```
wehe serve --port 8765 --web ./public
```

JSON endpoints:

- `GET /api/lookup?q=haipule` — syllabification + every matching sub-word
- `GET /api/autocomplete?q=hai` — top 10 prefix matches

CORS is wide open. It's a dictionary, not a bank.

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

That re-fetches the OCR (cached in `.cache/`), re-parses, and overwrites
`src-asset/andrews1865.txt`. Commit the diff if it improves things.

## License

MIT. The dictionary itself is public domain.
