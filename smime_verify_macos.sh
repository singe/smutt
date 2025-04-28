#!/bin/sh

# Helper scripts to parse certificate verification responses from the `security cms` command
# For use with the mutt mail client
# By @singe

signature="$1"

if [ -z "$2" ]; then
  # not detached - or opaque
  # likely invoked from smime_verify_opaque_command
  out=$(security cms -D -i "$signature" -n -h0)
  echo "Opaque verification" 1>&2
  # Output contents
  security cms -D -i "$signature"
else
  # normal detached mode - don't output contents
  # likely invoked from smime_verify_command
  content="$2"
  out=$(security cms -D -i "$signature" -c "$content" -n -h0)
fi

line=$(printf '%.0s-' {1..45})

# Look for failures before success

echo "$out" | grep "signer[0-9]*.status=DigestMismatch;" > /dev/null
if [[ $? -eq 0 ]]; then
  echo "$line\nVerification FAILURE - signature mismatch\n$line\n" 1>&2
  exit 4
fi

echo "$out" | grep "signer[0-9]*.status=SigningCertNotTrusted;" > /dev/null
if [[ $? -eq 0 ]]; then
  echo "$line\nVerification FAILURE - untrusted signing cert\n$line\n" 1>&2
  openssl pkcs7 -inform DER -in $signature -print_certs | grep -B2 "BEGIN" |grep -v BEGIN 1>&2
  exit 5
fi

# Success only if first signer (i.e. signer0) is good

echo "$out" | grep "signer0.status=GoodSignature;" > /dev/null
if [[ $? -eq 0 ]]; then
  # mutt requires this exact format and exit code
  echo "Verification successful" 1>&2
  exit 0
fi

# Something unknown has happened

echo "$line\nVerification - weird\n$line\n" 1>&2
echo $out 1>&2
exit 100
