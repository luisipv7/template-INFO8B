# Guia dos CRUDs — Sistema de Locações

Este guia mostra, passo a passo, como implementar os endpoints de todas as models do projeto, seguindo **o mesmo padrão do `POST /categories`** que já está pronto.

O guia tem duas fases:

1. **Partes 1 a 6 — CRUDs básicos.** Todo mundo consegue chamar todas as rotas (ainda sem login). O objetivo é fazer cada model funcionar.
2. **Parte 7 — Regras de acesso por papel.** Depois que tudo funciona, colocamos as travas: quem é admin, locador ou cliente, e o que cada um pode fazer.

> Não pule para a Parte 7 antes de terminar as anteriores. Primeiro faz funcionar, depois protege.

---

## Parte 0 — Entendendo o padrão (o `POST /categories`)

Cada model é dividida em 4 arquivos, um em cada pasta:

```
schemas/<model>.py     → o formato dos dados que ENTRAM e SAEM da API
services/<model>.py    → regras de negócio e acesso ao banco
controller/<model>.py  → ponte entre a rota e o service
routes/<model>.py      → os endpoints (URL + método HTTP)
```

O caminho de uma requisição é sempre este:

```
Cliente HTTP ──► routes ──► controller ──► services ──► banco
                   ▲                                       │
                   └─────────────── resposta ◄─────────────┘
```

Veja como isso aparece no código de categoria que já existe:

**1. Schema** — [schemas/category.py](schemas/category.py): define o que o usuário manda no corpo da requisição.

```python
class CategoryCreate(SQLModel):
    tenant_id: int
    name: str
    slug: str
    description: str | None = None
    parent_id: int | None = None
```

**2. Service** — [services/category.py](services/category.py): cria o objeto da tabela e salva.

```python
async def create_category_service(session: Session, categoria: CategoryCreate) -> Category:
    new_category = Category(**categoria.model_dump(mode="json"))
    session.add(new_category)      # prepara para salvar
    session.commit()               # salva de verdade no banco
    session.refresh(new_category)  # recarrega (agora com o id gerado)
    return new_category
```

**3. Controller** — [controller/category.py](controller/category.py): chama o service.

```python
async def create_category(session: Session, categoria: CategoryCreate) -> Category:
    return await create_category_service(session, categoria)
```

**4. Route** — [routes/category.py](routes/category.py): liga a URL ao controller.

```python
router = APIRouter(prefix="/categories", tags=["categories"])

@router.post("/")
async def create_task(categoria: CategoryCreate, session: Session = Depends(get_session)) -> Category:
    return await create_category(session, categoria)
```

**5. Registro** — o router é exportado em [`routes/__init__.py`](routes/__init__.py) e incluído no [`main.py`](main.py) com `app.include_router(...)`.

### Receita para cada model

Para cada model nova, repita sempre:

1. Criar `schemas/<model>.py` com `XCreate`, `XRead` e `XUpdate`.
2. Criar `services/<model>.py` com as funções `create`, `list`, `get`, `update` e `delete`.
3. Criar `controller/<model>.py` chamando o service.
4. Criar `routes/<model>.py` com os endpoints.
5. Exportar o router em `routes/__init__.py`.
6. Incluir o router no `main.py`.
7. Testar no `/docs`.

### Os três schemas

| Schema        | Para que serve                                   | Campos                                               |
|---------------|--------------------------------------------------|------------------------------------------------------|
| `XCreate`     | Corpo do `POST`                                  | Só o que o usuário pode informar. Sem `id`, sem datas automáticas |
| `XRead`       | O que a API **devolve**                          | O que pode ser mostrado. Nunca senha!                |
| `XUpdate`     | Corpo do `PATCH`                                 | Tudo opcional (`= None`), pois a pessoa altera só o que quiser |

Na rota, o `response_model=XRead` diz ao FastAPI para filtrar a resposta e mostrar apenas os campos do `XRead`.

### Os status HTTP que vamos usar

| Status | Quando                                                        |
|--------|---------------------------------------------------------------|
| `200`  | Deu certo (GET, PATCH, DELETE)                                |
| `201`  | Criou um registro (POST)                                      |
| `404`  | O registro (ou algo que ele referencia) não existe            |
| `409`  | Conflito: slug repetido, horário já reservado, registro em uso |
| `422`  | Dados no formato certo, mas proibidos pela regra de negócio   |

Para devolver um erro, o service levanta um `HTTPException`:

```python
from fastapi import HTTPException, status

raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Categoria nao encontrada")
```

### Ordem de implementação

As tabelas dependem umas das outras:

```
Tenant  →  User  →  Category  →  Item  →  Booking
(loja)    (pessoas)  (grupos)    (o que     (a locação: liga
                                  se aluga)   um Item a um User)
```

Não dá para criar um Item sem ter um Tenant, nem uma Booking sem ter Item e User. A categoria vem primeiro neste guia só porque já começou a ser feita.

---

## Parte 1 — Completar o CRUD de Categoria

Já temos o `POST`. Faltam: listar, buscar por id, alterar e apagar. Este é o **modelo completo** que as outras models vão copiar.

### `schemas/category.py`

Já está pronto. Não precisa mudar nada.

### `services/category.py`

```python
from fastapi import HTTPException, status
from sqlmodel import Session, select

from models.category import Category
from models.item import Item
from models.tenant import Tenant
from schemas.category import CategoryCreate, CategoryUpdate


# ---------- funcoes auxiliares ----------

def _check_slug_available(
    session: Session, tenant_id: int, slug: str, ignore_id: int | None = None
) -> None:
    """O slug precisa ser unico dentro do tenant."""
    statement = select(Category).where(Category.tenant_id == tenant_id, Category.slug == slug)
    if ignore_id is not None:
        statement = statement.where(Category.id != ignore_id)
    if session.exec(statement).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ja existe uma categoria com esse slug",
        )


def _check_parent(session: Session, tenant_id: int, parent_id: int) -> None:
    """A categoria pai precisa existir e ser do mesmo tenant."""
    parent = session.get(Category, parent_id)
    if not parent or parent.tenant_id != tenant_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Categoria pai nao encontrada",
        )


# ---------- CRUD ----------

async def create_category_service(session: Session, categoria: CategoryCreate) -> Category:
    if not session.get(Tenant, categoria.tenant_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tenant nao encontrado")
    _check_slug_available(session, categoria.tenant_id, categoria.slug)
    if categoria.parent_id is not None:
        _check_parent(session, categoria.tenant_id, categoria.parent_id)

    new_category = Category(**categoria.model_dump(mode="json"))
    session.add(new_category)
    session.commit()
    session.refresh(new_category)
    return new_category


async def list_categories_service(session: Session, tenant_id: int) -> list[Category]:
    statement = select(Category).where(Category.tenant_id == tenant_id).order_by(Category.name)
    return list(session.exec(statement).all())


async def get_category_service(session: Session, category_id: int) -> Category:
    category = session.get(Category, category_id)
    if not category:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Categoria nao encontrada")
    return category


async def update_category_service(
    session: Session, category_id: int, categoria: CategoryUpdate
) -> Category:
    category = await get_category_service(session, category_id)

    # exclude_unset=True: pega SO os campos que vieram no corpo da requisicao
    changes = categoria.model_dump(exclude_unset=True)

    if "slug" in changes:
        _check_slug_available(session, category.tenant_id, changes["slug"], ignore_id=category.id)
    if changes.get("parent_id") is not None:
        if changes["parent_id"] == category.id:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Uma categoria nao pode ser pai dela mesma",
            )
        _check_parent(session, category.tenant_id, changes["parent_id"])

    category.sqlmodel_update(changes)  # copia os campos alterados para o objeto
    session.add(category)
    session.commit()
    session.refresh(category)
    return category


async def delete_category_service(session: Session, category_id: int) -> None:
    category = await get_category_service(session, category_id)

    # nao deixa apagar categoria que ainda tem itens ou subcategorias
    has_items = session.exec(select(Item).where(Item.category_id == category_id)).first()
    has_children = session.exec(select(Category).where(Category.parent_id == category_id)).first()
    if has_items or has_children:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Categoria em uso por itens ou subcategorias",
        )

    session.delete(category)
    session.commit()
```

Pontos importantes:

- **`model_dump(exclude_unset=True)`**: se o `PATCH` mandar só `{"name": "Novo"}`, o dicionário fica só com `name`. Sem isso, os outros campos virariam `None` e apagariam os dados.
- **`sqlmodel_update(changes)`**: copia cada chave do dicionário para o objeto. É o mesmo que fazer `setattr(category, campo, valor)` para cada campo.
- **`ignore_id` no slug**: ao editar, a própria categoria já tem aquele slug no banco. Sem ignorar ela mesma, daria conflito consigo.

### `controller/category.py`

```python
from sqlmodel import Session

from models.category import Category
from schemas.category import CategoryCreate, CategoryUpdate
from services.category import (
    create_category_service,
    delete_category_service,
    get_category_service,
    list_categories_service,
    update_category_service,
)


async def create_category(session: Session, categoria: CategoryCreate) -> Category:
    return await create_category_service(session, categoria)


async def list_categories(session: Session, tenant_id: int) -> list[Category]:
    return await list_categories_service(session, tenant_id)


async def get_category(session: Session, category_id: int) -> Category:
    return await get_category_service(session, category_id)


async def update_category(session: Session, category_id: int, categoria: CategoryUpdate) -> Category:
    return await update_category_service(session, category_id, categoria)


async def delete_category(session: Session, category_id: int) -> None:
    return await delete_category_service(session, category_id)
```

