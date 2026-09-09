## CI supply-chain pinning

GitHub Actions are pinned to immutable, 40-character commit IDs. The nearby
comment retains the human-maintainable release tag.

| Dependency | Selected release | Verified immutable reference |
| --- | --- | --- |
| `actions/checkout` | `v4.2.2` | `11bd71901bbe5b1630ceea73d27597364c9af683` |
| `returntocorp/semgrep` | `1.99.0` | Deliberately fixed image tag (manifest verified) |

Verification was performed against the official upstreams:

```sh
git ls-remote --refs https://github.com/actions/checkout.git refs/tags/v4.2.2
docker manifest inspect returntocorp/semgrep:1.99.0
```

`semgrep --config=auto --error --quiet` runs without `continue-on-error`, and
the Quality Gate fails if Semgrep (or either peer security control) does not
return `success`. Dependabot retains its `github-actions` ecosystem entry so it
can propose future Action pin updates; Maven, GitHub Actions, and Docker updates
use a seven-day default cooldown.
