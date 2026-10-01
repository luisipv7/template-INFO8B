# =====================================================================
#  aluno.ps1 — Assistente de ambiente do template-INFO8B (Windows)
#
#  Use pelo atalho aluno.cmd (ele libera a ExecutionPolicy sozinho):
#     aluno.cmd                      -> menu interativo
#     aluno.cmd --cadastro           -> abre a página de cadastro do GitHub
#     aluno.cmd --setup              -> instala XAMPP, Git, VS Code e Python
#                                       e configura o Git Bash no VS Code
#     aluno.cmd --github --username "Maria Silva" --email "maria@ex.com"
#                                    -> git config global + chave SSH
#     aluno.cmd --check              -> diagnóstico do ambiente
# =====================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$XamppDir       = if ($env:XAMPP_DIR)     { $env:XAMPP_DIR }     else { 'C:\xampp' }
$XamppVersion   = if ($env:XAMPP_VERSION) { $env:XAMPP_VERSION } else { '8.2.12' }
$XamppWingetIds = @('ApacheFriends.Xampp.8.2')
$XamppUrl       = "https://sourceforge.net/projects/xampp/files/XAMPP%20Windows/$XamppVersion/xampp-windows-x64-$XamppVersion-0-VS16-installer.exe/download"
$PythonWingetId = 'Python.Python.3.12'
$script:Failures = 0

# ---------------------------------------------------------------- saída
function Info($m) { Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ OK ]  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[AVISO] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[ERRO]  $m" -ForegroundColor Red; $script:Failures++ }
function Title($m){ Write-Host ""; Write-Host "=== $m ===" -ForegroundColor Magenta }

function Show-Help {
@"
Assistente de ambiente - template-INFO8B

  aluno.cmd                    Menu interativo
  aluno.cmd --cadastro         Abre o cadastro do GitHub no navegador
  aluno.cmd --setup            Instala XAMPP, Git (Git Bash), VS Code e Python
                               e deixa o Git Bash como terminal do VS Code
  aluno.cmd --github --username "Seu Nome" --email "seu@email.com"
                               Configura o Git e cria a chave SSH
  aluno.cmd --check            Mostra o que está instalado/configurado

As opções podem ser combinadas:
  aluno.cmd --setup --github --username "Maria Silva" --email "maria@ex.com"

Variáveis opcionais: XAMPP_DIR (padrão C:\xampp), XAMPP_VERSION (padrão 8.2.12)
"@ | Write-Host
}

# ------------------------------------------------------------ argumentos
function Parse-Args([object[]]$Argv) {
    $o = @{ setup=$false; github=$false; cadastro=$false; check=$false; help=$false;
            internal=$false; username=$null; email=$null }
    $i = 0
    while ($i -lt $Argv.Count) {
        $raw = [string]$Argv[$i]
        $key = $raw; $val = $null
        if ($raw -match '^-{1,2}([^=]+)=(.*)$') { $key = $Matches[1]; $val = $Matches[2] }
        $key = ($key -replace '^-+', '').ToLower()
        switch ($key) {
            'setup'     { $o.setup = $true }
            'github'    { $o.github = $true }
            'cadastro'  { $o.cadastro = $true }
            'signup'    { $o.cadastro = $true }
            'check'     { $o.check = $true }
            'verificar' { $o.check = $true }
            'help'      { $o.help = $true }
            'h'         { $o.help = $true }
            '_install'  { $o.internal = $true }
            { $_ -in 'username','user','name','nome','u' } {
                if ($null -eq $val) { $i++; $val = if ($i -lt $Argv.Count) { [string]$Argv[$i] } else { '' } }
                $o.username = $val }
            { $_ -in 'email','e' } {
                if ($null -eq $val) { $i++; $val = if ($i -lt $Argv.Count) { [string]$Argv[$i] } else { '' } }
                $o.email = $val }
            default { Write-Host "[ERRO]  Opção desconhecida: $raw" -ForegroundColor Red; Show-Help; exit 1 }
        }
        $i++
    }
    return $o
}

