-- seed.sql
-- Popula o banco rent-all com dados de teste respeitando as FKs.
--
-- Ordem obrigatoria (quem e referenciado entra primeiro):
--   tenants -> users -> categories -> items -> bookings
--
-- Cada PK gerada e guardada numa variavel (@...) com LAST_INSERT_ID()
-- e reutilizada como FK nos INSERTs seguintes.
--
-- Senha de TODOS os usuarios: senha123
--
-- Atencao aos enums (formato que o SQLModel cria no MySQL):
--   tenants.status, items.status, bookings.status -> NOME em maiusculo ('ACTIVE', 'AVAILABLE', 'PENDING'...)
--   users.role                                     -> VALOR em minusculo ('admin', 'locador', 'cliente')
--
-- created_at / updated_at nao tem DEFAULT no banco, por isso vao preenchidos com NOW().

USE `rent-all`;

-- ---------------------------------------------------------
-- (Opcional) Para rodar o seed de novo, apague antes so os
-- dados dele, na ordem INVERSA das FKs:
-- ---------------------------------------------------------
-- SET @t1 = (SELECT id FROM tenants WHERE slug = 'festa-e-cia');
-- SET @t2 = (SELECT id FROM tenants WHERE slug = 'ferramentas-ja');
-- DELETE FROM bookings   WHERE tenant_id IN (@t1, @t2);
-- DELETE FROM items      WHERE tenant_id IN (@t1, @t2);
-- DELETE FROM categories WHERE tenant_id IN (@t1, @t2) AND parent_id IS NOT NULL;
-- DELETE FROM categories WHERE tenant_id IN (@t1, @t2);
-- DELETE FROM users      WHERE tenant_id IN (@t1, @t2);
-- DELETE FROM tenants    WHERE id IN (@t1, @t2);

START TRANSACTION;

SET @senha = 'pbkdf2_sha256$600000$UpzvEodf2dG/PcAFwy6pFw==$gw4ffGDpWC0du9gLJiIhMg2piT+G2RFqvJWLdNOHQPg=';

-- =========================================================
-- 1) TENANTS (nao tem FK)
-- =========================================================
INSERT INTO tenants (name, slug, domain, logo_url, currency, timezone, language,
                     min_rental_hours, max_rental_days, advance_booking_days, status,
                     created_at, updated_at)
VALUES ('Festa & Cia Locações', 'festa-e-cia', 'festaecia.com.br', NULL, 'BRL', 'America/Sao_Paulo', 'pt-BR',
        4, 7, 60, 'ACTIVE', NOW(), NOW());
SET @tenant_festa = LAST_INSERT_ID();

INSERT INTO tenants (name, slug, domain, logo_url, currency, timezone, language,
                     min_rental_hours, max_rental_days, advance_booking_days, status,
                     created_at, updated_at)
VALUES ('Ferramentas Já', 'ferramentas-ja', 'ferramentasja.com.br', NULL, 'BRL', 'America/Sao_Paulo', 'pt-BR',
        2, 30, 90, 'ACTIVE', NOW(), NOW());
SET @tenant_ferr = LAST_INSERT_ID();

-- =========================================================
-- 2) USERS (FK: tenant_id -> tenants.id)
-- =========================================================
INSERT INTO users (tenant_id, username, hashed_password, role, is_active, created_at, updated_at)
VALUES (@tenant_festa, 'festa_admin', @senha, 'admin', TRUE, NOW(), NOW());
SET @user_festa_admin = LAST_INSERT_ID();

INSERT INTO users (tenant_id, username, hashed_password, role, is_active, created_at, updated_at)
VALUES (@tenant_festa, 'festa_locador', @senha, 'locador', TRUE, NOW(), NOW());
SET @user_festa_locador = LAST_INSERT_ID();

INSERT INTO users (tenant_id, username, hashed_password, role, is_active, created_at, updated_at)
VALUES (@tenant_festa, 'festa_cliente', @senha, 'cliente', TRUE, NOW(), NOW());
SET @user_festa_cliente = LAST_INSERT_ID();

INSERT INTO users (tenant_id, username, hashed_password, role, is_active, created_at, updated_at)
VALUES (@tenant_ferr, 'ferr_admin', @senha, 'admin', TRUE, NOW(), NOW());
SET @user_ferr_admin = LAST_INSERT_ID();

