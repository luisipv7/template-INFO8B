# template-INFO8B

## Início rápido (recomendado)

O projeto traz um assistente de linha de comando que instala os programas,
configura o VS Code e prepara o Git/GitHub para você. Ele tem os mesmos
comandos no Windows e no Linux:

| Windows     | Linux           |
| ----------- | --------------- |
| `aluno.cmd` | `bash aluno.sh` |

Abra um terminal **na pasta do projeto**. No Windows, você pode usar o Prompt
de Comando, o PowerShell ou dar dois cliques em `aluno.cmd`. No Linux, use o
terminal **sem** `sudo`; o script pede a senha quando precisar.

### Passo 1 — Criar a conta no GitHub

```
aluno.cmd --cadastro
```

O comando abre a página de cadastro no navegador. Use um e-mail que você
acessa e confirme o código enviado. Se você for estudante, vale também pedir o
[GitHub Student Developer Pack](https://education.github.com/pack).

### Passo 2 — Instalar os programas

```
aluno.cmd --setup
```

No **Windows**, o comando pede permissão de administrador uma única vez e faz o
seguinte:

- Instala o **Git for Windows (Git Bash)**, o **Python 3.12**, o **VS Code** e o
  **XAMPP** (em `C:\xampp`).
- Deixa o **Git Bash como terminal padrão** do VS Code e aponta o `git.path`
  para o `git.exe`.
- Instala a extensão Python no VS Code.

No **Linux** (Ubuntu, Debian, Mint ou Fedora), o comando instala o Git, o
Python com `venv` e `pip`, o OpenSSH, o VS Code e o XAMPP (em `/opt/lampp`).

Ao terminar, **feche e abra novamente o VS Code**.

### Passo 3 — Configurar o Git e a chave SSH

```
aluno.cmd --github --username "Seu Nome" --email "seu.email@exemplo.com"
```

Use o **mesmo e-mail do cadastro no GitHub**. O comando faz o seguinte:

1. Configura `git config --global user.name` e `user.email`.
2. Cria a chave SSH `~/.ssh/id_ed25519`. Se você já tiver uma chave, ela é
   reaproveitada e nunca sobrescrita.
3. Copia a chave pública para a área de transferência e abre
   [github.com/settings/ssh/new](https://github.com/settings/ssh/new). Lá,
   preencha um **Title** (ex.: `PC Lab 3`), cole a chave com `Ctrl+V` e
   clique em **Add SSH key**.
4. Volte ao terminal e pressione ENTER para testar a conexão.

> Não é preciso informar senha: o GitHub não aceita senha em comandos Git.
> A chave SSH é a sua identificação. Por isso, ao clonar, use o endereço
> **SSH** do repositório: `git@github.com:USUARIO/REPOSITORIO.git`.

### Passo 4 — Conferir o ambiente

```
aluno.cmd --check
```

O comando mostra `[ OK ]` ou `[FALTA]` para cada item. Se algo faltar, mostre a
tela ao professor.

### Resumo dos comandos

| Comando                                       | O que faz                                       |
| --------------------------------------------- | ----------------------------------------------- |
| `aluno.cmd` / `bash aluno.sh`                 | Menu interativo com todas as opções             |
| `--cadastro`                                  | Abre o cadastro do GitHub                       |
| `--setup`                                     | Instala XAMPP, Git (Git Bash), VS Code e Python |
| `--github --username "Nome" --email "e-mail"` | Configura o Git e cria a chave SSH              |
| `--check`                                     | Diagnóstico do ambiente                         |
| `--help`                                      | Ajuda                                           |

As opções podem ser combinadas, por exemplo:

```
aluno.cmd --setup --github --username "Maria Silva" --email "maria@exemplo.com"
```

Para instalar o XAMPP em outro local no Windows, defina a variável antes de
rodar o comando. No Prompt de Comando, use `set XAMPP_DIR=D:\xampp`.

---

## Configuração do projeto

Com o ambiente pronto, abra a pasta do projeto no VS Code
(**File > Open Folder**), abra um terminal (**Terminal > New Terminal**, que já
será o Git Bash no Windows) e execute:

```bash
bash setup.sh
```

O script faz o seguinte, nesta ordem:

1. Cria o `venv` e instala o `requirements.txt`.
2. Copia `.env.example` para `.env`, caso o `.env` ainda não exista. O modelo
   `.env.example` é preservado.
3. Inicia o Apache e o MySQL.
4. Importa `db01.sql` no banco `rent-all`.
5. Inicia `fastapi dev main.py`. A importação acontece antes do servidor,
   que ocupa o terminal.

O XAMPP é procurado em `C:\xampp` no Windows e em `/opt/lampp` no Linux.
Para usar outro local:

```bash
XAMPP_DIR='/c/Program Files/xampp' bash setup.sh
```

No Linux, o script solicita `sudo` apenas para iniciar os serviços.

Se as credenciais do seu MySQL forem diferentes do padrão do exemplo (`root`
sem senha), configure `DATABASE_URL` no `.env` antes de executar o script. O
usuário precisa de permissão para criar o banco e executar `db01.sql`.

Executar a configuração novamente reaplica o SQL, incluindo a senha e o perfil
do usuário `admin` definidos nesse arquivo.

## Inicialização

Com o MySQL já em execução:

```bash
bash start.sh
```

Esse script apenas ativa o `venv` e inicia o FastAPI. Use `Ctrl+C` para
encerrar a API; os serviços do XAMPP continuam em execução.

---

## Instalação manual (caso o assistente não funcione)

### Programas necessários

| Programa                          | Download                                                      | Para que serve / orientação                                                                                                              |
| --------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| XAMPP                             | [Apache Friends](https://www.apachefriends.org/download.html) | Fornece Apache e MySQL/MariaDB. No Windows, prefira instalar em `C:\xampp`.                                                              |
| Visual Studio Code (VS Code)      | [Download do VS Code](https://code.visualstudio.com/download) | Editor para abrir o projeto e executar os comandos no terminal integrado.                                                                |
| Python 3.10 ou superior           | [Download do Python](https://www.python.org/downloads/)       | Executa a API e cria o ambiente virtual. No instalador do Windows, marque **Add python.exe to PATH**, quando disponível.                 |
| Git for Windows (inclui Git Bash) | [Download do Git](https://git-scm.com/downloads/win)          | Instala o Git e o Bash usado pelos scripts no Windows. No instalador, permita o uso do Git pela linha de comando e por outros programas. |

Após instalar, feche e abra novamente o VS Code para atualizar o `PATH`.

No Linux, instale o Git, o Bash, o Python com suporte a `venv` e o pip, além do
XAMPP para Linux (LAMPP) e do VS Code. O Git Bash é necessário apenas no
Windows.

### Git Bash no terminal do VS Code (Windows)

1. Abra a pasta do projeto no VS Code em **File > Open Folder** (Arquivo > Abrir Pasta).
2. Pressione `Ctrl+Shift+P`, procure **Terminal: Select Default Profile**
   (Terminal: Selecionar Perfil Padrão) e selecione **Git Bash**.
3. Feche os terminais antigos pelo ícone da lixeira e abra um novo em
   **Terminal > New Terminal** (Novo Terminal).

Se o Git Bash não aparecer:

1. Pressione `Ctrl+Shift+P` e abra **Preferences: Open User Settings (JSON)**
   (Preferências: Abrir Configurações do Usuário (JSON)).
2. Adicione as propriedades abaixo dentro do objeto principal. Se já houver
   configurações, preserve-as e separe as propriedades por vírgulas:

```json
{
  "terminal.integrated.profiles.windows": {
    "Git Bash": {
      "path": "C:\\Program Files\\Git\\bin\\bash.exe",
      "args": ["--login", "-i"]
    }
  },
  "terminal.integrated.defaultProfile.windows": "Git Bash",
  "git.path": "C:\\Program Files\\Git\\cmd\\git.exe"
}
```

O caminho padrão do Bash é `C:\Program Files\Git\bin\bash.exe`. Se você
instalou o Git em outra pasta, ajuste o caminho. No JSON, as barras invertidas
precisam ser duplicadas (`\\`).

Também é possível fazer pelas configurações visuais: pressione `Ctrl+,`,
procure **Terminal › Integrated › Default Profile: Windows** e selecione
**Git Bash**. Abra um novo terminal após alterar o perfil.

Referência: [perfis de terminal na documentação do VS Code](https://code.visualstudio.com/docs/terminal/profiles).

No novo terminal Git Bash, confirme as instalações:

```bash
git --version
python --version
python -m pip --version
```

Se `git` não for encontrado, verifique se `C:\Program Files\Git\cmd` está no
`Path` das variáveis de ambiente do Windows e reinicie o VS Code.

Se `python` não for encontrado, ajuste a instalação do Python para adicioná-lo
ao `PATH` e reinicie o editor.

### Identificação no Git e chave SSH

Para identificar seus commits, execute uma vez, substituindo pelos seus dados:

```bash
git config --global user.name "Seu Nome"
git config --global user.email "seu.email@exemplo.com"
```

Esses dados identificam o autor dos commits; eles não fazem login no GitHub.
Para se autenticar, crie uma chave SSH e cadastre-a no GitHub:

```bash
ssh-keygen -t ed25519 -C "seu.email@exemplo.com"
cat ~/.ssh/id_ed25519.pub
```

1. Copie a linha exibida pelo `cat`.
2. Cole a chave em [github.com/settings/ssh/new](https://github.com/settings/ssh/new).
3. Teste a conexão com `ssh -T git@github.com`.

Com a pasta do projeto aberta, execute `git status` para verificar o repositório.