### `routes/category.py`

```python
from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from controller.category import (
    create_category,
    delete_category,
    get_category,
    list_categories,
    update_category,
)
from database import get_session
from schemas.category import CategoryCreate, CategoryRead, CategoryUpdate

router = APIRouter(prefix="/categories", tags=["categories"])


@router.post("/", response_model=CategoryRead, status_code=status.HTTP_201_CREATED)
async def create_category_route(categoria: CategoryCreate, session: Session = Depends(get_session)):
    return await create_category(session, categoria)


@router.get("/", response_model=list[CategoryRead])
async def list_categories_route(tenant_id: int, session: Session = Depends(get_session)):
    return await list_categories(session, tenant_id)


@router.get("/{category_id}", response_model=CategoryRead)
async def get_category_route(category_id: int, session: Session = Depends(get_session)):
    return await get_category(session, category_id)


@router.patch("/{category_id}", response_model=CategoryRead)
async def update_category_route(
    category_id: int, categoria: CategoryUpdate, session: Session = Depends(get_session)
):
    return await update_category(session, category_id, categoria)


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category_route(category_id: int, session: Session = Depends(get_session)):
    await delete_category(session, category_id)
```

De onde vem cada parâmetro? O FastAPI descobre sozinho:

| Parâmetro             | Está em...                     | Exemplo                       |
|-----------------------|--------------------------------|-------------------------------|
| `category_id: int`    | **path** (está na URL `{}`)    | `/categories/5`               |
| `tenant_id: int`      | **query** (não está na URL)    | `/categories?tenant_id=1`     |
| `categoria: CategoryUpdate` | **corpo** (é um schema)  | `{"name": "Novo nome"}`       |
| `session`             | **dependência** (`Depends`)    | o FastAPI abre a sessão       |

> **Mudanças em relação ao `POST` original:** a função foi renomeada de `create_task` para `create_category_route` (o nome aparece no `/docs`), ganhou `response_model=CategoryRead` e `status_code=201`.

### Atualizar os `__init__.py`

```python
# controller/__init__.py
from controller.auth import get_current_user, login, read_me
from controller.category import (
    create_category,
    delete_category,
    get_category,
    list_categories,
    update_category,
)
```

```python
# services/__init__.py
from services.auth import authenticate_user, get_user_by_username
from services.category import (
    create_category_service,
    delete_category_service,
    get_category_service,
    list_categories_service,
    update_category_service,
)
```

> Os `__init__.py` de `controller`, `services` e `schemas` são opcionais (as rotas importam direto do arquivo). Se quiser manter, acrescente as funções novas de cada model do mesmo jeito.

### Endpoints de categoria

| Método | Rota                          | O que faz                |
|--------|-------------------------------|--------------------------|
| POST   | `/categories/`                | Cria                     |
| GET    | `/categories/?tenant_id=1`    | Lista as do tenant       |
| GET    | `/categories/{id}`            | Detalhe                  |
| PATCH  | `/categories/{id}`            | Altera                   |
| DELETE | `/categories/{id}`            | Apaga (se não estiver em uso) |

---

## Parte 2 — Tenant (a loja)

Cada tenant é uma locadora. Ele guarda as **regras de locação** que a Booking vai usar: `min_rental_hours`, `max_rental_days` e `advance_booking_days`.

### `schemas/tenant.py`

```python
from sqlmodel import Field, SQLModel

from models.enums import TenantStatus


class TenantCreate(SQLModel):
    name: str = Field(max_length=100)
    slug: str = Field(max_length=100)
    domain: str | None = None
    logo_url: str | None = None
    currency: str = "BRL"
    timezone: str = "America/Sao_Paulo"
    language: str = "pt-BR"
    min_rental_hours: int = Field(default=2, ge=1)
    max_rental_days: int = Field(default=30, ge=1)
    advance_booking_days: int = Field(default=90, ge=0)


class TenantRead(SQLModel):
    id: int
    name: str
    slug: str
    domain: str | None
    logo_url: str | None
    currency: str
    timezone: str
    language: str
    min_rental_hours: int
    max_rental_days: int
    advance_booking_days: int
    status: TenantStatus


class TenantUpdate(SQLModel):
    name: str | None = Field(default=None, max_length=100)
    slug: str | None = Field(default=None, max_length=100)
    domain: str | None = None
    logo_url: str | None = None
    currency: str | None = None
    timezone: str | None = None
    language: str | None = None
    min_rental_hours: int | None = Field(default=None, ge=1)
    max_rental_days: int | None = Field(default=None, ge=1)
    advance_booking_days: int | None = Field(default=None, ge=0)
    status: TenantStatus | None = None
```

`Field(ge=1)` significa "maior ou igual a 1". O FastAPI recusa sozinho valores menores (responde `422` sem nem chegar no service).

### `services/tenant.py`

```python
from fastapi import HTTPException, status
from sqlmodel import Session, select

from models.enums import TenantStatus
from models.tenant import Tenant
from schemas.tenant import TenantCreate, TenantUpdate


def _check_slug_available(session: Session, slug: str, ignore_id: int | None = None) -> None:
    """No tenant o slug e unico no sistema inteiro."""
    statement = select(Tenant).where(Tenant.slug == slug)
    if ignore_id is not None:
        statement = statement.where(Tenant.id != ignore_id)
    if session.exec(statement).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ja existe um tenant com esse slug",
        )


async def create_tenant_service(session: Session, tenant: TenantCreate) -> Tenant:
    _check_slug_available(session, tenant.slug)

    new_tenant = Tenant(**tenant.model_dump())
    session.add(new_tenant)
    session.commit()
    session.refresh(new_tenant)
    return new_tenant


async def list_tenants_service(session: Session) -> list[Tenant]:
    return list(session.exec(select(Tenant).order_by(Tenant.name)).all())


async def get_tenant_service(session: Session, tenant_id: int) -> Tenant:
    tenant = session.get(Tenant, tenant_id)
    if not tenant:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tenant nao encontrado")
    return tenant


async def update_tenant_service(session: Session, tenant_id: int, data: TenantUpdate) -> Tenant:
    tenant = await get_tenant_service(session, tenant_id)
    changes = data.model_dump(exclude_unset=True)

    if "slug" in changes:
        _check_slug_available(session, changes["slug"], ignore_id=tenant.id)

    tenant.sqlmodel_update(changes)
    session.add(tenant)
    session.commit()
    session.refresh(tenant)
    return tenant


async def delete_tenant_service(session: Session, tenant_id: int) -> Tenant:
    """Nao apaga de verdade: o tenant tem usuarios, itens e locacoes. So desativa."""
    tenant = await get_tenant_service(session, tenant_id)
    tenant.status = TenantStatus.INACTIVE
    session.add(tenant)
    session.commit()
    session.refresh(tenant)
    return tenant
```

> **Soft delete** ("apagar de mentira"): em vez de `session.delete(...)`, mudamos um campo de status. O registro continua no banco e o histórico (locações antigas) não quebra. Vamos usar isso em Tenant, User e Item.

### `controller/tenant.py`

```python
from sqlmodel import Session

from models.tenant import Tenant
from schemas.tenant import TenantCreate, TenantUpdate
from services.tenant import (
    create_tenant_service,
    delete_tenant_service,
    get_tenant_service,
    list_tenants_service,
    update_tenant_service,
)


async def create_tenant(session: Session, tenant: TenantCreate) -> Tenant:
    return await create_tenant_service(session, tenant)


async def list_tenants(session: Session) -> list[Tenant]:
    return await list_tenants_service(session)


async def get_tenant(session: Session, tenant_id: int) -> Tenant:
    return await get_tenant_service(session, tenant_id)


async def update_tenant(session: Session, tenant_id: int, tenant: TenantUpdate) -> Tenant:
    return await update_tenant_service(session, tenant_id, tenant)


async def delete_tenant(session: Session, tenant_id: int) -> Tenant:
    return await delete_tenant_service(session, tenant_id)
```

### `routes/tenant.py`

```python
from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from controller.tenant import create_tenant, delete_tenant, get_tenant, list_tenants, update_tenant
from database import get_session
from schemas.tenant import TenantCreate, TenantRead, TenantUpdate

router = APIRouter(prefix="/tenants", tags=["tenants"])


@router.post("/", response_model=TenantRead, status_code=status.HTTP_201_CREATED)
async def create_tenant_route(tenant: TenantCreate, session: Session = Depends(get_session)):
    return await create_tenant(session, tenant)


@router.get("/", response_model=list[TenantRead])
async def list_tenants_route(session: Session = Depends(get_session)):
    return await list_tenants(session)


@router.get("/{tenant_id}", response_model=TenantRead)
async def get_tenant_route(tenant_id: int, session: Session = Depends(get_session)):
    return await get_tenant(session, tenant_id)


@router.patch("/{tenant_id}", response_model=TenantRead)
async def update_tenant_route(
    tenant_id: int, tenant: TenantUpdate, session: Session = Depends(get_session)
):
    return await update_tenant(session, tenant_id, tenant)


@router.delete("/{tenant_id}", response_model=TenantRead)
async def delete_tenant_route(tenant_id: int, session: Session = Depends(get_session)):
    return await delete_tenant(session, tenant_id)
```