INSERT INTO users (tenant_id, username, hashed_password, role, is_active, created_at, updated_at)
VALUES (@tenant_ferr, 'ferr_locador', @senha, 'locador', TRUE, NOW(), NOW());
SET @user_ferr_locador = LAST_INSERT_ID();

INSERT INTO users (tenant_id, username, hashed_password, role, is_active, created_at, updated_at)
VALUES (@tenant_ferr, 'ferr_cliente', @senha, 'cliente', TRUE, NOW(), NOW());
SET @user_ferr_cliente = LAST_INSERT_ID();

-- =========================================================
-- 3) CATEGORIES
--    FK: tenant_id -> tenants.id
--    FK: parent_id -> categories.id (auto-relacionamento:
--        a categoria "pai" precisa existir antes da "filha")
-- =========================================================
-- Tenant Festa & Cia
INSERT INTO categories (tenant_id, name, slug, description, parent_id, created_at, updated_at)
VALUES (@tenant_festa, 'Festas', 'festas', 'Tudo para festas e eventos', NULL, NOW(), NOW());
SET @cat_festas = LAST_INSERT_ID();

INSERT INTO categories (tenant_id, name, slug, description, parent_id, created_at, updated_at)
VALUES (@tenant_festa, 'Mesas e Cadeiras', 'mesas-e-cadeiras', 'Kits de mesas e cadeiras', @cat_festas, NOW(), NOW());
SET @cat_mesas = LAST_INSERT_ID();

INSERT INTO categories (tenant_id, name, slug, description, parent_id, created_at, updated_at)
VALUES (@tenant_festa, 'Som e Iluminação', 'som-e-iluminacao', 'Caixas de som e efeitos de luz', @cat_festas, NOW(), NOW());
SET @cat_som = LAST_INSERT_ID();

-- Tenant Ferramentas Já
INSERT INTO categories (tenant_id, name, slug, description, parent_id, created_at, updated_at)
VALUES (@tenant_ferr, 'Ferramentas', 'ferramentas', 'Ferramentas em geral', NULL, NOW(), NOW());
SET @cat_ferramentas = LAST_INSERT_ID();

INSERT INTO categories (tenant_id, name, slug, description, parent_id, created_at, updated_at)
VALUES (@tenant_ferr, 'Ferramentas Elétricas', 'ferramentas-eletricas', 'Furadeiras, serras e lixadeiras', @cat_ferramentas, NOW(), NOW());
SET @cat_eletricas = LAST_INSERT_ID();

INSERT INTO categories (tenant_id, name, slug, description, parent_id, created_at, updated_at)
VALUES (@tenant_ferr, 'Construção', 'construcao', 'Equipamentos para obra', @cat_ferramentas, NOW(), NOW());
SET @cat_construcao = LAST_INSERT_ID();

-- =========================================================
-- 4) ITEMS
--    FK: tenant_id   -> tenants.id
--    FK: category_id -> categories.id (do MESMO tenant)
--    FK: owner_id    -> users.id      (locador do MESMO tenant)
-- =========================================================
-- Tenant Festa & Cia
INSERT INTO items (tenant_id, category_id, owner_id, name, slug, description,
                   daily_price, hourly_price, image_url, status, is_active, created_at, updated_at)
VALUES (@tenant_festa, @cat_mesas, @user_festa_locador, 'Kit mesa + 10 cadeiras', 'kit-mesa-10-cadeiras',
        'Mesa redonda com 10 cadeiras plásticas', 80.00, NULL, NULL, 'AVAILABLE', TRUE, NOW(), NOW());
SET @item_kit_mesa = LAST_INSERT_ID();

INSERT INTO items (tenant_id, category_id, owner_id, name, slug, description,
                   daily_price, hourly_price, image_url, status, is_active, created_at, updated_at)
VALUES (@tenant_festa, @cat_som, @user_festa_locador, 'Caixa de som amplificada 500W', 'caixa-de-som-500w',
        'Caixa ativa com bluetooth e microfone', 150.00, 25.00, NULL, 'AVAILABLE', TRUE, NOW(), NOW());
SET @item_som = LAST_INSERT_ID();

INSERT INTO items (tenant_id, category_id, owner_id, name, slug, description,
                   daily_price, hourly_price, image_url, status, is_active, created_at, updated_at)
VALUES (@tenant_festa, @cat_som, @user_festa_locador, 'Globo de luz LED', 'globo-de-luz-led',
        'Globo giratório RGB', 60.00, 10.00, NULL, 'MAINTENANCE', TRUE, NOW(), NOW());
