#!/usr/bin/env bash
# =====================================================================
#  aluno.sh — Assistente de ambiente do template-INFO8B (Linux)
#
#     bash aluno.sh                    -> menu interativo
#     bash aluno.sh --cadastro         -> abre o cadastro do GitHub
#     bash aluno.sh --setup            -> instala XAMPP, Git, VS Code e Python
#     bash aluno.sh --github --username "Maria Silva" --email "maria@ex.com"
#     bash aluno.sh --check            -> diagnóstico do ambiente
#
#  No Windows use aluno.cmd. (--github e --check também funcionam no Git Bash.)
# =====================================================================
set -uo pipefail

XAMPP_VERSION="${XAMPP_VERSION:-8.2.12}"
XAMPP_DIR="${XAMPP_DIR:-/opt/lampp}"
FAILURES=0

c_cyan=$'\e[36m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_mag=$'\e[35m'; c_off=$'\e[0m'
info()  { echo "${c_cyan}[INFO]  $*${c_off}"; }
ok()    { echo "${c_green}[ OK ]  $*${c_off}"; }
warn()  { echo "${c_yellow}[AVISO] $*${c_off}"; }
fail()  { echo "${c_red}[ERRO]  $*${c_off}"; FAILURES=$((FAILURES + 1)); }
title() { echo; echo "${c_mag}=== $* ===${c_off}"; }

usage() {
  cat <<EOF
Assistente de ambiente - template-INFO8B

  bash aluno.sh                    Menu interativo
  bash aluno.sh --cadastro         Abre o cadastro do GitHub no navegador
  bash aluno.sh --setup            Instala XAMPP, Git, VS Code e Python
  bash aluno.sh --github --username "Seu Nome" --email "seu@email.com"
                                   Apaga chaves/credenciais do usuário anterior,
                                   configura o Git e cria uma chave SSH nova
  bash aluno.sh --check           Mostra o que está instalado/configurado

Variáveis opcionais: XAMPP_DIR (padrão /opt/lampp), XAMPP_VERSION (padrão 8.2.12)
EOF
}

is_windows() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0;; *) return 1;; esac; }

open_url() {
  local url="$1"
  if is_windows; then start "" "$url" 2>/dev/null && return
  elif command -v xdg-open >/dev/null; then xdg-open "$url" >/dev/null 2>&1 & return
  fi
  warn "Abra manualmente: $url"
}

copy_clip() {
  if is_windows && command -v clip.exe >/dev/null; then clip.exe
  elif [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null; then wl-copy
  elif command -v xclip >/dev/null; then xclip -selection clipboard
  elif command -v xsel  >/dev/null; then xsel --clipboard --input
  else cat >/dev/null; return 1
  fi
}

# ------------------------------------------------------------ argumentos
DO_SETUP=0; DO_GITHUB=0; DO_SIGNUP=0; DO_CHECK=0; GH_NAME=""; GH_EMAIL=""
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --setup|-setup)                     DO_SETUP=1 ;;
      --github|-github)                   DO_GITHUB=1 ;;
      --cadastro|--signup|-cadastro)      DO_SIGNUP=1 ;;
      --check|--verificar|-check)         DO_CHECK=1 ;;
      --username|--user|--name|--nome|-u) shift; GH_NAME="${1:-}"; DO_GITHUB=1 ;;
      --username=*|--user=*|--name=*|--nome=*) GH_NAME="${1#*=}"; DO_GITHUB=1 ;;
      --email|-e)                         shift; GH_EMAIL="${1:-}"; DO_GITHUB=1 ;;
      --email=*)                          GH_EMAIL="${1#*=}"; DO_GITHUB=1 ;;
      -h|--help)                          usage; exit 0 ;;
      *) echo "${c_red}[ERRO]  Opção desconhecida: $1${c_off}"; usage; exit 1 ;;
    esac
    shift
  done
}

# ------------------------------------------------------------ cadastro
open_signup() {
  title "Cadastro no GitHub"
  info "Abrindo https://github.com/signup no navegador..."
  open_url "https://github.com/signup"
  cat <<EOF
  1. Crie a conta com um e-mail que você acessa (confirme o código enviado).
  2. Anote o e-mail usado: ele será pedido na opção --github.
  3. Estudante? Vale pedir o GitHub Student Developer Pack:
     https://education.github.com/pack
EOF
}

