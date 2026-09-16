-- List all tables in current schema
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public';

DROP TABLE IF EXISTS account_test;
CREATE TABLE account_test
(
    user_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(50) NOT NULL,
    email VARCHAR(355) UNIQUE NOT NULL,
    created_on TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO account_test (username, password, email, created_on, last_login)
VALUES ('john_doe', 'pass123', 'john@example.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO account_test (username, password, email, created_on, last_login)
VALUES ('jane_smith', 'secure456', 'jane@example.com', '2024-01-01 10:00:00 UTC', '2024-01-01 10:30:00 UTC');

INSERT INTO account_test (username, password, email, created_on)
VALUES ('new_user', 'welcome789', 'new@example.com', CURRENT_TIMESTAMP);

-- Batch insert
INSERT INTO account_test (username, password, email, created_on, last_login)
VALUES
    ('alice_wonder', 'alice123', 'alice@example.com', '2024-02-15 08:30:00 UTC', '2024-02-15 09:00:00 UTC'),
    ('bob_builder', 'bob456', 'bob@example.com', '2024-02-15 09:15:00 UTC', '2024-02-15 10:00:00 UTC');

SELECT * FROM account_test WHERE last_login IS NOT NULL;

SELECT
  username,
  email,
  created_on
FROM account_test ORDER BY created_on DESC;

SELECT COUNT(*) as active_users FROM account_test WHERE last_login >= CURRENT_TIMESTAMP - INTERVAL '1 day';

-- Update statements with timestamp handling
UPDATE account_test
SET last_login = CURRENT_TIMESTAMP
WHERE username = 'john_doe';

UPDATE account_test
SET password = 'newpass123',
    last_login = CURRENT_TIMESTAMP
WHERE email = 'jane@example.com';

-- Select to verify updates
SELECT username, last_login AT TIME ZONE 'UTC' as last_login_utc
FROM account_test
WHERE username IN ('john_doe', 'jane_smith')
ORDER BY last_login DESC;


SELECT
    schemaname,
    tablename,
    tableowner,
    has_table_privilege(current_user, tablename, 'SELECT') as can_select,
    has_table_privilege(current_user, tablename, 'INSERT') as can_insert,
    has_table_privilege(current_user, tablename, 'UPDATE') as can_update,
    has_table_privilege(current_user, tablename, 'DELETE') as can_delete
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename;

SELECT table_name
FROM information_schema.tables;

SELECT
    grantee,
    table_schema,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'account_test';

GRANT ALL PRIVILEGES ON account_test TO test_user;
