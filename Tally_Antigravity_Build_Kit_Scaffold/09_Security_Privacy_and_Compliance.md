# Security, Privacy, and Compliance

## Non-Negotiables
- No Tally-hosted persistence of Canvas data
- Keychain for auth tokens
- Encrypted local cache
- Explicit consent for optional Microsoft/Google integrations
- Clear privacy controls and cache purge

## Recommended Files
- `PRIVACY.md`
- `SECURITY.md`
- data retention section in Settings

## Security Controls
- PKCE for OAuth
- certificate pinning evaluation if justified
- secure defaults for caching and logging
- least-privilege integration scopes
- dependency scanning in CI
- secret scanning in repo
