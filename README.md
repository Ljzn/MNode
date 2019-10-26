# M2

## Make Directory

```bash
curl -X POST  \
  'http://localhost:4000/api/mkdir' \
  -H 'x-app-key: 123' \
  -H 'x-onchain-path: /eva'
```


## Write File

```bash
curl -X POST  \
  'http://localhost:4000/api/write' \
  -H 'x-app-key: 123' \
  -H 'x-onchain-path: /eva/narv.png' \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @narv.png
```

## Read File

```bash
curl -X GET \
  'http://localhost:4000/api/read' \
  -H 'x-app-key: 123' \
  -H 'x-onchain-path: /joe_armstrong_crypto_tutorial.pdf' \
  -o joe_armstrong_crypto_tutorial.pdf
```