O `DELETE` devolve o tenant (com `status: "inactive"`) em vez de `204`, já que ele continua existindo.

---

## Parte 3 — User (as pessoas)

O usuário pertence a um tenant e tem um papel (`role`): `admin`, `locador` ou `cliente`.

### Antes de começar: ajuste na model

O admin criado pelo [db01.sql](db01.sql) **não tem tenant** (`tenant_id` é `NULL`), porque ele administra o sistema todo. Para a model refletir isso, em [models/user.py](models/user.py) troque:

```python
tenant_id: int = Field(foreign_key="tenants.id", index=True)
```

por:

```python
tenant_id: int | None = Field(default=None, foreign_key="tenants.id", index=True)
```

E em [schemas/auth.py](schemas/auth.py), acrescente o `tenant_id` no `UserRead` (ele é a resposta de todas as rotas de usuário):

```python
class UserRead(SQLModel):
    id: int
    tenant_id: int | None
    username: str
    role: str
    is_active: bool
```

### `schemas/user.py`

```python
from sqlmodel import Field, SQLModel

from models.enums import UserRole


class UserCreate(SQLModel):
    tenant_id: int
    username: str = Field(min_length=3, max_length=50)
    password: str = Field(min_length=6)
    role: UserRole = UserRole.CLIENTE


class UserUpdate(SQLModel):
    username: str | None = Field(default=None, min_length=3, max_length=50)
    password: str | None = Field(default=None, min_length=6)
    role: UserRole | None = None
    is_active: bool | None = None
```

Repare: o schema recebe **`password`**, mas a tabela guarda **`hashed_password`**. Não tem `UserRead` aqui porque vamos usar o de `schemas/auth.py`.

### `services/user.py`

```python
from fastapi import HTTPException, status
from sqlmodel import Session, select

from models.tenant import Tenant
from models.user import User
from schemas.user import UserCreate, UserUpdate
from security import get_password_hash


def _check_username_available(
    session: Session, username: str, ignore_id: int | None = None
) -> None:
    statement = select(User).where(User.username == username)
    if ignore_id is not None:
        statement = statement.where(User.id != ignore_id)
    if session.exec(statement).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ja existe um usuario com esse username",
        )


async def create_user_service(session: Session, data: UserCreate) -> User:
    if not session.get(Tenant, data.tenant_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tenant nao encontrado")
    _check_username_available(session, data.username)

    new_user = User(
        tenant_id=data.tenant_id,
        username=data.username,
        hashed_password=get_password_hash(data.password),  # NUNCA salve a senha pura
        role=data.role,
    )
    session.add(new_user)
    session.commit()
    session.refresh(new_user)
    return new_user


async def list_users_service(session: Session, tenant_id: int) -> list[User]:
    statement = select(User).where(User.tenant_id == tenant_id).order_by(User.username)
    return list(session.exec(statement).all())


async def get_user_service(session: Session, user_id: int) -> User:
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario nao encontrado")
    return user


async def update_user_service(session: Session, user_id: int, data: UserUpdate) -> User:
    user = await get_user_service(session, user_id)
    changes = data.model_dump(exclude_unset=True)

    if "username" in changes:
        _check_username_available(session, changes["username"], ignore_id=user.id)

    # a senha nao vai direto: tira do dicionario e grava o hash
    if "password" in changes:
        user.hashed_password = get_password_hash(changes.pop("password"))

    user.sqlmodel_update(changes)
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


async def delete_user_service(session: Session, user_id: int) -> User:
    """Nao apaga: o usuario pode ter locacoes. So desativa (o login ja recusa inativo)."""
    user = await get_user_service(session, user_id)
    user.is_active = False
    session.add(user)
    session.commit()
    session.refresh(user)
    return user
```

> **Username único no sistema todo:** a model diz que o username é único **por tenant**, mas o login ([services/auth.py](services/auth.py)) busca o usuário só pelo username, sem tenant, e o `db01.sql` cria a coluna como `UNIQUE`. Por isso o service confere o username no sistema inteiro: assim o login nunca pega o usuário errado.

### `controller/user.py`

```python
from sqlmodel import Session

from models.user import User
from schemas.user import UserCreate, UserUpdate
from services.user import (
    create_user_service,
    delete_user_service,
    get_user_service,
    list_users_service,
    update_user_service,
)


async def create_user(session: Session, user: UserCreate) -> User:
    return await create_user_service(session, user)


async def list_users(session: Session, tenant_id: int) -> list[User]:
    return await list_users_service(session, tenant_id)


async def get_user(session: Session, user_id: int) -> User:
    return await get_user_service(session, user_id)


async def update_user(session: Session, user_id: int, user: UserUpdate) -> User:
    return await update_user_service(session, user_id, user)


async def delete_user(session: Session, user_id: int) -> User:
    return await delete_user_service(session, user_id)
```

### `routes/user.py`

```python
from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from controller.user import create_user, delete_user, get_user, list_users, update_user
from database import get_session
from schemas.auth import UserRead
from schemas.user import UserCreate, UserUpdate

router = APIRouter(prefix="/users", tags=["users"])


@router.post("/", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def create_user_route(user: UserCreate, session: Session = Depends(get_session)):
    return await create_user(session, user)


@router.get("/", response_model=list[UserRead])
async def list_users_route(tenant_id: int, session: Session = Depends(get_session)):
    return await list_users(session, tenant_id)


@router.get("/{user_id}", response_model=UserRead)
async def get_user_route(user_id: int, session: Session = Depends(get_session)):
    return await get_user(session, user_id)


@router.patch("/{user_id}", response_model=UserRead)
async def update_user_route(user_id: int, user: UserUpdate, session: Session = Depends(get_session)):
    return await update_user(session, user_id, user)


@router.delete("/{user_id}", response_model=UserRead)
async def delete_user_route(user_id: int, session: Session = Depends(get_session)):
    return await delete_user(session, user_id)
```

O `response_model=UserRead` é o que **garante que o `hashed_password` nunca aparece na resposta**: o `UserRead` não tem esse campo, então o FastAPI o descarta.

---

## Parte 4 — Item (o que se aluga)

### `schemas/item.py`

```python
from decimal import Decimal

from sqlmodel import Field, SQLModel

from models.enums import ItemStatus


class ItemCreate(SQLModel):
    tenant_id: int
    category_id: int | None = None
    owner_id: int | None = None
    name: str = Field(max_length=150)
    slug: str = Field(max_length=150)
    description: str | None = Field(default=None, max_length=1000)
    daily_price: Decimal = Field(ge=0, max_digits=10, decimal_places=2)
    hourly_price: Decimal | None = Field(default=None, ge=0, max_digits=10, decimal_places=2)
    image_url: str | None = None


class ItemRead(SQLModel):
    id: int
    tenant_id: int
    category_id: int | None
    owner_id: int | None
    name: str
    slug: str
    description: str | None
    daily_price: Decimal
    hourly_price: Decimal | None
    image_url: str | None
    status: ItemStatus
    is_active: bool


class ItemUpdate(SQLModel):
    category_id: int | None = None
    owner_id: int | None = None
    name: str | None = Field(default=None, max_length=150)
    slug: str | None = Field(default=None, max_length=150)
    description: str | None = Field(default=None, max_length=1000)
    daily_price: Decimal | None = Field(default=None, ge=0, max_digits=10, decimal_places=2)
    hourly_price: Decimal | None = Field(default=None, ge=0, max_digits=10, decimal_places=2)
    image_url: str | None = None
    status: ItemStatus | None = None
    is_active: bool | None = None
```

Use **`Decimal`** para dinheiro, nunca `float`: `0.1 + 0.2` em float dá `0.30000000000000004`.

### `services/item.py`

```python
from fastapi import HTTPException, status
from sqlmodel import Session, select

from models.category import Category
from models.enums import UserRole
from models.item import Item
from models.tenant import Tenant
from models.user import User
from schemas.item import ItemCreate, ItemUpdate


def _check_slug_available(
    session: Session, tenant_id: int, slug: str, ignore_id: int | None = None
) -> None:
    statement = select(Item).where(Item.tenant_id == tenant_id, Item.slug == slug)
    if ignore_id is not None:
        statement = statement.where(Item.id != ignore_id)
    if session.exec(statement).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ja existe um item com esse slug",
        )


def _check_category(session: Session, tenant_id: int, category_id: int) -> None:
    """A categoria precisa existir E ser do mesmo tenant do item."""
    category = session.get(Category, category_id)
    if not category or category.tenant_id != tenant_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Categoria nao encontrada")


def _check_owner(session: Session, tenant_id: int, owner_id: int) -> None:
    """O dono do item precisa ser um locador do mesmo tenant."""
    owner = session.get(User, owner_id)
    if not owner or owner.tenant_id != tenant_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dono do item nao encontrado")
    if owner.role != UserRole.LOCADOR:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Somente um locador pode ser dono de item",
        )


async def create_item_service(session: Session, data: ItemCreate) -> Item:
    if not session.get(Tenant, data.tenant_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tenant nao encontrado")
    _check_slug_available(session, data.tenant_id, data.slug)
    if data.category_id is not None:
        _check_category(session, data.tenant_id, data.category_id)
    if data.owner_id is not None:
        _check_owner(session, data.tenant_id, data.owner_id)

    new_item = Item(**data.model_dump())
    session.add(new_item)
    session.commit()
    session.refresh(new_item)
    return new_item


async def list_items_service(
    session: Session, tenant_id: int, category_id: int | None = None
) -> list[Item]:
    statement = select(Item).where(Item.tenant_id == tenant_id)
    if category_id is not None:  # filtro opcional
        statement = statement.where(Item.category_id == category_id)
    return list(session.exec(statement.order_by(Item.name)).all())


async def get_item_service(session: Session, item_id: int) -> Item:
    item = session.get(Item, item_id)
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item nao encontrado")
    return item


async def update_item_service(session: Session, item_id: int, data: ItemUpdate) -> Item:
    item = await get_item_service(session, item_id)
    changes = data.model_dump(exclude_unset=True)

    if "slug" in changes:
        _check_slug_available(session, item.tenant_id, changes["slug"], ignore_id=item.id)
    if changes.get("category_id") is not None:
        _check_category(session, item.tenant_id, changes["category_id"])
    if changes.get("owner_id") is not None:
        _check_owner(session, item.tenant_id, changes["owner_id"])

    item.sqlmodel_update(changes)
    session.add(item)
    session.commit()
    session.refresh(item)
    return item


async def delete_item_service(session: Session, item_id: int) -> Item:
    """Nao apaga: o item tem historico de locacoes. So desativa."""
    item = await get_item_service(session, item_id)
    item.is_active = False
    session.add(item)
    session.commit()
    session.refresh(item)
    return item
```

