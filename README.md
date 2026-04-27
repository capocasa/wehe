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
nimble importAndrews   # fetches Andrews 1865 from Internet Archive (~2MB)
wehe haipule
```

`importAndrews` is a one-shot. It writes `build/andrews1865.txt`, a
sorted plain-text master (headword + indented sense lines). The binary
reads that file at runtime; you can edit it by hand if the OCR misread
something.

## Serve

```
wehe serve --port 8765 --web ./public
```

JSON endpoints:

- `GET /api/lookup?q=haipule` — syllabification + every matching sub-word
- `GET /api/autocomplete?q=hai` — top 10 prefix matches

CORS is wide open. It's a dictionary, not a bank.

## Source

The dictionary is Lorrin Andrews, *A Dictionary of the Hawaiian Language*
(Honolulu: Henry M. Whitney, 1865). Public domain. The OCR comes from
Internet Archive and is imperfect; small-caps `V` is consistently a
misread `U` (Hawaiian has no `v`), so the importer rewrites it. Other
OCR sins are still in there — patches welcome.

## License

MIT.
