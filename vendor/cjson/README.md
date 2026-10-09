# cJSON

Sources officielles non modifiees de [cJSON 1.7.19](https://github.com/DaveGamble/cJSON/releases/tag/v1.7.19), licence MIT conservee dans `LICENSE`.

SHA-256 :

```text
298581a04a36c0165da4b0aade235c23088cb2faa58651d720ea2f3706ed0b0d  cJSON.c
25b0145150d500498e4d209cec69c18c42cf818bffcc54690be3b895a2a16dee  cJSON.h
a36dda207c36db5818729c54e7ad4e8b0c6fba847491ba64f372c1a2037b6d5c  LICENSE
```

Compilation avec `CJSON_NESTING_LIMIT=64`. Le client refuse les doublons de cles, les racines non objet, les donnees non UTF-8 et les reponses de plus de 1 Mio. La cle de service est limitee a 64 Kio. Ne pas modifier les sources sans mettre a jour ce releve et les tests.
