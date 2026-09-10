ALTER TABLE transactions RENAME COLUMN provider_reference TO provider_transaction_id;
ALTER TABLE transactions ADD COLUMN account_id VARCHAR(128) NOT NULL DEFAULT 'legacy-account';
ALTER TABLE transactions ADD COLUMN description VARCHAR(500);
ALTER TABLE transactions ADD COLUMN balance_after NUMERIC(19, 2);
ALTER TABLE transactions ADD COLUMN rejection_code VARCHAR(64);

ALTER TABLE transactions DROP CONSTRAINT transactions_terminal_payload_check;
ALTER TABLE transactions ADD CONSTRAINT transactions_terminal_payload_check CHECK (
    (status = 'PENDING' AND provider_transaction_id IS NULL AND balance_after IS NULL AND rejection_reason IS NULL)
    OR (status = 'APPROVED' AND provider_transaction_id IS NOT NULL AND balance_after IS NOT NULL AND rejection_reason IS NULL)
    OR (status = 'REJECTED' AND rejection_reason IS NOT NULL AND balance_after IS NULL)
);
