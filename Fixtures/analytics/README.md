# Synthetic local analytics acceptance fixture

These files contain synthetic, non-user data for the v0.2.2 local repository
analytics acceptance test. The workspace names, repository root, commit OIDs,
session IDs, model labels, authors, and canaries are invented and do not refer
to a real checkout, provider account, source file, credential, or remote.

`workspace-session-fixture.json` describes a fixed UTC capture and report
fragments. It covers an observed repository workspace, missing and
non-repository workspaces, provider/model totals, active-session timing,
Task-1 overflow and partial counters, and privacy canaries.

`git-log-fixture.nul` is intentionally committed as text containing the two
characters `\\` and `0` wherever the subprocess fixture needs a NUL byte. The
acceptance test decodes those `\0` escapes in memory before handing bytes to a
fake `GitRunner`; no real Git process, repository, remote, network, credential,
or authentication is used.

The log includes an inclusive four-hour boundary, an earliest/full-OID tie,
one unambiguous local `(#42)` marker, and multiple invalid marker candidates.
The invalid-marker subject deliberately carries synthetic remote URL, branch,
author/email, prompt, response, source, credential, account, and stdout
canaries. The first fake discovery result carries the stderr canary. These are
actual raw fake Git inputs, not merely labels in the canary list; only the
sanitized short ID and PR number can reach the serialized payload.
