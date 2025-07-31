#!/bin/bash

echo "=== Setting up ezssh auto-login environment ==="

# Prompt user to input SSH IP and OTP URL
read -p "Please enter the SSH server IP address: " SSH_HOST
read -p "Please enter the otpauth token URL (e.g. otpauth://totp/...): " OTP_URL

# Write ezssh function script
cat > ~/ezssh_alias.sh <<'EOSCRIPT'
# ========= ezssh function =========
ezssh() {
  local PORT="$1"
  if [[ -z "$PORT" ]]; then
    echo "Usage: ezssh <port>"
    return 1
  fi

  # Custom configuration
  local SSH_HOST="172.16.78.132"
  local OTP_URL='otpauth://totp/SElogin:wanfang?secret=GQYTQZBUMRQWIMBYMM3DGMZYGE2DOZBZGZTDONJUGBSTGYJSBI======&algorithm=SHA512&digits=8&period=30&lock=true'

  # Extract parameters
  local SSH_USER=$(echo "$OTP_URL" | sed -n 's|.*totp/[^:]*:\([^?]*\)?.*|\1|p')
  local SECRET=$(echo "$OTP_URL" | sed -n 's/.*secret=\([^&]*\).*/\1/p')
  local ALGO=$(echo "$OTP_URL" | sed -n 's/.*algorithm=\([^&]*\).*/\1/p' | tr '[:upper:]' '[:lower:]')
  local DIGITS=$(echo "$OTP_URL" | sed -n 's/.*digits=\([0-9]*\).*/\1/p')
  local PERIOD=$(echo "$OTP_URL" | sed -n 's/.*period=\([0-9]*\).*/\1/p')
  [[ -z "$ALGO" ]] && ALGO="sha1"
  [[ -z "$DIGITS" ]] && DIGITS=6
  [[ -z "$PERIOD" ]] && PERIOD=30

  # Call Python to generate OTP
  local TOTP=$(python3 <<PYEOF
import base64, hmac, hashlib, time, struct
secret = "$SECRET"
algo = "$ALGO".upper()
digits = int("$DIGITS")
period = int("$PERIOD")
try:
    key = base64.b32decode(secret, casefold=True)
except:
    print("Base32 decoding failed")
    exit(1)
tm = int(time.time() // period)
msg = struct.pack(">Q", tm)
h = hmac.new(key, msg, getattr(hashlib, algo.lower()))
digest = h.digest()
offset = digest[-1] & 0x0F
code = (struct.unpack(">I", digest[offset:offset+4])[0] & 0x7fffffff) % (10 ** digits)
print(str(code).zfill(digits))
PYEOF
  )

  echo "[INFO] Current generated one-time password: $TOTP"

  # Auto login
  expect <<EXPEOF
set timeout 20
log_user 1
spawn ssh -p $PORT $SSH_USER@$SSH_HOST
expect {
    -re "(?i)password.*:|one-time password.*:" {
        send "$TOTP\r"
        exp_continue
    }
    eof
}
interact
EXPEOF
}
EOSCRIPT

# Replace default SSH_HOST and OTP_URL with user inputs using robust perl one-liners
perl -pi -e "s|local SSH_HOST=.*|local SSH_HOST=\"$SSH_HOST\"|g" ~/ezssh_alias.sh
# Escape & and other special characters in OTP_URL for substitution
perl -pi -e "s|local OTP_URL=.*|local OTP_URL='${OTP_URL//&/\\&}'|g" ~/ezssh_alias.sh

# Source ezssh_alias.sh in ~/.zshrc if not already present
if ! grep -q "source ~/ezssh_alias.sh" ~/.zshrc; then
  echo "source ~/ezssh_alias.sh" >> ~/.zshrc
  echo "Added source ~/ezssh_alias.sh to ~/.zshrc"
else
  echo "source already exists in ~/.zshrc, no need to add again"
fi

echo "Setup complete! Please run 'source ~/.zshrc' or restart the terminal to use: ezssh <port>"