### `controller/item.py`

```python
from sqlmodel import Session

from models.item import Item
from schemas.item import ItemCreate, ItemUpdate
from services.item import (
    create_item_service,
    delete_item_service,
    get_item_service,
    list_items_service,
    update_item_service,
)


async def create_item(session: Session, item: ItemCreate) -> Item:
    return await create_item_service(session, item)


async def list_items(session: Session, tenant_id: int, category_id: int | None = None) -> list[Item]:
    return await list_items_service(session, tenant_id, category_id)


async def get_item(session: Session, item_id: int) -> Item:
    return await get_item_service(session, item_id)


async def update_item(session: Session, item_id: int, item: ItemUpdate) -> Item:
    return await update_item_service(session, item_id, item)


async def delete_item(session: Session, item_id: int) -> Item:
    return await delete_item_service(session, item_id)
```

### `routes/item.py`

```python
from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from controller.item import create_item, delete_item, get_item, list_items, update_item
from database import get_session
from schemas.item import ItemCreate, ItemRead, ItemUpdate

router = APIRouter(prefix="/items", tags=["items"])


@router.post("/", response_model=ItemRead, status_code=status.HTTP_201_CREATED)
async def create_item_route(item: ItemCreate, session: Session = Depends(get_session)):
    return await create_item(session, item)


@router.get("/", response_model=list[ItemRead])
async def list_items_route(
    tenant_id: int, category_id: int | None = None, session: Session = Depends(get_session)
):
    return await list_items(session, tenant_id, category_id)


@router.get("/{item_id}", response_model=ItemRead)
async def get_item_route(item_id: int, session: Session = Depends(get_session)):
    return await get_item(session, item_id)


@router.patch("/{item_id}", response_model=ItemRead)
async def update_item_route(item_id: int, item: ItemUpdate, session: Session = Depends(get_session)):
    return await update_item(session, item_id, item)


@router.delete("/{item_id}", response_model=ItemRead)
async def delete_item_route(item_id: int, session: Session = Depends(get_session)):
    return await delete_item(session, item_id)
```

Exemplo de filtro: `GET /items/?tenant_id=1&category_id=2`.

---

## Parte 5 — Booking (o agendamento / a locação) ⭐

A Booking é o centro do sistema: ela **liga um Item a um User durante um período**. É a parte com mais regras.

```
 User (cliente) ──┐
                  ├──► Booking (start_at → end_at, status, total_amount)
 Item ────────────┘
```

- `start_at` = **data de retirada** do item
- `end_at` = **data de devolução** do item

### Regras

| # | Regra                                                                     | Erro |
|---|---------------------------------------------------------------------------|------|
| 1 | Tenant, item e usuário existem e são do **mesmo tenant**                  | 404  |
| 2 | Item ativo e com `status = available`; usuário ativo                      | 422  |
| 3 | `end_at` depois de `start_at`, e `start_at` não está no passado           | 422  |
| 4 | Respeita o tenant: duração ≥ `min_rental_hours`, ≤ `max_rental_days`, início em até `advance_booking_days` | 422 |
| 5 | **O item não pode ter outra locação ativa no mesmo período**              | 409  |
| 6 | O **valor total é calculado pelo servidor**, nunca enviado pelo cliente   | —    |
| 7 | O status só muda pelos caminhos permitidos (abaixo)                       | 422  |
| 8 | Booking **não é apagada**: é cancelada, para manter o histórico           | —    |

### Ciclo de vida (status)

```
             confirm             complete
  PENDING ───────────► CONFIRMED ───────────► COMPLETED
     │                     │
     │ cancel              │ cancel
     ▼                     ▼
  CANCELLED            CANCELLED
```

`CANCELLED` e `COMPLETED` são finais. As datas só podem ser alteradas enquanto a locação está `PENDING`.

### Como saber se dois períodos se chocam

Duas locações do mesmo item se sobrepõem quando **uma começa antes da outra terminar, e termina depois da outra começar**:

```
existente:        |=========|
nova:       |=======|              → choca
nova:                 |=======|    → choca
nova:                       |====| → NÃO choca (começa exatamente quando a outra termina)
```

Em código: `existente.start_at < nova.end_at` **e** `existente.end_at > nova.start_at`. Só contam as locações `PENDING` e `CONFIRMED`; as canceladas e concluídas liberam o horário.

### Como o valor é calculado

- As horas são arredondadas **para cima** (2h10 conta como 3h).
- Menos de 24h **e** o item tem `hourly_price` → `horas × hourly_price`.
- Senão → dias arredondados para cima × `daily_price` (25h contam como 2 diárias).

### Fuso horário

O service converte toda data que chega para **UTC** antes de comparar e salvar. O front deve mandar a data com o fuso, por exemplo `2026-10-20T09:00:00-03:00` (9h de Brasília). Uma data sem fuso é tratada como UTC. Se aparecer o erro `can't compare offset-naive and offset-aware datetimes`, é alguma data que não passou pelo `_to_utc`.

### `schemas/booking.py`

```python
from datetime import datetime
from decimal import Decimal

from sqlmodel import Field, SQLModel

from models.enums import BookingStatus


class BookingCreate(SQLModel):
    tenant_id: int
    item_id: int
    user_id: int          # o cliente que esta alugando
    start_at: datetime    # retirada
    end_at: datetime      # devolucao
    notes: str | None = Field(default=None, max_length=500)


class BookingRead(SQLModel):
    id: int
    tenant_id: int
    item_id: int
    user_id: int
    start_at: datetime
    end_at: datetime
    status: BookingStatus
    total_amount: Decimal | None
    notes: str | None


class BookingUpdate(SQLModel):
    start_at: datetime | None = None
    end_at: datetime | None = None
    notes: str | None = Field(default=None, max_length=500)


class AvailabilityRead(SQLModel):
    item_id: int
    start_at: datetime
    end_at: datetime
    available: bool
```

Repare: **não existe `status` nem `total_amount` no `BookingCreate`**. Se existissem, alguém poderia criar uma locação já confirmada ou com preço R$ 0,01.

### `services/booking.py`

