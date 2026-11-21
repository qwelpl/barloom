#!/bin/bash
# Creates a self-signed "Barloom Dev" code-signing identity in the login keychain.
# Signing every build with the same identity lets macOS remember the
# Accessibility and Screen Recording permissions across rebuilds.
set -euo pipefail

NAME="Barloom Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "$NAME already exists"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/id.p12" -passout pass:barloom 2>/dev/null
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P barloom -T /usr/bin/codesign >/dev/null
echo "Created $NAME"