# --------------------------------------------------------- instalação
SUDO=""
python_ok() { command -v python3 >/dev/null && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)'; }

detect_pm() {
  if command -v apt-get >/dev/null; then echo apt
  elif command -v dnf >/dev/null; then echo dnf
  else echo none; fi
}

install_base() {
  local pm="$1"
  info "Instalando Git, Python (venv/pip), SSH e utilitários..."
  if [ "$pm" = apt ]; then
    $SUDO apt-get update || fail "apt-get update falhou."
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      git python3 python3-venv python3-pip openssh-client curl ca-certificates net-tools \
      || fail "Falha ao instalar pacotes básicos."
    # Faz o comando "python" funcionar (o README usa "python --version")
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y python-is-python3 >/dev/null 2>&1 || true
  else
    $SUDO dnf install -y git python3 python3-pip openssh-clients curl net-tools libxcrypt-compat \
      || fail "Falha ao instalar pacotes básicos."
  fi
  command -v git >/dev/null && ok "$(git --version)"
  if python_ok; then ok "$(python3 --version)"
  else warn "Python 3.10+ não disponível nesta distribuição ($(python3 --version 2>&1)). Fale com o professor."; fi
}

install_vscode() {
  local pm="$1" arch deb_arch
  if command -v code >/dev/null; then ok "VS Code já instalado."; return; fi
  arch="$(uname -m)"
  case "$arch" in x86_64) deb_arch=x64 ;; aarch64|arm64) deb_arch=arm64 ;; *) fail "Arquitetura $arch não suportada pelo VS Code."; return ;; esac
  info "Instalando Visual Studio Code..."
  if [ "$pm" = apt ]; then
    echo "code code/add-microsoft-repo boolean true" | $SUDO debconf-set-selections 2>/dev/null || true
    local deb=/tmp/vscode.deb
    curl -fL --retry 3 -o "$deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-$deb_arch" \
      && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$deb" \
      || { fail "Falha ao instalar o VS Code."; return; }
    rm -f "$deb"
  else
    $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc
    printf '%s\n' "[code]" "name=Visual Studio Code" "baseurl=https://packages.microsoft.com/yumrepos/vscode" \
      "enabled=1" "autorefresh=1" "type=rpm-md" "gpgcheck=1" "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
      | $SUDO tee /etc/yum.repos.d/vscode.repo >/dev/null
    $SUDO dnf install -y code || { fail "Falha ao instalar o VS Code."; return; }
  fi
  ok "VS Code instalado."
}

install_xampp() {
  if [ -x "$XAMPP_DIR/lampp" ]; then ok "XAMPP já instalado em $XAMPP_DIR."; return; fi
  if [ "$(uname -m)" != x86_64 ]; then fail "XAMPP só existe para Linux x86_64 (sua máquina: $(uname -m))."; return; fi
  if [ "$XAMPP_DIR" != /opt/lampp ]; then warn "O instalador do XAMPP para Linux sempre usa /opt/lampp."; fi
  local url="https://sourceforge.net/projects/xampp/files/XAMPP%20Linux/${XAMPP_VERSION}/xampp-linux-x64-${XAMPP_VERSION}-0-installer.run/download"
  local run=/tmp/xampp-installer.run
  info "Baixando XAMPP $XAMPP_VERSION (cerca de 150 MB)..."
  if ! curl -fL --retry 3 -A "Wget/1.21" -o "$run" "$url" || [ "$(stat -c%s "$run" 2>/dev/null || echo 0)" -lt 50000000 ]; then
    fail "Não consegui baixar o XAMPP. Baixe em https://www.apachefriends.org/download.html"
    rm -f "$run"; return
  fi
  chmod +x "$run"
  info "Instalando XAMPP em /opt/lampp..."
  if $SUDO "$run" --mode unattended; then ok "XAMPP instalado em /opt/lampp."
  else fail "O instalador do XAMPP falhou."; fi
  rm -f "$run"
}