```python
import math
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from fastapi import HTTPException, status
from sqlmodel import Session, col, select

from models.booking import Booking
from models.enums import BookingStatus, ItemStatus, TenantStatus
from models.item import Item
from models.tenant import Tenant
from models.user import User
from schemas.booking import BookingCreate, BookingUpdate

# locacoes nesses status ocupam o item
ACTIVE_STATUSES = [BookingStatus.PENDING, BookingStatus.CONFIRMED]

# para onde cada status pode ir
ALLOWED_TRANSITIONS = {
    BookingStatus.PENDING: {BookingStatus.CONFIRMED, BookingStatus.CANCELLED},
    BookingStatus.CONFIRMED: {BookingStatus.COMPLETED, BookingStatus.CANCELLED},
    BookingStatus.CANCELLED: set(),
    BookingStatus.COMPLETED: set(),
}


def _error(code: int, message: str) -> HTTPException:
    return HTTPException(status_code=code, detail=message)


# ---------- datas ----------

def _to_utc(value: datetime) -> datetime:
    """Deixa toda data em UTC. Data sem fuso e tratada como UTC."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ---------- validacoes ----------

def _get_active_tenant(session: Session, tenant_id: int) -> Tenant:
    tenant = session.get(Tenant, tenant_id)
    if not tenant or tenant.status != TenantStatus.ACTIVE:
        raise _error(status.HTTP_404_NOT_FOUND, "Tenant nao encontrado")
    return tenant


def _get_bookable_item(session: Session, tenant_id: int, item_id: int) -> Item:
    # with_for_update trava a linha do item ate o commit. Se duas pessoas tentarem
    # reservar o mesmo item ao mesmo tempo, a segunda espera a primeira terminar
    # e entao ve a reserva dela na checagem de conflito.
    statement = select(Item).where(Item.id == item_id).with_for_update()
    item = session.exec(statement).first()
    if not item or item.tenant_id != tenant_id:
        raise _error(status.HTTP_404_NOT_FOUND, "Item nao encontrado")
    if not item.is_active or item.status != ItemStatus.AVAILABLE:
        raise _error(status.HTTP_422_UNPROCESSABLE_ENTITY, "Item indisponivel para locacao")
    return item


def _get_active_user(session: Session, tenant_id: int, user_id: int) -> User:
    user = session.get(User, user_id)
    if not user or user.tenant_id != tenant_id:
        raise _error(status.HTTP_404_NOT_FOUND, "Usuario nao encontrado")
    if not user.is_active:
        raise _error(status.HTTP_422_UNPROCESSABLE_ENTITY, "Usuario inativo")
    return user


def _validate_period(tenant: Tenant, start_at: datetime, end_at: datetime) -> None:
    now = _now()
    if end_at <= start_at:
        raise _error(status.HTTP_422_UNPROCESSABLE_ENTITY, "A data final deve ser depois da data inicial")
    if start_at < now:
        raise _error(status.HTTP_422_UNPROCESSABLE_ENTITY, "Nao e possivel reservar no passado")
    if start_at > now + timedelta(days=tenant.advance_booking_days):
        raise _error(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"So e possivel reservar com ate {tenant.advance_booking_days} dias de antecedencia",
        )

    duration = end_at - start_at
    if duration < timedelta(hours=tenant.min_rental_hours):
        raise _error(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"A locacao minima e de {tenant.min_rental_hours} horas",
        )
    if duration > timedelta(days=tenant.max_rental_days):
        raise _error(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"A locacao maxima e de {tenant.max_rental_days} dias",
        )


def _has_overlap(
    session: Session,
    item_id: int,
    start_at: datetime,
    end_at: datetime,
    ignore_id: int | None = None,
) -> bool:
    statement = select(Booking).where(
        Booking.item_id == item_id,
        col(Booking.status).in_(ACTIVE_STATUSES),
        Booking.start_at < end_at,
        Booking.end_at > start_at,
    )
    if ignore_id is not None:
        statement = statement.where(Booking.id != ignore_id)
    return session.exec(statement).first() is not None


def calculate_total(item: Item, start_at: datetime, end_at: datetime) -> Decimal:
    hours = math.ceil((end_at - start_at).total_seconds() / 3600)
    if item.hourly_price is not None and hours < 24:
        total = item.hourly_price * hours
    else:
        days = math.ceil(hours / 24)
        total = item.daily_price * days
    return Decimal(total).quantize(Decimal("0.01"))


# ---------- CRUD ----------

async def get_booking_service(session: Session, booking_id: int) -> Booking:
    booking = session.get(Booking, booking_id)
    if not booking:
        raise _error(status.HTTP_404_NOT_FOUND, "Locacao nao encontrada")
    return booking


async def list_bookings_service(
    session: Session,
    tenant_id: int,
    item_id: int | None = None,
    user_id: int | None = None,
    booking_status: BookingStatus | None = None,
) -> list[Booking]:
    statement = select(Booking).where(Booking.tenant_id == tenant_id)
    if item_id is not None:
        statement = statement.where(Booking.item_id == item_id)
    if user_id is not None:
        statement = statement.where(Booking.user_id == user_id)
    if booking_status is not None:
        statement = statement.where(Booking.status == booking_status)
    statement = statement.order_by(col(Booking.start_at))
    return list(session.exec(statement).all())


async def check_availability_service(
    session: Session, item_id: int, start_at: datetime, end_at: datetime
) -> bool:
    return not _has_overlap(session, item_id, _to_utc(start_at), _to_utc(end_at))


async def create_booking_service(session: Session, data: BookingCreate) -> Booking:
    tenant = _get_active_tenant(session, data.tenant_id)
    item = _get_bookable_item(session, data.tenant_id, data.item_id)
    _get_active_user(session, data.tenant_id, data.user_id)

    start_at = _to_utc(data.start_at)
    end_at = _to_utc(data.end_at)
    _validate_period(tenant, start_at, end_at)

    if _has_overlap(session, item.id, start_at, end_at):
        raise _error(status.HTTP_409_CONFLICT, "O item ja esta reservado nesse periodo")

    booking = Booking(
        tenant_id=data.tenant_id,
        item_id=item.id,
        user_id=data.user_id,
        start_at=start_at,
        end_at=end_at,
        notes=data.notes,
        total_amount=calculate_total(item, start_at, end_at),  # calculado aqui, nunca recebido
    )
    session.add(booking)
    session.commit()
    session.refresh(booking)
    return booking


async def update_booking_service(session: Session, booking_id: int, data: BookingUpdate) -> Booking:
    booking = await get_booking_service(session, booking_id)
    if booking.status != BookingStatus.PENDING:
        raise _error(status.HTTP_422_UNPROCESSABLE_ENTITY, "So e possivel alterar locacoes pendentes")

    changes = data.model_dump(exclude_unset=True)

    if "start_at" in changes or "end_at" in changes:
        start_at = _to_utc(changes.get("start_at") or booking.start_at)
        end_at = _to_utc(changes.get("end_at") or booking.end_at)

        tenant = _get_active_tenant(session, booking.tenant_id)
        item = _get_bookable_item(session, booking.tenant_id, booking.item_id)
        _validate_period(tenant, start_at, end_at)

        # ignore_id: a propria locacao nao conta como conflito
        if _has_overlap(session, item.id, start_at, end_at, ignore_id=booking.id):
            raise _error(status.HTTP_409_CONFLICT, "O item ja esta reservado nesse periodo")

        booking.start_at = start_at
        booking.end_at = end_at
        booking.total_amount = calculate_total(item, start_at, end_at)

    if "notes" in changes:
        booking.notes = changes["notes"]

    session.add(booking)
    session.commit()
    session.refresh(booking)
    return booking


async def change_booking_status_service(
    session: Session, booking_id: int, new_status: BookingStatus
) -> Booking:
    booking = await get_booking_service(session, booking_id)
    if new_status not in ALLOWED_TRANSITIONS[booking.status]:
        raise _error(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"Nao e possivel mudar de '{booking.status.value}' para '{new_status.value}'",
        )
    booking.status = new_status
    session.add(booking)
    session.commit()
    session.refresh(booking)
    return booking
```

Pontos que valem explicar em aula:

- **`col(Booking.status).in_(...)`**: o `col()` do SQLModel avisa ao editor que aquilo é uma coluna do banco, para ele aceitar o `.in_()`.
- **`with_for_update()`**: sem a trava, duas requisições ao mesmo tempo poderiam passar as duas pela checagem de conflito antes de qualquer uma salvar, e o item ficaria reservado duas vezes. (No SQLite a trava é ignorada; no MySQL funciona.)
- **`ignore_id` no update**: ao mudar as datas de uma locação, ela mesma ainda está no banco com as datas antigas. Sem o `ignore_id`, ela conflitaria consigo mesma.
- **`booking_status` em vez de `status`**: o nome `status` já é o módulo `fastapi.status` importado no arquivo.
- **Mudar o preço do item depois não muda as locações antigas**: o `total_amount` é gravado na hora da reserva.

### `controller/booking.py`

```python
from datetime import datetime

from sqlmodel import Session

from models.booking import Booking
from models.enums import BookingStatus
from schemas.booking import AvailabilityRead, BookingCreate, BookingUpdate
from services.booking import (
    change_booking_status_service,
    check_availability_service,
    create_booking_service,
    get_booking_service,
    list_bookings_service,
    update_booking_service,
)


async def create_booking(session: Session, booking: BookingCreate) -> Booking:
    return await create_booking_service(session, booking)


async def list_bookings(
    session: Session,
    tenant_id: int,
    item_id: int | None = None,
    user_id: int | None = None,
    booking_status: BookingStatus | None = None,
) -> list[Booking]:
    return await list_bookings_service(session, tenant_id, item_id, user_id, booking_status)


async def check_availability(
    session: Session, item_id: int, start_at: datetime, end_at: datetime
) -> AvailabilityRead:
    available = await check_availability_service(session, item_id, start_at, end_at)
    return AvailabilityRead(item_id=item_id, start_at=start_at, end_at=end_at, available=available)


async def get_booking(session: Session, booking_id: int) -> Booking:
    return await get_booking_service(session, booking_id)


async def update_booking(session: Session, booking_id: int, booking: BookingUpdate) -> Booking:
    return await update_booking_service(session, booking_id, booking)


async def confirm_booking(session: Session, booking_id: int) -> Booking:
    return await change_booking_status_service(session, booking_id, BookingStatus.CONFIRMED)


async def cancel_booking(session: Session, booking_id: int) -> Booking:
    return await change_booking_status_service(session, booking_id, BookingStatus.CANCELLED)


async def complete_booking(session: Session, booking_id: int) -> Booking:
    return await change_booking_status_service(session, booking_id, BookingStatus.COMPLETED)
```

### `routes/booking.py`

