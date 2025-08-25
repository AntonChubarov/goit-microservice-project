#!/usr/bin/env python
"""Django's command-line utility for administrative tasks."""
import os
import sys
import json
import socket

def log_db_boot():
    """
    Print DB-related environment and DNS info before Django starts.
    Safe: redacts password and does not attempt to connect to DB.
    """
    keys = [
        "POSTGRES_HOST", "POSTGRES_PORT", "POSTGRES_NAME",
        "POSTGRES_USER", "POSTGRES_PASSWORD", "DATABASE_URL"
    ]
    env = {k: os.getenv(k) for k in keys}

    # redact password
    redacted = dict(env)
    if redacted.get("POSTGRES_PASSWORD"):
        pw = redacted["POSTGRES_PASSWORD"]
        redacted["POSTGRES_PASSWORD"] = (pw[:3] + "…redacted…") if pw else ""

    print("==== [BOOT] DB-related environment ====")
    print(json.dumps(redacted, indent=2))

    # DNS resolution check for POSTGRES_HOST
    host = env.get("POSTGRES_HOST")
    port = env.get("POSTGRES_PORT") or "5432"
    if host:
        try:
            # Just resolve; do not open sockets
            infos = socket.getaddrinfo(host, int(port))
            addrs = sorted({i[4][0] for i in infos})
            print(f"==== [BOOT] DNS OK for {host}:{port} -> {addrs}")
        except Exception as e:
            print(f"==== [BOOT] DNS FAIL for {host}:{port} -> {e}")
            # Show resolvers to help debug cluster DNS
            try:
                with open("/etc/resolv.conf") as f:
                    print("---- /etc/resolv.conf ----")
                    print(f.read())
            except Exception:
                pass
    else:
        print("==== [BOOT] POSTGRES_HOST not set ====")


def main():
    """Run administrative tasks."""
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "goit.settings")

    # Print before Django initializes (so you see it even on early failure)
    log_db_boot()

    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed and "
            "available on your PYTHONPATH environment variable? Did you "
            "forget to activate a virtual environment?"
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
