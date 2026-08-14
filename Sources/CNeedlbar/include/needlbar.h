#ifndef AISTATS_H
#define AISTATS_H

#ifdef __cplusplus
extern "C" {
#endif

// Returned pointers are owned by Rust. Every non-null pointer must be released
// exactly once with needlbar_free_string. Callers must not mutate the bytes.
const char *needlbar_usage_snapshot_json(void);
// Forces Cursor source hydration before collecting usage. Ownership matches
// needlbar_usage_snapshot_json and the returned pointer must be freed once.
const char *needlbar_forced_usage_snapshot_json(void);
const char *needlbar_quota_snapshot_json(void);
const char *needlbar_diagnostics_json(void);
// session_token must be null or a valid NUL-terminated UTF-8 string. The
// returned envelope never contains the token and must be freed as above.
const char *needlbar_cursor_import_session_json(const char *session_token);
void needlbar_free_string(const char *ptr);

#ifdef __cplusplus
}
#endif

#endif