```python
from datetime import datetime

from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from controller.booking import (
    cancel_booking,
    check_availability,
    complete_booking,
    confirm_booking,
    create_booking,
    get_booking,
    list_bookings,
    update_booking,
)
from database import get_session
from models.enums import BookingStatus
from schemas.booking import AvailabilityRead, BookingCreate, BookingRead, BookingUpdate

router = APIRouter(prefix="/bookings", tags=["bookings"])


@router.post("/", response_model=BookingRead, status_code=status.HTTP_201_CREATED)
async def create_booking_route(booking: BookingCreate, session: Session = Depends(get_session)):
    return await create_booking(session, booking)


@router.get("/", response_model=list[BookingRead])
async def list_bookings_route(
    tenant_id: int,
    item_id: int | None = None,
    user_id: int | None = None,
    booking_status: BookingStatus | None = None,
    session: Session = Depends(get_session),
):
    return await list_bookings(session, tenant_id, item_id, user_id, booking_status)


# precisa vir ANTES de "/{booking_id}", senao o FastAPI tenta ler "availability" como id
@router.get("/availability", response_model=AvailabilityRead)
async def check_availability_route(
    item_id: int, start_at: datetime, end_at: datetime, session: Session = Depends(get_session)
):
    return await check_availability(session, item_id, start_at, end_at)


@router.get("/{booking_id}", response_model=BookingRead)
async def get_booking_route(booking_id: int, session: Session = Depends(get_session)):
    return await get_booking(session, booking_id)


@router.patch("/{booking_id}", response_model=BookingRead)
async def update_booking_route(
    booking_id: int, booking: BookingUpdate, session: Session = Depends(get_session)
):
    return await update_booking(session, booking_id, booking)


@router.post("/{booking_id}/confirm", response_model=BookingRead)
async def confirm_booking_route(booking_id: int, session: Session = Depends(get_session)):
    return await confirm_booking(session, booking_id)


@router.post("/{booking_id}/cancel", response_model=BookingRead)
async def cancel_booking_route(booking_id: int, session: Session = Depends(get_session)):
    return await cancel_booking(session, booking_id)


@router.post("/{booking_id}/complete", response_model=BookingRead)
async def complete_booking_route(booking_id: int, session: Session = Depends(get_session)):
    return await complete_booking(session, booking_id)
```

| Método | Rota                                                        | O que faz                        |
|--------|-------------------------------------------------------------|----------------------------------|
| POST   | `/bookings/`                                                | Cria uma locação (`pending`)     |
| GET    | `/bookings/?tenant_id=1&item_id=&user_id=&booking_status=`  | Lista com filtros opcionais      |
| GET    | `/bookings/availability?item_id=1&start_at=...&end_at=...`  | O item está livre nesse período? |
| GET    | `/bookings/{id}`                                            | Detalhe                          |
| PATCH  | `/bookings/{id}`                                            | Muda datas/notas (só `pending`)  |
| POST   | `/bookings/{id}/confirm`                                    | `pending` → `confirmed`          |
| POST   | `/bookings/{id}/cancel`                                     | → `cancelled`                    |
| POST   | `/bookings/{id}/complete`                                   | `confirmed` → `completed`        |

Não existe `DELETE`: locação é cancelada, nunca apagada. As mudanças de status são `POST` em sub-rotas (`/confirm`, `/cancel`...) em vez de um `PATCH` com `status`, assim cada ação tem uma URL clara e não dá para pular etapas.

---

## Parte 6 — Registrar tudo e testar

### `routes/__init__.py`

```python
from routes.auth import router as auth_router
from routes.booking import router as booking_router
from routes.category import router as category_router
from routes.health import router as health_router
from routes.item import router as item_router
from routes.tenant import router as tenant_router
from routes.user import router as user_router

__all__ = [
    "auth_router",
    "booking_router",
    "category_router",
    "health_router",
    "item_router",
    "tenant_router",
    "user_router",
]
```

> Os nomes mudaram: `category` virou `category_router` e `health_check` virou `health_router`, para todos seguirem o mesmo padrão. Lembre de ajustar o `main.py`.

### `main.py`

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from database import create_db_and_tables
from routes import (
    auth_router,
    booking_router,
    category_router,
    health_router,
    item_router,
    tenant_router,
    user_router,
)