do_setup() {
  title "Instalando programas"
  if is_windows; then
    fail "No Windows, a instalação é feita pelo aluno.cmd:  aluno.cmd --setup"
    return
  fi
  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null || { fail "sudo não encontrado."; return; }
    SUDO="sudo"
    info "Será pedida a sua senha do Linux (sudo) para instalar os programas."
    sudo -v || { fail "sudo negado."; return; }
  fi
  local pm; pm="$(detect_pm)"
  if [ "$pm" = none ]; then fail "Distribuição não suportada (precisa de apt ou dnf)."; return; fi
  install_base "$pm"
  install_vscode "$pm"
  install_xampp
  if command -v code >/dev/null; then
    info "Instalando a extensão Python no VS Code..."
    code --install-extension ms-python.python --force >/dev/null 2>&1 && ok "Extensão Python instalada." \
      || warn "Não consegui instalar a extensão Python (instale pelo VS Code)."
  fi
  show_check
}

# ------------------------------------------------------- git + github
# Computador de laboratório passa por vários alunos: apaga chaves SSH,
# credenciais e configuração Git do usuário anterior (mantém authorized_keys).
reset_previous_user() {
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}" t
  info "Apagando chaves SSH, credenciais e configuração Git do usuário anterior..."
  printf 'protocol=https\nhost=github.com\n\n' | git credential reject >/dev/null 2>&1
  if is_windows && command -v cmdkey.exe >/dev/null; then
    for t in $(MSYS_NO_PATHCONV=1 cmdkey.exe /list | grep -oE '([^[:space:]]+:target=)?git:https?://[^[:space:]]+'); do
      MSYS_NO_PATHCONV=1 cmdkey.exe "/delete:$t" >/dev/null
    done
  fi
  command -v ssh-add >/dev/null && ssh-add -D >/dev/null 2>&1
  [ -d "$HOME/.ssh" ] && find "$HOME/.ssh" -mindepth 1 -maxdepth 1 ! -name authorized_keys -exec rm -rf {} +
  rm -f "$HOME/.gitconfig" "$HOME/.git-credentials" "$xdg/git/config" "$xdg/git/credentials"
  ok "Identidade anterior removida."
}

