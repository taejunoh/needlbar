# Security policy

Needlbar handles provider-authenticated quota requests and reads local usage sources. Treat the repository and released artifacts as security-sensitive software even though Needlbar has no hosted service.

## Security boundaries

- Provider credentials stay in Rust-owned adapters and are not copied into Swift presentation models.
- The bridge exposes normalized usage, quota, and diagnostics envelopes. It must not expose tokens, cookies, account identifiers, raw paths, prompt/response text, or source-code content.
- HTTP/RPC clients use bounded responses and timeouts, allowlisted provider destinations, and redacted errors. Cursor session import is explicit and its input is cleared from the Settings form immediately after submission.
- Needlbar has no backend, account system, telemetry, cloud sync, or analytics pipeline.
- The pinned `tokscale-core` submodule is an input dependency for local usage parsing and aggregation; Needlbar-specific quota and authentication code remains outside it.

## Reporting a vulnerability

Please do not put credentials, cookies, session exports, prompts, responses, source code, or other private data in a public issue or pull request. Use the repository's private security reporting channel (GitHub Security Advisories when enabled) and include a minimal reproduction with synthetic data.

Security reports should describe the affected version or commit, macOS architecture, provider/subsystem boundary, impact, and a safe reproduction. Redact request headers and response bodies. If a report contains a secret, revoke or rotate it through the provider before sharing any further details.

In-scope examples include credential or cookie disclosure, unintended network destinations or uploads, diagnostics redaction failures, unsafe local path traversal, and bypasses of the explicit Cursor connection flow. General provider API changes should be reported as compatibility issues unless they create a security impact.
