#!/bin/bash
# ServiDesk Update Signing Script
# Pouziti: ./sign-update.sh <soubor.exe> <private-key.pem>
#
# Generovani klicu:
#   openssl genrsa -out update-private.pem 2048
#   openssl rsa -in update-private.pem -pubout -out update-public.pem
#
# Vloz obsah update-public.pem do UpdateInstaller.cs (UpdatePublicKeyPem)

set -e

if [ $# -lt 2 ]; then
    echo "Pouziti: $0 <soubor.exe> <private-key.pem>"
    exit 1
fi

FILE="$1"
KEY="$2"

if [ ! -f "$FILE" ]; then
    echo "Soubor nenalezen: $FILE"
    exit 1
fi

if [ ! -f "$KEY" ]; then
    echo "Privatni klic nenalezen: $KEY"
    exit 1
fi

# SHA-256 hash
SHA256=$(shasum -a 256 "$FILE" | awk '{print $1}')
echo "SHA-256: $SHA256"

# RSA podpis (base64)
SIGNATURE=$(openssl dgst -sha256 -sign "$KEY" "$FILE" | base64 | tr -d '\n')
echo "Signature: ${SIGNATURE:0:40}..."

echo ""
echo "Pro manifest.json:"
echo "  \"sha256\": \"$SHA256\","
echo "  \"signature\": \"$SIGNATURE\""