do_github() {
  title "Configurando Git e chave SSH do GitHub"
  local name="$GH_NAME" email="$GH_EMAIL"
  [ -z "$name" ]  && read -rp "Seu nome para os commits (ex.: Maria Silva): " name
  [ -z "$email" ] && read -rp "E-mail usado no cadastro do GitHub: " email
  name="$(echo "$name" | xargs)"; email="$(echo "$email" | xargs)"
  [ -z "$name" ] && { fail "Nome vazio."; return; }
  [[ "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || { fail "E-mail inválido: $email"; return; }
  command -v git >/dev/null || { fail "Git não encontrado. Rode primeiro: bash aluno.sh --setup"; return; }
  command -v ssh-keygen >/dev/null || { fail "ssh-keygen não encontrado. Rode primeiro: bash aluno.sh --setup"; return; }

  reset_previous_user

  git config --global user.name "$name"
  git config --global user.email "$email"
  git config --global init.defaultBranch main
  if is_windows; then git config --global core.autocrlf true; else git config --global core.autocrlf input; fi
  ok "git config --global user.name  = $(git config --global user.name)"
  ok "git config --global user.email = $(git config --global user.email)"

  local key="$HOME/.ssh/id_ed25519"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  info "Gerando chave SSH ed25519 nova (sem senha, para uso em aula)..."
  ssh-keygen -q -t ed25519 -C "$email" -f "$key" -N "" || { fail "Falha ao gerar a chave SSH."; return; }
  ok "Chave criada: $key.pub"

  copy_clip < "$key.pub" && ok "Chave pública COPIADA para a área de transferência."
  echo; cat "$key.pub"; echo
  cat <<EOF
Agora no GitHub (a página vai abrir):
  0. Confira se o navegador está logado na SUA conta (foto no canto superior
     direito). Se for de outra pessoa: Sign out e entre com a sua.
  1. Title: um nome para este computador (ex.: PC Lab 3)
  2. Key type: Authentication Key
  3. Key: cole a chave acima  ->  Add SSH key
EOF
  open_url "https://github.com/settings/ssh/new"

  local ans out
  read -rp "Depois de salvar a chave, pressione ENTER para testar (ou digite P para pular): " ans
  [[ "$ans" =~ ^[pP] ]] && return
  out="$(ssh -T -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=15 git@github.com 2>&1)"
  if grep -q "successfully authenticated" <<<"$out"; then
    ok "Conexão com o GitHub funcionando! $(head -n1 <<<"$out")"
    info "Clone/push usando o endereço SSH: git@github.com:USUARIO/REPOSITORIO.git"
  else
    fail "Teste falhou: $out"
    warn "Confira se a chave foi colada inteira e salva em https://github.com/settings/keys"
  fi
}

# ---------------------------------------------------------- diagnóstico
line() {  # rótulo valor dica
  if [ -n "$2" ]; then printf "${c_green}  [ OK ]  %-16s %s${c_off}\n" "$1" "$2"
  else printf "${c_yellow}  [FALTA] %-16s %s${c_off}\n" "$1" "$3"; fi
}

show_check() {
  title "Diagnóstico do ambiente"
  local py=""; python_ok && py="$(python3 --version 2>&1)"
  local xampp=""
  if is_windows; then [ -f "/c/xampp/xampp-control.exe" ] && xampp="C:\\xampp"
  else [ -x "$XAMPP_DIR/lampp" ] && xampp="$XAMPP_DIR"; fi
  line "Git"            "$(git --version 2>/dev/null)"                          "rode --setup"
  line "Python >=3.10"  "$py"                                                    "rode --setup"
  line "venv"           "$(python3 -c 'import venv' 2>/dev/null && echo ok)"     "rode --setup"
  line "VS Code"        "$(command -v code 2>/dev/null)"                         "rode --setup"
  line "XAMPP"          "$xampp"                                                 "rode --setup"
  line "git user.name"  "$(git config --global user.name 2>/dev/null)"           "rode --github"
  line "git user.email" "$(git config --global user.email 2>/dev/null)"          "rode --github"
  line "Chave SSH"      "$([ -f "$HOME/.ssh/id_ed25519.pub" ] && echo "$HOME/.ssh/id_ed25519.pub")" "rode --github"
}

# ------------------------------------------------------------------ menu
menu() {
  while true; do
    echo
    echo "${c_mag}==============================================${c_off}"
    echo "${c_mag}   Assistente de ambiente - template-INFO8B${c_off}"
    echo "${c_mag}==============================================${c_off}"
    echo "  1) Criar conta no GitHub (abre o navegador)"
    echo "  2) Instalar XAMPP, Git, VS Code e Python"
    echo "  3) Configurar Git + gerar chave SSH do GitHub"
    echo "  4) Verificar o ambiente"
    echo "  0) Sair"
    local opt; read -rp "Escolha: " opt
    case "$opt" in
      1) open_signup ;; 2) do_setup ;; 3) GH_NAME=""; GH_EMAIL=""; do_github ;;
      4) show_check ;; 0) return ;; *) warn "Opção inválida." ;;
    esac
  done
}

# ------------------------------------------------------------------ main
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  echo "${c_red}[ERRO]  Não rode com sudo. Use: bash aluno.sh ...  (a senha é pedida quando precisar)${c_off}"
  exit 1
fi

parse_args "$@"
if [ $((DO_SETUP + DO_GITHUB + DO_SIGNUP + DO_CHECK)) -eq 0 ]; then menu; exit 0; fi

[ "$DO_SIGNUP" -eq 1 ] && open_signup
[ "$DO_SETUP"  -eq 1 ] && do_setup
[ "$DO_GITHUB" -eq 1 ] && do_github
[ "$DO_CHECK"  -eq 1 ] && [ "$DO_SETUP" -eq 0 ] && show_check

if [ "$FAILURES" -gt 0 ]; then echo; fail "Terminado com problemas. Mostre esta tela ao professor."; exit 1; fi
exit 0
