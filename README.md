# template-INFO8B

## Programas necessários

Antes de configurar o projeto, instale:

| Programa | Download | Para que serve / orientação |
| --- | --- | --- |
| XAMPP | [Apache Friends](https://www.apachefriends.org/download.html) | Fornece Apache e MySQL/MariaDB. No Windows, prefira instalar em `C:\xampp`. |
| Visual Studio Code (VS Code) | [Download do VS Code](https://code.visualstudio.com/download) | Editor para abrir o projeto e executar os comandos no terminal integrado. |
| Python 3.10 ou superior | [Download do Python](https://www.python.org/downloads/) | Executa a API e cria o ambiente virtual. No instalador do Windows, marque **Add python.exe to PATH**, quando disponível. |
| Git for Windows (inclui Git Bash) | [Download do Git](https://git-scm.com/downloads/win) | Instala o Git e o Bash usado pelos scripts no Windows. Permita o uso do Git pela linha de comando e por outros programas no instalador. |

Após instalar, feche e abra novamente o VS Code para atualizar o `PATH`.
No Linux, instale Git, Bash, Python com suporte a `venv` e pip, além do
XAMPP para Linux (LAMPP) e do VS Code. Git Bash é necessário apenas no Windows.

## Git Bash no terminal do VS Code (Windows)

1. Abra a pasta do projeto no VS Code em **File > Open Folder** (Arquivo > Abrir Pasta).
2. Pressione `Ctrl+Shift+P`, procure **Terminal: Select Default Profile**
   (Terminal: Selecionar Perfil Padrão) e selecione **Git Bash**.
3. Feche os terminais antigos pelo ícone da lixeira e abra um novo em
   **Terminal > New Terminal** (Novo Terminal).

Se o Git Bash não aparecer, pressione `Ctrl+Shift+P` e abra
**Preferences: Open User Settings (JSON)** (Preferências: Abrir Configurações
do Usuário (JSON)). Adicione as propriedades abaixo dentro do objeto principal.
Se já houver configurações, preserve-as e separe as propriedades por vírgulas:

```json
{
  "terminal.integrated.profiles.windows": {
    "Git Bash": {
      "path": "C:\\Program Files\\Git\\bin\\bash.exe",
      "args": ["--login", "-i"]
    }
  },
  "terminal.integrated.defaultProfile.windows": "Git Bash"
}
```

O caminho padrão do Bash é `C:\Program Files\Git\bin\bash.exe`.
Se instalou o Git em outra pasta, ajuste o caminho. No JSON, as barras
invertidas precisam ser duplicadas (`\\`). Nas configurações visuais
(`Ctrl+,`), procure **Terminal › Integrated › Default Profile: Windows**
e selecione **Git Bash**. Abra um novo terminal após alterar o perfil.

Referência: [perfis de terminal na documentação do VS Code](https://code.visualstudio.com/docs/terminal/profiles).

No novo terminal Git Bash, confirme as instalações:

```bash
git --version
python --version
python -m pip --version
```

Se `git` não for encontrado, verifique se `C:\Program Files\Git\cmd`
está no `Path` das variáveis de ambiente do Windows e reinicie o VS Code.
Se `python` não for encontrado, ajuste a instalação do Python para adicioná-lo
ao `PATH` e reinicie o editor.

Para identificar seus commits, execute uma vez, substituindo pelos seus dados:

```bash
git config --global user.name "Seu Nome"
git config --global user.email "seu.email@exemplo.com"
```

Esses dados identificam o autor dos commits; não fazem login no GitHub.
Com a pasta do projeto aberta, execute `git status` para verificar o repositório.
Use esse mesmo terminal Git Bash para executar os scripts abaixo.

## Configuração

Instale Python 3 e XAMPP previamente. No Windows, execute os scripts pelo
Git Bash; no Linux, instale também o suporte a `venv` do Python.

```bash
bash setup.sh
```

O script cria `venv`, instala `requirements.txt`, copia `.env.example` para
`.env` caso ele ainda não exista, inicia Apache e MySQL, importa `db01.sql`
no banco `rent-all` e inicia `fastapi dev main.py`. O modelo `.env.example`
é preservado. A importação acontece antes do servidor, que ocupa o terminal.

O XAMPP é procurado em `C:\xampp` no Windows e `/opt/lampp` no Linux.
Para outro local, use, por exemplo:

```bash
XAMPP_DIR='/c/Program Files/xampp' bash setup.sh
```

No Linux, o script solicita `sudo` apenas para iniciar os serviços.
Configure `DATABASE_URL` no `.env` com as credenciais do seu MySQL antes
da execução caso sejam diferentes do padrão do exemplo (`root` sem senha).
O usuário precisa de permissão para criar o banco e executar `db01.sql`.
Executar a configuração novamente reaplica o SQL, incluindo a senha e o
perfil do usuário `admin` definidos nesse arquivo.

## Inicialização

Com o MySQL já em execução:

```bash
bash start.sh
```

Esse script apenas ativa `venv` e inicia o FastAPI. Use `Ctrl+C` para encerrar
a API; os serviços do XAMPP continuam em execução.
