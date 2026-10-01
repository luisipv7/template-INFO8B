#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if [[ -f venv/Scripts/activate ]]; then
  source venv/Scripts/activate
elif [[ -f venv/bin/activate ]]; then
  source venv/bin/activate
else
  echo 'Ambiente virtual não encontrado. Execute bash setup.sh primeiro.' >&2
  exit 1
fi

exec fastapi dev main.py
