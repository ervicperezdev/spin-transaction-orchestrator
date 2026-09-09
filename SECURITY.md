# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Report it
privately to the repository owner with a description, affected revision,
reproduction steps and potential impact. Avoid including real credentials or
transaction data.

The maintainer should acknowledge the report, assess severity and coordinate a
fix before public disclosure. Security fixes should receive a regression test
where practical and be released through the normal reviewed pull-request flow.

## Supported scope

This repository is an MVP/challenge implementation. Its default local database
credentials and unauthenticated API are not production-ready. See
`docs/security.md`, `docs/threat-model.md` and
`docs/limitations-roadmap-ai.md` for implemented controls, intended controls
and known gaps.

## Secure development expectations

- Never commit secrets, `.env` files, private keys or real transaction data.
- Use the supplied CI checks as review gates; investigate findings rather than
  silently suppressing them.
- Keep dependencies and action references reviewed and pinned as appropriate.
- Treat image signing, IaC and Kubernetes policies as controls that require
  deployed-environment verification, not as a substitute for it.