SET @item_globo = LAST_INSERT_ID();

-- Tenant Ferramentas Já
INSERT INTO items (tenant_id, category_id, owner_id, name, slug, description,
                   daily_price, hourly_price, image_url, status, is_active, created_at, updated_at)
VALUES (@tenant_ferr, @cat_eletricas, @user_ferr_locador, 'Furadeira de impacto', 'furadeira-de-impacto',
        'Furadeira 750W com maleta de brocas', 35.00, 8.00, NULL, 'AVAILABLE', TRUE, NOW(), NOW());
SET @item_furadeira = LAST_INSERT_ID();

INSERT INTO items (tenant_id, category_id, owner_id, name, slug, description,
                   daily_price, hourly_price, image_url, status, is_active, created_at, updated_at)
VALUES (@tenant_ferr, @cat_eletricas, @user_ferr_locador, 'Serra circular', 'serra-circular',
        'Serra circular 1400W', 45.00, 10.00, NULL, 'AVAILABLE', TRUE, NOW(), NOW());
SET @item_serra = LAST_INSERT_ID();

INSERT INTO items (tenant_id, category_id, owner_id, name, slug, description,
                   daily_price, hourly_price, image_url, status, is_active, created_at, updated_at)
VALUES (@tenant_ferr, @cat_construcao, @user_ferr_locador, 'Betoneira 400L', 'betoneira-400l',
        'Betoneira elétrica 400 litros', 120.00, NULL, NULL, 'AVAILABLE', TRUE, NOW(), NOW());
SET @item_betoneira = LAST_INSERT_ID();

-- =========================================================
-- 5) BOOKINGS
--    FK: tenant_id -> tenants.id
--    FK: item_id   -> items.id  (item do MESMO tenant)
--    FK: user_id   -> users.id  (cliente do MESMO tenant)
--    CHECK: end_at > start_at
-- =========================================================
INSERT INTO bookings (tenant_id, item_id, user_id, start_at, end_at, status, total_amount, notes, created_at, updated_at)
VALUES
  -- Festa & Cia
  (@tenant_festa, @item_kit_mesa,  @user_festa_cliente, '2026-09-12 09:00:00', '2026-09-14 09:00:00', 'COMPLETED', 160.00, 'Aniversário - devolvido sem avarias', NOW(), NOW()),
  (@tenant_festa, @item_kit_mesa,  @user_festa_cliente, '2026-10-24 10:00:00', '2026-10-25 10:00:00', 'CONFIRMED',  80.00, NULL, NOW(), NOW()),
  (@tenant_festa, @item_som,       @user_festa_cliente, '2026-10-24 18:00:00', '2026-10-24 23:00:00', 'PENDING',   125.00, 'Locação por hora (5h)', NOW(), NOW()),
  -- Ferramentas Já
  (@tenant_ferr,  @item_furadeira, @user_ferr_cliente,  '2026-10-20 08:00:00', '2026-10-22 08:00:00', 'CONFIRMED',  70.00, NULL, NOW(), NOW()),
  (@tenant_ferr,  @item_serra,     @user_ferr_cliente,  '2026-10-15 08:00:00', '2026-10-16 08:00:00', 'CANCELLED',  45.00, 'Cliente desistiu', NOW(), NOW()),
  (@tenant_ferr,  @item_betoneira, @user_ferr_cliente,  '2026-11-03 07:00:00', '2026-11-08 07:00:00', 'PENDING',   600.00, 'Obra residencial', NOW(), NOW());

COMMIT;

-- =========================================================
-- Conferencia: cada reserva com seus vinculos resolvidos
-- =========================================================
SELECT b.id         AS booking_id,
       t.slug       AS tenant,
       i.name       AS item,
       c.name       AS categoria,
       p.name       AS categoria_pai,
       dono.username AS locador,
       cli.username AS cliente,
       b.start_at, b.end_at, b.status, b.total_amount
FROM bookings b
JOIN tenants    t    ON t.id    = b.tenant_id
JOIN items      i    ON i.id    = b.item_id
JOIN users      cli  ON cli.id  = b.user_id
LEFT JOIN users      dono ON dono.id = i.owner_id
LEFT JOIN categories c    ON c.id    = i.category_id
LEFT JOIN categories p    ON p.id    = c.parent_id
ORDER BY t.slug, b.start_at;
