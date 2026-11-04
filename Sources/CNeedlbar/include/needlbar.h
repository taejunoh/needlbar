#ifndef AISTATS_H
#define AISTATS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returned pointers are owned by Rust. Every non-null pointer must be released
// exactly once with needlbar_free_string. Callers must not mutate the bytes.
const char *needlbar_usage_snapshot_json(void);
const char *needlbar_quota_snapshot_json(void);
// Performs only Claude connection preflight without allowing Keychain UI.
// Ownership matches needlbar_quota_snapshot_json.
const char *needlbar_claude_preflight_quota_snapshot_json(void);
// Performs only Claude quota verification after an explicit user action.
// Ownership matches needlbar_quota_snapshot_json.
const char *needlbar_claude_user_initiated_quota_snapshot_json(void);
// Performs only non-interactive Codex quota verification. Ownership matches
// needlbar_quota_snapshot_json.
const char *needlbar_codex_quota_snapshot_json(void);
// Runs `/usage` through the user's installed claude. Blocks for at most about
// 31 seconds. Ownership matches needlbar_quota_snapshot_json. run_id is at
// least 1 and larger than any ID already passed to the cancel call.
const char *needlbar_claude_usage_report_quota_snapshot_json(uint64_t run_id);
// Cancels every run with an ID at most run_id, including one not yet started.
void needlbar_claude_usage_report_cancel_through(uint64_t run_id);
const char *needlbar_diagnostics_json(void);
const char *needlbar_analytics_snapshot_json(void);
void needlbar_free_string(const char *ptr);

#ifdef __cplusplus
}
#endif

#endif
