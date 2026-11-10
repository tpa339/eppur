#!/bin/zsh
# Erzeugt ein selbstsigniertes Code-Signing-Zertifikat „Eppur Local Signing“
# nur für diesen Mac und legt es im Anmelde-Schlüsselbund ab.
# Damit behält Eppur über Neubauten hinweg dieselbe Signatur, und macOS
# merkt sich die Freigaben (Bildschirmaufnahme, Bedienungshilfen, Mikrofon).
set -euo pipefail

NAME="Eppur Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Zertifikat „$NAME“ existiert bereits – nichts zu tun."
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT   # privater Schlüssel liegt nur kurz hier
PASS=$(/usr/bin/openssl rand -hex 16)

cat > "$WORK/cert.cnf" <<EOF
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
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/cert.p12" -passout "pass:$PASS"

# Import; codesign darf den Schlüssel ohne Rückfrage benutzen.
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security
# Für Code-Signing vertrauen (macOS fragt nach deinem Passwort).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
security find-identity -v -p codesigning | grep "$NAME" && echo "Fertig: „$NAME“ ist eingerichtet."