# --------------------------------------------------------- utilitários
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Find-First([string[]]$Paths) {
    foreach ($p in $Paths) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

function Find-GitExe {
    $p = Find-First @("$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
    if ($p) { return $p }
    $c = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Find-GitRoot {
    $git = Find-GitExe
    if (-not $git) { return $null }
    $dir = Split-Path $git -Parent                 # ...\Git\cmd (ou mingw64\bin)
    while ($dir -and -not (Test-Path (Join-Path $dir 'bin\bash.exe'))) { $dir = Split-Path $dir -Parent }
    return $dir
}

function Find-GitBash {
    $root = Find-GitRoot
    if ($root) { return (Join-Path $root 'bin\bash.exe') }
    return $null
}

function Find-Code {
    $p = Find-First @("$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
                      "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd")
    if ($p) { return $p }
    $c = Get-Command code.cmd -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Find-SshTool([string]$Name) {
    $c = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $root = Find-GitRoot
    if ($root) { return (Find-First @(Join-Path $root "usr\bin\$Name.exe")) }
    return $null
}

# Retorna "3.12.4" ou $null. Ignora o atalho falso da Microsoft Store.
function Get-PythonVersion {
    foreach ($cmd in @('py', 'python')) {
        $c = Get-Command "$cmd.exe" -ErrorAction SilentlyContinue
        if (-not $c -or $c.Source -like '*\WindowsApps\*') { continue }
        try {
            $out = if ($cmd -eq 'py') { & $c.Source -3 --version 2>&1 } else { & $c.Source --version 2>&1 }
            if ("$out" -match 'Python (\d+\.\d+(\.\d+)?)') { return $Matches[1] }
        } catch {}
    }
    return $null
}

function Test-PythonOk {
    $v = Get-PythonVersion
    if (-not $v) { return $false }
    $p = $v.Split('.')
    return ([int]$p[0] -gt 3) -or ([int]$p[0] -eq 3 -and [int]$p[1] -ge 10)
}

function Open-Url([string]$Url) {
    try { Start-Process $Url } catch { Warn "Abra manualmente: $Url" }
}

# ------------------------------------------------------------ cadastro
function Open-Signup {
    Title 'Cadastro no GitHub'
    Info 'Abrindo https://github.com/signup no navegador...'
    Open-Url 'https://github.com/signup'
    Write-Host @"
  1. Crie a conta com um e-mail que você acessa (confirme o código enviado).
  2. Anote o e-mail usado: ele será pedido na opção --github.
  3. Estudante? Vale pedir o GitHub Student Developer Pack:
     https://education.github.com/pack
"@
}

# --------------------------------------------------------- instalação
function Install-Pkg([string]$Id, [string]$Name, [string[]]$Extra) {
    Info "Instalando $Name (winget: $Id)... isso pode levar alguns minutos."
    $a = @('install', '--id', $Id, '-e', '--source', 'winget',
           '--accept-package-agreements', '--accept-source-agreements', '--silent') + $Extra
    & winget @a | Out-Host
    $code = $LASTEXITCODE
    # 0 = ok | 0x8A15002B / 0x8A150061 = já instalado / sem atualização
    if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335135) { Ok "$Name instalado."; return $true }
    Warn "winget retornou código $code ao instalar $Name."
    return $false
}

function Install-Xampp {
    if (Test-Path (Join-Path $XamppDir 'xampp-control.exe')) { Ok "XAMPP já instalado em $XamppDir."; return }

    $override = '--mode unattended --unattendedmodeui minimal'
    if ($XamppDir -notmatch '\s') { $override += " --prefix $XamppDir" }
    else { Warn 'XAMPP_DIR contém espaços; o instalador usará o caminho padrão (C:\xampp).' }

    foreach ($id in $XamppWingetIds) {
        if (Install-Pkg $id 'XAMPP' @('--override', $override)) {
            if (Test-Path (Join-Path $XamppDir 'xampp-control.exe')) { return }
        }
    }

    Info "Tentando download direto do XAMPP $XamppVersion (SourceForge)..."
    $tmp = Join-Path $env:TEMP 'xampp-installer.exe'
    & curl.exe -fL --retry 3 -A 'Wget/1.21' -o $tmp $XamppUrl | Out-Host
    if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 50MB) {
        Fail 'Não consegui baixar o XAMPP. Baixe em https://www.apachefriends.org/download.html e instale em C:\xampp.'
        Open-Url 'https://www.apachefriends.org/download.html'
        return
    }
    Info 'Executando o instalador do XAMPP...'
    $p = Start-Process $tmp -ArgumentList $override -Wait -PassThru
    if ($p.ExitCode -eq 0 -and (Test-Path (Join-Path $XamppDir 'xampp-control.exe'))) { Ok "XAMPP instalado em $XamppDir." }
    else { Fail "O instalador do XAMPP terminou com código $($p.ExitCode)." }
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

# Parte que precisa de administrador (roda na janela elevada)
function Install-All {
    Title 'Instalando programas'
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Fail 'winget não encontrado. Instale/atualize o "Instalador de Aplicativo" (App Installer) pela Microsoft Store e rode de novo.'
        Open-Url 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1'
        return
    }
    Update-SessionPath

    if (Find-GitExe) { Ok 'Git (com Git Bash) já instalado.' }
    elseif (-not (Install-Pkg 'Git.Git' 'Git for Windows (Git Bash)' @('--scope', 'machine'))) { Fail 'Falha ao instalar o Git.' }

    if (Test-PythonOk) { Ok "Python $(Get-PythonVersion) já instalado." }
    elseif (-not (Install-Pkg $PythonWingetId 'Python 3' @('--scope', 'machine', '--override',
            '/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 Include_launcher=1'))) { Fail 'Falha ao instalar o Python.' }

    if (Find-Code) { Ok 'VS Code já instalado.' }
    elseif (-not (Install-Pkg 'Microsoft.VisualStudioCode' 'Visual Studio Code' @('--scope', 'machine', '--override',
            '/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'))) { Fail 'Falha ao instalar o VS Code.' }

    Install-Xampp
}

function Set-JsonProp($Obj, [string]$Name, $Value) {
    $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

# Parte que roda como o próprio aluno (configurações ficam no perfil dele)
function Configure-VSCode {
    Title 'Configurando o VS Code'
    $bash = Find-GitBash
    $git  = Find-GitExe
    if (-not $bash -or -not $git) { Fail 'Git Bash não encontrado; não foi possível configurar o terminal do VS Code.'; return }

    $settings = Join-Path $env:APPDATA 'Code\User\settings.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $settings) | Out-Null

    $obj = New-Object PSObject
    if (Test-Path $settings) {
        $raw = [IO.File]::ReadAllText($settings)
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $bak = "$settings.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item $settings $bak
            try { $obj = $raw | ConvertFrom-Json -ErrorAction Stop }
            catch {
                Warn "Seu settings.json tem comentários ou erro de formato, então não mexi nele (backup: $bak)."
                Warn 'Configure manualmente pela seção "Git Bash no terminal do VS Code" do README.'
                return
            }
        }
    }

    $profilesKey = 'terminal.integrated.profiles.windows'
    $profiles = $obj.$profilesKey
    if (-not $profiles) { $profiles = New-Object PSObject }
    Set-JsonProp $profiles 'Git Bash' ([pscustomobject]@{ path = $bash; args = @('--login', '-i') })
    Set-JsonProp $obj $profilesKey $profiles
    Set-JsonProp $obj 'terminal.integrated.defaultProfile.windows' 'Git Bash'
    Set-JsonProp $obj 'git.path' $git

    $json = $obj | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($settings, $json, (New-Object Text.UTF8Encoding $false))
    Ok "Terminal padrão do VS Code = Git Bash ($bash)"
    Ok "git.path do VS Code = $git"

    $code = Find-Code
    if ($code) {
        Info 'Instalando a extensão Python no VS Code...'
        & $code --install-extension ms-python.python --force | Out-Host
    }
}

function Invoke-Setup {
    if (Test-Admin) {
        Install-All
    } else {
        Info 'A instalação precisa de permissão de administrador. Confirme na janela do Windows (UAC).'
        try {
            $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList `
                 "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" --_install"
            if ($p.ExitCode -ne 0) { Fail "A instalação terminou com $($p.ExitCode) erro(s). Veja as mensagens acima/na outra janela." }
        } catch {
            Fail 'Permissão de administrador negada. Peça ajuda ao professor.'
            return
        }
    }
    Update-SessionPath
    Configure-VSCode
    Show-Check
    Warn 'Feche e abra novamente o VS Code para ele enxergar os novos programas.'
}

# ------------------------------------------------------- git + github
function Invoke-Github([string]$Name, [string]$Email) {
    Title 'Configurando Git e chave SSH do GitHub'
    if (-not $Name)  { $Name  = Read-Host 'Seu nome para os commits (ex.: Maria Silva)' }
    if (-not $Email) { $Email = Read-Host 'E-mail usado no cadastro do GitHub' }
    $Name = "$Name".Trim(); $Email = "$Email".Trim()
    if (-not $Name) { Fail 'Nome vazio.'; return }
    if ($Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { Fail "E-mail inválido: $Email"; return }

    Update-SessionPath
    $git = Find-GitExe
    if (-not $git) { Fail 'Git não encontrado. Rode primeiro: aluno.cmd --setup'; return }

    & $git config --global user.name $Name
    & $git config --global user.email $Email
    & $git config --global init.defaultBranch main
    & $git config --global core.autocrlf true
    Ok "git config --global user.name  = $(& $git config --global user.name)"
    Ok "git config --global user.email = $(& $git config --global user.email)"

    $keygen = Find-SshTool 'ssh-keygen'
    if (-not $keygen) { Fail 'ssh-keygen não encontrado. Rode primeiro: aluno.cmd --setup'; return }

    $sshDir = Join-Path $env:USERPROFILE '.ssh'
    $key    = Join-Path $sshDir 'id_ed25519'
    New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

    if (Test-Path $key) {
        Info "Você já tem uma chave em $key - ela será reaproveitada (não sobrescrevo chaves)."
    } else {
        Info 'Gerando chave SSH ed25519 (sem senha, para uso em aula)...'
        $p = Start-Process -FilePath $keygen -NoNewWindow -Wait -PassThru -ArgumentList `
             "-q -t ed25519 -C `"$Email`" -f `"$key`" -N `"`""
        if ($p.ExitCode -ne 0 -or -not (Test-Path "$key.pub")) { Fail 'Falha ao gerar a chave SSH.'; return }
        Ok "Chave criada: $key.pub"
    }

    $pub = ([IO.File]::ReadAllText("$key.pub")).Trim()
    try { Set-Clipboard -Value $pub; Ok 'Chave pública COPIADA para a área de transferência.' } catch {}
    Write-Host ''
    Write-Host $pub -ForegroundColor White
    Write-Host ''
    Write-Host @"
Agora no GitHub (a página vai abrir):
  1. Title: um nome para este computador (ex.: PC Lab 3)
  2. Key type: Authentication Key
  3. Key: cole com Ctrl+V  ->  Add SSH key
"@
    Open-Url 'https://github.com/settings/ssh/new'

    $ans = Read-Host 'Depois de salvar a chave, pressione ENTER para testar (ou digite P para pular)'
    if ($ans -match '^[pP]') { return }

    $ssh = Find-SshTool 'ssh'
    if (-not $ssh) { Warn 'ssh não encontrado para o teste.'; return }
    $out = & $ssh -T -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=15 git@github.com 2>&1 | Out-String
    if ($out -match 'successfully authenticated') {
        Ok ("Conexão com o GitHub funcionando! " + ($out -split "`n")[0].Trim())
        Info 'Clone/push usando o endereço SSH: git@github.com:USUARIO/REPOSITORIO.git'
    } else {
        Fail "Teste falhou: $($out.Trim())"
        Warn 'Confira se a chave foi colada inteira e salva em https://github.com/settings/keys'
    }
}

# ---------------------------------------------------------- diagnóstico
function Line([string]$Label, $Value, [string]$Hint) {
    if ($Value) { Write-Host ("  [ OK ]  {0,-16} {1}" -f $Label, $Value) -ForegroundColor Green }
    else        { Write-Host ("  [FALTA] {0,-16} {1}" -f $Label, $Hint)  -ForegroundColor Yellow }
}

function Show-Check {
    Title 'Diagnóstico do ambiente'
    Update-SessionPath
    $git  = Find-GitExe
    $code = Find-Code
    $py   = Get-PythonVersion
    $key  = Join-Path $env:USERPROFILE '.ssh\id_ed25519.pub'
    Line 'Git'           $(if ($git) { (& $git --version) })            'rode --setup'
    Line 'Git Bash'      (Find-GitBash)                                 'rode --setup'
    Line 'Python >=3.10' $(if (Test-PythonOk) { "Python $py" })         $(if ($py) { "versão $py é antiga - rode --setup" } else { 'rode --setup' })
    Line 'VS Code'       $code                                          'rode --setup'
    Line 'XAMPP'         $(if (Test-Path (Join-Path $XamppDir 'xampp-control.exe')) { $XamppDir }) "não encontrado em $XamppDir - rode --setup"
    Line 'git user.name' $(if ($git) { & $git config --global user.name })  'rode --github'
    Line 'git user.email' $(if ($git) { & $git config --global user.email }) 'rode --github'
    Line 'Chave SSH'     $(if (Test-Path $key) { $key })                'rode --github'
}

# ------------------------------------------------------------------ menu
function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '==============================================' -ForegroundColor Magenta
        Write-Host '   Assistente de ambiente - template-INFO8B'      -ForegroundColor Magenta
        Write-Host '==============================================' -ForegroundColor Magenta
        Write-Host '  1) Criar conta no GitHub (abre o navegador)'
        Write-Host '  2) Instalar XAMPP, Git, VS Code e Python'
        Write-Host '  3) Configurar Git + gerar chave SSH do GitHub'
        Write-Host '  4) Verificar o ambiente'
        Write-Host '  0) Sair'
        switch (Read-Host 'Escolha') {
            '1' { Open-Signup }
            '2' { Invoke-Setup }
            '3' { Invoke-Github $null $null }
            '4' { Show-Check }
            '0' { return }
            default { Warn 'Opção inválida.' }
        }
    }
}

# ------------------------------------------------------------------ main
$o = Parse-Args $args

if ($o.internal) {                     # janela elevada aberta pelo --setup
    Install-All
    Write-Host ''
    Read-Host 'Instalação concluída. Pressione ENTER para fechar esta janela' | Out-Null
    exit $script:Failures
}
if ($o.help) { Show-Help; exit 0 }
if ($o.username -or $o.email) { $o.github = $true }

if (-not ($o.setup -or $o.github -or $o.cadastro -or $o.check)) { Show-Menu; exit 0 }

if ($o.cadastro) { Open-Signup }
if ($o.setup)    { Invoke-Setup }
if ($o.github)   { Invoke-Github $o.username $o.email }
if ($o.check -and -not $o.setup) { Show-Check }

if ($script:Failures -gt 0) { Write-Host ''; Fail "Terminado com problemas. Mostre esta tela ao professor."; exit 1 }
exit 0
