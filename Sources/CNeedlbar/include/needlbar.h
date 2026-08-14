#ifndef AISTATS_H
#define AISTATS_H

#ifdef __cplusplus
extern "C" {
#endif

// Returned pointers are owned by Rust. Every non-null pointer must be released
// exactly once with needlbar_free_string. Callers must not mutate the bytes.
const char *needlbar_usage_snapshot_json(void);
const char *needlbar_quota_snapshot_json(void);
const char *needlbar_diagnostics_json(void);
void needlbar_free_string(const char *ptr);

#ifdef __cplusplus
}
#endif

#endif
