#!/bin/zsh
# Genera el certificado TLS local para claude.ai.
# - CA propia restringida por name constraints a claude.ai: no sirve para ningún otro sitio.
# - Firma un único certificado para claude.ai y después BORRA la clave privada de la CA:
#   nadie (ni este programa) puede emitir otros certificados con ella.
# Uso: gen-cert.sh <directorio>   → deja ca.crt, claude.ai.crt y claude.ai.key
set -euo pipefail
OUT=${1:?Uso: gen-cert.sh <directorio>}
mkdir -p $OUT && chmod 700 $OUT
TMP=$(mktemp -d)
trap 'rm -rf $TMP' EXIT
WHO="$(id -un)@$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

cat > $TMP/ca.cnf <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = Claude Desktop Themes local CA ($WHO)
O = claude-desktop-themes (local)
[ext]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
nameConstraints = critical,permitted;DNS:claude.ai
subjectKeyIdentifier = hash
CNF
cat > $TMP/leaf.cnf <<CNF
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:claude.ai
authorityKeyIdentifier = keyid
subjectKeyIdentifier = hash
CNF

openssl ecparam -name prime256v1 -genkey -noout -out $TMP/ca.key 2>/dev/null
openssl req -new -x509 -key $TMP/ca.key -days 820 -config $TMP/ca.cnf -extensions ext -out $OUT/ca.crt
openssl ecparam -name prime256v1 -genkey -noout -out $OUT/claude.ai.key 2>/dev/null
openssl req -new -key $OUT/claude.ai.key -subj "/CN=claude.ai" -out $TMP/leaf.csr
openssl x509 -req -in $TMP/leaf.csr -CA $OUT/ca.crt -CAkey $TMP/ca.key -CAserial $TMP/ca.srl -CAcreateserial \
  -days 820 -extfile $TMP/leaf.cnf -extensions ext -out $OUT/claude.ai.crt 2>/dev/null
rm -P $TMP/ca.key 2>/dev/null || rm -f $TMP/ca.key   # la clave de la CA no se guarda
chmod 600 $OUT/claude.ai.key
chmod 644 $OUT/ca.crt $OUT/claude.ai.crt
openssl verify -CAfile $OUT/ca.crt $OUT/claude.ai.crt >/dev/null
