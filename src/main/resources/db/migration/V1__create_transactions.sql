CREATE TABLE transactions (
    id UUID PRIMARY KEY,
    type VARCHAR(16) NOT NULL,
    status VARCHAR(16) NOT NULL,
    amount NUMERIC(19, 2) NOT NULL,
    currency CHAR(3) NOT NULL,
    provider_reference VARCHAR(255),
    rejection_reason VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT transactions_type_check CHECK (type IN ('DEBIT', 'CREDIT')),
    CONSTRAINT transactions_status_check CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    CONSTRAINT transactions_terminal_payload_check CHECK (
        (status = 'PENDING' AND provider_reference IS NULL AND rejection_reason IS NULL)
        OR (status = 'APPROVED' AND provider_reference IS NOT NULL AND rejection_reason IS NULL)
        OR (status = 'REJECTED' AND provider_reference IS NULL AND rejection_reason IS NOT NULL)
    )
);

-- Supports the default transaction history read: newest records first, with id as a stable tie-breaker.
CREATE INDEX transactions_created_at_desc_idx ON transactions (created_at DESC, id DESC);

-- Supports filtering by status/type while retaining the same ordered read path.
CREATE INDEX transactions_status_type_created_at_desc_idx ON transactions (status, type, created_at DESC, id DESC);

COMMENT ON INDEX transactions_created_at_desc_idx IS
    'Newest-first transaction history ordering, with a stable UUID tie-breaker.';
COMMENT ON INDEX transactions_status_type_created_at_desc_idx IS
    'Status/type filtered transaction history ordered newest first.';
