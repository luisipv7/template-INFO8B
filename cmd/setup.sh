#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) platform=windows ;;
  Linux*) platform=linux ;;
  *) echo 'Sistema não suportado. Use Linux ou Git Bash no Windows.' >&2; exit 1 ;;
esac

if [[ ! -d venv ]]; then
  if command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
    python3 -m venv venv
  else
    python -m venv venv
  fi
fi

if [[ "$platform" == windows ]]; then
  source venv/Scripts/activate
else
  source venv/bin/activate
fi
python -m pip install -r requirements.txt

if [[ ! -f .env ]]; then
  cp .env.example .env
fi

if [[ "$platform" == windows ]]; then
  XAMPP_DIR="${XAMPP_DIR:-/c/xampp}"
  for script in apache_start.bat mysql_start.bat; do
    if [[ ! -f "$XAMPP_DIR/$script" ]]; then
      echo "Não encontrado: $XAMPP_DIR/$script. Configure XAMPP_DIR." >&2
      exit 1
    fi
  done
  export SETUP_XAMPP_DIR="$(cygpath -w "$XAMPP_DIR")"
  powershell.exe -NoProfile -Command '
    $ErrorActionPreference = "Stop"
    foreach ($service in @(@("httpd", "apache_start.bat"), @("mysqld", "mysql_start.bat"))) {
      if (-not (Get-Process -Name $service[0] -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $env:ComSpec -ArgumentList @("/c", $service[1]) -WorkingDirectory $env:SETUP_XAMPP_DIR -WindowStyle Hidden
      }
    }
  '
else
  XAMPP_DIR="${XAMPP_DIR:-/opt/lampp}"
  if [[ ! -x "$XAMPP_DIR/lampp" ]]; then
    echo "Não encontrado: $XAMPP_DIR/lampp. Instale o XAMPP ou configure XAMPP_DIR." >&2
    exit 1
  fi
  if [[ "$EUID" -eq 0 ]]; then
    "$XAMPP_DIR/lampp" startapache
    "$XAMPP_DIR/lampp" startmysql
  else
    sudo "$XAMPP_DIR/lampp" startapache
    sudo "$XAMPP_DIR/lampp" startmysql
  fi
fi

echo 'Aguardando o MySQL e importando db01.sql...'
python - <<'PY'
import os
import time
from pathlib import Path

import pymysql
from dotenv import load_dotenv
from pymysql.constants import CLIENT
from sqlalchemy.engine import make_url

load_dotenv(Path('.env'))
url = make_url(os.environ['DATABASE_URL'])
if url.get_backend_name() != 'mysql' or url.database != 'rent-all':
    raise SystemExit('Configure DATABASE_URL para o banco MySQL rent-all no .env.')

for attempt in range(30):
    try:
        connection = pymysql.connect(
            host=url.host or 'localhost', port=url.port or 3306,
            user=url.username or 'root', password=url.password or '',
            charset='utf8mb4', autocommit=True, connect_timeout=2,
            client_flag=CLIENT.MULTI_STATEMENTS,
        )
        break
    except pymysql.OperationalError as exc:
        if exc.args[0] not in (2002, 2003) or attempt == 29:
            raise SystemExit(
                f'MySQL indisponível (erro {exc.args[0]}). Verifique o XAMPP e DATABASE_URL.'
            ) from None
        time.sleep(1)

with connection:
    with connection.cursor() as cursor:
        cursor.execute(Path('db01.sql').read_text(encoding='utf-8-sig'))
        while cursor.nextset():
            pass
print('Banco rent-all configurado.')
PY

exec fastapi dev main.py
