# Historical prompt migration verification — 0.2.1

This records verification of a migration implementation in version 0.2.1. That migration has since been removed and this file does not describe current behavior. Current Ayre versions use only `~/Library/Application Support/Ayre/Prompts`; they do not import prompts from another directory.

Historical evidence: 31 core/integration tests passed for the 0.2.1 migration implementation, including exact Unicode/CRLF bytes, source-file and modification-date preservation, conflicting destination data, symlink exclusion, staging cleanup, repeated migration, deletion behavior, a missing source directory, and failure/retry. Plugin helper end-to-end, compatibility, and timeout tests also passed. These results describe that earlier implementation only; they are not new test results for current storage behavior. Tests used isolated temporary stores, not user prompts.
