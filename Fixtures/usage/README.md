# Usage fixtures

These fixture trees use documented Claude Code and Codex CLI session shapes. Every
content string, identifier, and project name is synthetic; the fixtures contain no
real prompts, paths, emails, credentials, or user data.

Each provider has exactly two usage events. The expected all-time aggregates are:

| Provider | Input | Output | Cache read | Cache write | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Claude | 1000 | 250 | 400 | 100 | 1750 |
| Codex | 800 | 200 | 300 | 0 | 1300 |
