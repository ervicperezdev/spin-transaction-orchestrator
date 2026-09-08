ALTER TABLE transactions
    ADD COLUMN idempotency_key VARCHAR(255);

-- Partial unique index: enforces uniqueness only for non-null keys, allowing
-- multiple rows with a NULL idempotency_key (transactions submitted without one).
CREATE UNIQUE INDEX transactions_idempotency_key_idx ON transactions (idempotency_key) WHERE idempotency_key IS NOT NULL;

COMMENT ON COLUMN transactions.idempotency_key IS
    'Client-supplied key used to deduplicate retried requests. NULL means no idempotency guarantee was requested.';
COMMENT ON INDEX transactions_idempotency_key_idx IS
    'Partial unique index on idempotency_key; NULLs are excluded so only keyed requests are deduplicated.';
