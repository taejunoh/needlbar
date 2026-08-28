#ifndef AISTATS_H
#define AISTATS_H

#ifdef __cplusplus
extern "C" {
#endif

// Returned pointers are owned by Rust. Every non-null pointer must be released
// exactly once with needlbar_free_string. Callers must not mutate the bytes.
const char *needlbar_usage_snapshot_json(void);
const char *needlbar_quota_snapshot_json(void);
// Performs only Claude quota verification after an explicit user action.
// Ownership matches needlbar_quota_snapshot_json.
const char *needlbar_claude_user_initiated_quota_snapshot_json(void);
// Performs only non-interactive Codex quota verification. Ownership matches
// needlbar_quota_snapshot_json.
const char *needlbar_codex_quota_snapshot_json(void);
const char *needlbar_diagnostics_json(void);
void needlbar_free_string(const char *ptr);

#ifdef __cplusplus
}
#endif

#endif