app = FastAPI(title="Template INFO8B API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup():
    create_db_and_tables()


app.include_router(health_router)
app.include_router(auth_router)
app.include_router(tenant_router)
app.include_router(user_router)
app.include_router(category_router)
app.include_router(item_router)
app.include_router(booking_router)
```

### Roteiro de teste (no `/docs`)

Rode a API e abra `http://localhost:8000/docs`. Use datas no futuro (troque pelos próximos dias).

**1. Tenant** — `POST /tenants/`
```json
{ "name": "Loca Tudo", "slug": "loca-tudo", "min_rental_hours": 2, "max_rental_days": 30 }
```

**2. Usuários** — `POST /users/` duas vezes
```json
{ "tenant_id": 1, "username": "dono", "password": "123456", "role": "locador" }
```
```json
{ "tenant_id": 1, "username": "joana", "password": "123456", "role": "cliente" }
```
→ Confira que a resposta **não** mostra a senha. Anote os ids (com o admin do `db01.sql` sendo o `1`, `dono` fica com `2` e `joana` com `3`).

**3. Categoria** — `POST /categories/`
```json
{ "tenant_id": 1, "name": "Ferramentas", "slug": "ferramentas" }
```

**4. Item** — `POST /items/`
```json
{
  "tenant_id": 1, "category_id": 1, "owner_id": 2,
  "name": "Furadeira Bosch", "slug": "furadeira-bosch",
  "daily_price": "50.00", "hourly_price": "10.00"
}
```

**5. Locação para a Joana** — `POST /bookings/`
```json
{
  "tenant_id": 1, "item_id": 1, "user_id": 3,
  "start_at": "2026-10-20T09:00:00-03:00",
  "end_at":   "2026-10-20T13:00:00-03:00"
}
```
→ `201`, `status: "pending"`, `total_amount: "40.00"` (4h × R$ 10)

**6. Testar as regras**

| Teste                                                                  | Esperado |
|------------------------------------------------------------------------|----------|
| `POST /categories/` com o mesmo slug                                   | `409`    |
| `PATCH /categories/1` com `{"name": "Ferramentas Elétricas"}`          | `200`, só o nome muda |
| `DELETE /categories/1` (o item usa ela)                                | `409`    |
| `POST /items/` com `"owner_id": 3` (Joana é cliente)                   | `422`    |
| `GET /items/?tenant_id=1&category_id=1`                                | lista a furadeira |
| Mesma locação de novo (mesmo item e horário)                           | `409`    |
| Das `12:00` às `15:00` do mesmo dia (sobrepõe uma hora)                | `409`    |
| Das `13:00` às `16:00` (começa quando a outra termina)                 | `201`    |
| Das `09:00` às `10:00` de outro dia (só 1h, mínimo é 2h)               | `422`    |
| `end_at` antes de `start_at`                                           | `422`    |
| Data no passado                                                        | `422`    |
| De um dia às 09:00 até o dia seguinte às 10:00 (25h)                   | `total_amount` = 2 diárias = `100.00` |
| `GET /bookings/availability?item_id=1&start_at=...&end_at=...` num horário reservado | `available: false` |
| `POST /bookings/1/complete` ainda `pending`                            | `422`    |
| `POST /bookings/1/confirm` → depois `POST /bookings/1/complete`        | `200` e `200` |
| `PATCH /bookings/1` depois de `completed`                              | `422`    |
| `POST /bookings/2/cancel` e criar de novo no mesmo horário             | `201` (cancelada libera o horário) |
| `PATCH /items/1` com `{"status": "maintenance"}` e tentar reservar     | `422`    |
| `DELETE /users/3` e tentar logar como `joana`                          | login recusado (`401`) |

Se tudo isso passou, os CRUDs básicos estão prontos. ✅

---

## Parte 7 — Regras de acesso por papel ⚠️

Até aqui **qualquer pessoa, mesmo sem login, faz tudo**. Agora vamos travar as rotas. Esta é a parte com mais detalhes, então vá com calma e teste a cada model.

### Quem pode fazer o quê

| Papel     | Quem é                         | Alcance                                              |
|-----------|--------------------------------|------------------------------------------------------|
| `admin`   | Administrador da plataforma    | **Global**: age em qualquer tenant (não tem `tenant_id`) |
| `locador` | Backoffice da locadora         | **Só o próprio tenant** (`current_user.tenant_id`)   |
| `cliente` | Quem aluga                     | **Só os próprios itens locados**                     |

| Ação                                                       | admin | locador              | cliente               |
|------------------------------------------------------------|:-----:|:--------------------:|:---------------------:|
| Criar, listar, editar e desativar **tenants**              | ✅    | ❌                    | ❌                     |
| Criar, editar e desativar **usuários**                     | ✅ (só `locador` e `cliente`) | ❌      | ❌                     |
| Listar e ver **usuários** (para escolher o cliente da locação) | ✅ | só do tenant dele | ❌                     |
| CRUD de **categorias** e **itens**                         | ✅    | só do tenant dele    | ❌                     |
| Criar e gerenciar **agendamentos** (confirmar, cancelar...)| ✅    | só do tenant dele    | ❌                     |
| Ver **o que alugou**, com data de retirada e devolução     | —     | —                    | ✅ **só as dele** (`GET /bookings/me`) |

Na prática: quem registra a locação é o locador, escolhendo no corpo da requisição o cliente (`user_id`). O cliente entra no sistema **só para consultar** o que alugou e quando deve retirar e devolver.

Como as rotas passam a exigir login, **toda requisição precisa do token**. No `/docs`, clique em **Authorize** e entre com usuário e senha.

| Status | Quando                                                          |
|--------|-----------------------------------------------------------------|
| `401`  | Sem token, token vencido ou usuário inativo                     |
| `403`  | Logado, mas o papel não permite ou o registro é de outro tenant |

### Passo 1 — Criar `controller/permissions.py`

Este arquivo concentra todas as checagens. Ele reaproveita o `get_current_user` que já existe em [controller/auth.py](controller/auth.py), que lê o token e devolve o usuário logado.

```python
from typing import Annotated, Callable

from fastapi import Depends, HTTPException, status

from controller.auth import get_current_user
from models.enums import UserRole
from models.user import User

# qualquer usuario logado
CurrentUser = Annotated[User, Depends(get_current_user)]


def require_roles(*roles: UserRole) -> Callable[[User], User]:
    """Cria uma dependencia que so deixa passar os papeis informados."""

    def dependency(current_user: CurrentUser) -> User:
        if current_user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Voce nao tem permissao para esta acao",
            )
        return current_user

    return dependency


# use estes tipos nos parametros das rotas
AdminUser = Annotated[User, Depends(require_roles(UserRole.ADMIN))]
StaffUser = Annotated[User, Depends(require_roles(UserRole.ADMIN, UserRole.LOCADOR))]
ClienteUser = Annotated[User, Depends(require_roles(UserRole.CLIENTE))]


def check_tenant_access(user: User, tenant_id: int) -> None:
    """Admin acessa qualquer tenant; o locador, so o proprio."""
    if user.role == UserRole.ADMIN:
        return
    if user.tenant_id != tenant_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Voce so pode acessar dados do seu tenant",
        )


def resolve_tenant_id(user: User, tenant_id: int | None) -> int:
    """Descobre de qual tenant listar. Locador: o dele. Admin: precisa informar."""
    if user.role == UserRole.ADMIN:
        if tenant_id is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Informe o tenant_id",
            )
        return tenant_id
    check_tenant_access(user, tenant_id if tenant_id is not None else user.tenant_id)
    return user.tenant_id
```

| Quero que a rota seja...           | Parâmetro na rota                |
|------------------------------------|----------------------------------|
| Só admin                           | `current_user: AdminUser`        |
| Admin ou locador                   | `current_user: StaffUser`        |
| Só cliente                         | `current_user: ClienteUser`      |
| Qualquer usuário logado            | `current_user: CurrentUser`      |

O FastAPI resolve a dependência **antes** de entrar na função: se o papel não bate, a resposta é `403` e o service nem é chamado. Sem token, a resposta é `401`.

Além do papel, o **locador só mexe no próprio tenant**. Por isso, depois de saber de qual tenant é o registro, chamamos `check_tenant_access`. São sempre três situações:

| Situação                    | De onde vem o tenant          | O que fazer                                          |
|-----------------------------|-------------------------------|------------------------------------------------------|
| **Criar**                   | do corpo (`data.tenant_id`)   | `check_tenant_access(current_user, data.tenant_id)`  |
| **Ver, editar, apagar por id** | do registro no banco       | busca o registro → `check_tenant_access(current_user, registro.tenant_id)` |
| **Listar**                  | da query (`?tenant_id=`)      | `tenant_id = resolve_tenant_id(current_user, tenant_id)` |

Na listagem, o `tenant_id` da query passa a ser **opcional** (`int | None = None`): o locador nem precisa mandar, o sistema usa o dele. O admin precisa informar.

### Passo 2 — Categoria (exemplo completo, antes → depois)

As checagens ficam no **controller**: ele recebe o `current_user` da rota, confere e só então chama o service. O service não muda nada.

**`routes/category.py`** — cada rota ganha `current_user: StaffUser` e o repassa:

```python
from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from controller.category import (
    create_category,
    delete_category,
    get_category,
    list_categories,
    update_category,
)
from controller.permissions import StaffUser
from database import get_session
from schemas.category import CategoryCreate, CategoryRead, CategoryUpdate

router = APIRouter(prefix="/categories", tags=["categories"])


@router.post("/", response_model=CategoryRead, status_code=status.HTTP_201_CREATED)
async def create_category_route(
    categoria: CategoryCreate, current_user: StaffUser, session: Session = Depends(get_session)
):
    return await create_category(session, current_user, categoria)


@router.get("/", response_model=list[CategoryRead])
async def list_categories_route(
    current_user: StaffUser, tenant_id: int | None = None, session: Session = Depends(get_session)
):
    return await list_categories(session, current_user, tenant_id)


@router.get("/{category_id}", response_model=CategoryRead)
async def get_category_route(
    category_id: int, current_user: StaffUser, session: Session = Depends(get_session)
):
    return await get_category(session, current_user, category_id)


@router.patch("/{category_id}", response_model=CategoryRead)
async def update_category_route(
    category_id: int,
    categoria: CategoryUpdate,
    current_user: StaffUser,
    session: Session = Depends(get_session),
):
    return await update_category(session, current_user, category_id, categoria)


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category_route(
    category_id: int, current_user: StaffUser, session: Session = Depends(get_session)
):
    await delete_category(session, current_user, category_id)
```

**`controller/category.py`** — as três situações da tabela:

```python
from sqlmodel import Session

from controller.permissions import check_tenant_access, resolve_tenant_id
from models.category import Category
from models.user import User
from schemas.category import CategoryCreate, CategoryUpdate
from services.category import (
    create_category_service,
    delete_category_service,
    get_category_service,
    list_categories_service,
    update_category_service,
)


async def create_category(session: Session, current_user: User, categoria: CategoryCreate) -> Category:
    check_tenant_access(current_user, categoria.tenant_id)          # criar: tenant do corpo
    return await create_category_service(session, categoria)


async def list_categories(session: Session, current_user: User, tenant_id: int | None) -> list[Category]:
    tenant_id = resolve_tenant_id(current_user, tenant_id)          # listar
    return await list_categories_service(session, tenant_id)


async def get_category(session: Session, current_user: User, category_id: int) -> Category:
    category = await get_category_service(session, category_id)
    check_tenant_access(current_user, category.tenant_id)           # por id: tenant do registro
    return category


async def update_category(
    session: Session, current_user: User, category_id: int, categoria: CategoryUpdate
) -> Category:
    await get_category(session, current_user, category_id)         # reaproveita a checagem
    return await update_category_service(session, category_id, categoria)


async def delete_category(session: Session, current_user: User, category_id: int) -> None:
    await get_category(session, current_user, category_id)
    return await delete_category_service(session, category_id)
```

Repare no truque: `update` e `delete` chamam o `get_category` do próprio controller, que já busca **e** confere o tenant. Assim a checagem fica escrita uma vez só.

### Passo 3 — Item

**Exatamente igual à categoria.** Troque `Category` por `Item` e faça:

- Todas as rotas com `current_user: StaffUser`.
- `create_item` → `check_tenant_access(current_user, item.tenant_id)`.
- `list_items` → `tenant_id: int | None = None` na rota e `resolve_tenant_id` no controller (o filtro `category_id` continua igual).
- `get_item` → busca e confere `item.tenant_id`; `update_item` e `delete_item` chamam o `get_item` do controller antes do service.

### Passo 4 — Tenant (só admin)

Todas as rotas de tenant são **só admin**. Como não tem checagem de tenant, basta trocar o tipo na rota — o controller nem precisa receber o `current_user`:

```python
from controller.permissions import AdminUser


@router.post("/", response_model=TenantRead, status_code=status.HTTP_201_CREATED)
async def create_tenant_route(
    tenant: TenantCreate, current_user: AdminUser, session: Session = Depends(get_session)
):
    return await create_tenant(session, tenant)
```

Faça o mesmo (`current_user: AdminUser`) em `list`, `get`, `patch` e `delete`. Mesmo que a função não use a variável `current_user`, ela precisa estar nos parâmetros: é ela que dispara a checagem.

> Se você ainda não fez login como admin: o usuário `admin` vem do [db01.sql](db01.sql).

### Passo 5 — User (admin cria; staff consulta)

| Método | Rota               | Quem pode                                              |
|--------|--------------------|--------------------------------------------------------|
| POST   | `/users/`          | `AdminUser`, e só com `role` `locador` ou `cliente`    |
| GET    | `/users/`          | `StaffUser` + `resolve_tenant_id`                      |
| GET    | `/users/{id}`      | `StaffUser` + `check_tenant_access`                    |
| PATCH  | `/users/{id}`      | `AdminUser`, e o `role` novo também só `locador` ou `cliente` |
| DELETE | `/users/{id}`      | `AdminUser` (desativa)                                 |

O locador pode **listar e ver** usuários do tenant dele porque precisa escolher o cliente na hora de criar a locação.

O admin **não cria outro admin** pela API (o único admin vem do `db01.sql`). Essa regra fica no controller:

```python
# controller/user.py
from fastapi import HTTPException, status
from sqlmodel import Session

from controller.permissions import check_tenant_access, resolve_tenant_id
from models.enums import UserRole
from models.user import User
from schemas.user import UserCreate, UserUpdate
from services.user import (
    create_user_service,
    delete_user_service,
    get_user_service,
    list_users_service,
    update_user_service,
)

CREATABLE_ROLES = (UserRole.LOCADOR, UserRole.CLIENTE)


def _check_role(role: UserRole | None) -> None:
    if role is not None and role not in CREATABLE_ROLES:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="O admin so cria usuarios locador ou cliente",
        )


async def create_user(session: Session, user: UserCreate) -> User:
    _check_role(user.role)
    return await create_user_service(session, user)


async def list_users(session: Session, current_user: User, tenant_id: int | None) -> list[User]:
    tenant_id = resolve_tenant_id(current_user, tenant_id)
    return await list_users_service(session, tenant_id)


async def get_user(session: Session, current_user: User, user_id: int) -> User:
    user = await get_user_service(session, user_id)
    check_tenant_access(current_user, user.tenant_id)
    return user


async def update_user(session: Session, user_id: int, user: UserUpdate) -> User:
    _check_role(user.role)
    return await update_user_service(session, user_id, user)


async def delete_user(session: Session, user_id: int) -> User:
    return await delete_user_service(session, user_id)
```

Nas rotas: `POST`, `PATCH` e `DELETE` com `current_user: AdminUser`; os dois `GET` com `current_user: StaffUser` repassando para o controller.

> **Cuidado com o admin no `check_tenant_access` do `get_user`:** o admin tem `tenant_id = None`. Como `check_tenant_access` libera o admin logo na primeira linha, o locador nunca consegue ver o admin (o `tenant_id` dele não bate), e o admin vê todo mundo. É o comportamento certo.

### Passo 6 — Booking (locador gerencia; cliente só consulta)

| Método | Rota                          | Quem pode                    |
|--------|-------------------------------|------------------------------|
| POST   | `/bookings/`                  | `StaffUser` + `check_tenant_access(data.tenant_id)` |
| GET    | `/bookings/`                  | `StaffUser` + `resolve_tenant_id` |
| GET    | `/bookings/availability`      | `StaffUser` + tenant do item |
| GET    | `/bookings/{id}`              | `StaffUser` + tenant da locação |
| PATCH  | `/bookings/{id}`              | `StaffUser` + tenant da locação |
| POST   | `/bookings/{id}/confirm`, `/cancel`, `/complete` | `StaffUser` + tenant da locação |
| **GET**| **`/bookings/me`**            | **`ClienteUser`** — só as locações dele |

O controller segue as mesmas três situações:

```python
# controller/booking.py  (trechos que mudam)
from controller.permissions import check_tenant_access, resolve_tenant_id
from models.user import User
from services.item import get_item_service


async def create_booking(session: Session, current_user: User, booking: BookingCreate) -> Booking:
    check_tenant_access(current_user, booking.tenant_id)
    return await create_booking_service(session, booking)


async def list_bookings(
    session: Session,
    current_user: User,
    tenant_id: int | None = None,
    item_id: int | None = None,
    user_id: int | None = None,
    booking_status: BookingStatus | None = None,
) -> list[Booking]:
    tenant_id = resolve_tenant_id(current_user, tenant_id)
    return await list_bookings_service(session, tenant_id, item_id, user_id, booking_status)


async def check_availability(
    session: Session, current_user: User, item_id: int, start_at: datetime, end_at: datetime
) -> AvailabilityRead:
    item = await get_item_service(session, item_id)
    check_tenant_access(current_user, item.tenant_id)
    available = await check_availability_service(session, item_id, start_at, end_at)
    return AvailabilityRead(item_id=item_id, start_at=start_at, end_at=end_at, available=available)


async def get_booking(session: Session, current_user: User, booking_id: int) -> Booking:
    booking = await get_booking_service(session, booking_id)
    check_tenant_access(current_user, booking.tenant_id)
    return booking


async def update_booking(
    session: Session, current_user: User, booking_id: int, booking: BookingUpdate
) -> Booking:
    await get_booking(session, current_user, booking_id)
    return await update_booking_service(session, booking_id, booking)


async def confirm_booking(session: Session, current_user: User, booking_id: int) -> Booking:
    await get_booking(session, current_user, booking_id)
    return await change_booking_status_service(session, booking_id, BookingStatus.CONFIRMED)

# cancel_booking e complete_booking: igual ao confirm, so muda o status
```

E nas rotas, todas com `current_user: StaffUser` repassando o usuário para o controller.

#### O endpoint do cliente: `GET /bookings/me`

O cliente não usa as rotas acima (todas dão `403` para ele). Ele tem uma rota só dele, que mostra **o item que alugou, a data de retirada e a data de devolução**.

**1. Schema** — acrescente em `schemas/booking.py`:

```python
class MyRentalRead(SQLModel):
    booking_id: int
    item_id: int
    item_name: str
    item_image_url: str | None
    data_retirada: datetime     # start_at
    data_devolucao: datetime    # end_at
    status: BookingStatus
    total_amount: Decimal | None
```

Este schema é uma **visão** pensada para o cliente: ele não precisa de `tenant_id` nem `user_id`, mas precisa do **nome do item**, que não está na tabela de bookings.

**2. Service** — acrescente em `services/booking.py`:

```python
async def list_my_rentals_service(session: Session, user_id: int) -> list[Booking]:
    statement = (
        select(Booking)
        .where(Booking.user_id == user_id)
        .order_by(col(Booking.start_at).desc())
    )
    return list(session.exec(statement).all())
```

**3. Controller** — acrescente em `controller/booking.py`:

```python
from schemas.booking import MyRentalRead


async def list_my_rentals(session: Session, current_user: User) -> list[MyRentalRead]:
    # o user_id vem do TOKEN, nunca da URL: o cliente nao tem como ver as de outra pessoa
    bookings = await list_my_rentals_service(session, current_user.id)
    return [
        MyRentalRead(
            booking_id=booking.id,
            item_id=booking.item_id,
            item_name=booking.item.name,            # relacionamento Booking -> Item
            item_image_url=booking.item.image_url,
            data_retirada=booking.start_at,
            data_devolucao=booking.end_at,
            status=booking.status,
            total_amount=booking.total_amount,
        )
        for booking in bookings
    ]
```

O `booking.item` funciona por causa do `Relationship` definido em [models/booking.py](models/booking.py): o SQLModel busca o item sozinho.

**4. Rota** — em `routes/booking.py`, **antes** de `/{booking_id}` (senão o FastAPI tenta ler `me` como um id):

```python
from controller.permissions import ClienteUser
from schemas.booking import MyRentalRead


@router.get("/me", response_model=list[MyRentalRead])
async def list_my_rentals_route(current_user: ClienteUser, session: Session = Depends(get_session)):
    return await list_my_rentals(session, current_user)
```

Exemplo de resposta para a Joana:

```json
[
  {
    "booking_id": 1,
    "item_id": 1,
    "item_name": "Furadeira Bosch",
    "item_image_url": null,
    "data_retirada": "2026-10-20T12:00:00Z",
    "data_devolucao": "2026-10-20T16:00:00Z",
    "status": "confirmed",
    "total_amount": "40.00"
  }
]
```

As datas voltam em UTC (`Z`); 12:00 UTC = 09:00 de Brasília. O front converte para o horário local na hora de mostrar.

### Passo 7 — Testar as permissões

Para trocar de usuário no `/docs`: **Authorize** → **Logout** → entre com o outro usuário.

Prepare os dados como **admin** (`admin`):

1. `POST /tenants/` → `{ "name": "Loca Tudo", "slug": "loca-tudo" }` (tenant 1)
2. `POST /tenants/` → `{ "name": "Outra Loja", "slug": "outra-loja" }` (tenant 2)
3. `POST /users/` → `dono` (locador, tenant 1), `joana` (cliente, tenant 1), `outro` (locador, tenant 2)

Depois, como **`dono`**, crie categoria, item e uma locação para a Joana (Parte 6, passos 3 a 5).

**Como admin**

| Teste                                                     | Esperado |
|-----------------------------------------------------------|----------|
| `POST /users/` com `"role": "admin"`                      | `403`    |
| `GET /categories/` sem `tenant_id`                        | `422` (admin precisa informar) |
| `GET /categories/?tenant_id=1`                            | `200`    |

**Como locador (`dono`)**

| Teste                                                     | Esperado |
|-----------------------------------------------------------|----------|
| `POST /tenants/`                                          | `403`    |
| `POST /users/`                                            | `403`    |
| `GET /users/`                                             | `200`, só os do tenant 1 |
| `POST /categories/` com `"tenant_id": 1`                  | `201`    |
| `POST /categories/` com `"tenant_id": 2`                  | `403`    |
| `GET /items/` sem `tenant_id`                             | `200`, só os do tenant 1 |
| `GET /bookings/?tenant_id=2`                              | `403`    |
| `GET /bookings/me`                                        | `403` (não é cliente) |

**Como outro locador (`outro`)**

| Teste                                   | Esperado |
|-----------------------------------------|----------|
| `GET /bookings/`                        | `200`, lista vazia |
| `GET /bookings/1`                       | `403`    |
| `POST /bookings/1/cancel`               | `403`    |
| `PATCH /items/1`                        | `403`    |

**Como cliente (`joana`)**

| Teste                                   | Esperado |
|-----------------------------------------|----------|
| `GET /bookings/me`                      | `200`, só as locações da Joana, com item, retirada e devolução |
| `GET /bookings/`                        | `403`    |
| `GET /bookings/1`                       | `403`    |
| `POST /bookings/`                       | `403`    |
| `GET /items/` ou `GET /categories/`     | `403`    |

**Sem login**

| Teste                         | Esperado |
|-------------------------------|----------|
| Qualquer rota (menos `/auth/login` e `/health-check/`) | `401` |
