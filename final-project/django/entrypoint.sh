#!/bin/sh
set -eu

HOST="${POSTGRES_HOST:-}"
PORT="${POSTGRES_PORT:-5432}"

echo "==== [ENTRYPOINT] Starting ===="

if [ -n "$HOST" ]; then
  echo "Waiting for DNS of $HOST ..."
  i=0
  until python - <<'PY'
import socket, os, sys
h=os.environ.get("POSTGRES_HOST")
try: socket.getaddrinfo(h, None); sys.exit(0)
except Exception: sys.exit(1)
PY
  do
    i=$((i+1))
    [ "$i" -ge 60 ] && echo "DNS for $HOST still not resolvable" >&2 && break
    sleep 3
  done

  echo "Waiting for TCP $HOST:$PORT ..."
  i=0
  until python - <<'PY'
import socket, os, sys
h=os.environ.get("POSTGRES_HOST"); p=int(os.environ.get("POSTGRES_PORT","5432"))
s=socket.socket(); s.settimeout(3.0)
try: s.connect((h,p)); s.close(); sys.exit(0)
except Exception: sys.exit(1)
PY
  do
    i=$((i+1))
    [ "$i" -ge 60 ] && echo "DB $HOST:$PORT still unreachable" >&2 && break
    sleep 3
  done
else
  echo "POSTGRES_HOST is empty; skipping DB wait"
fi

# Best-effort migrate (avoid crash loops on first boot)
python manage.py migrate --noinput || true

exec python manage.py runserver 0.0.0.0:8000
