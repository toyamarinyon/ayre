# Prompt folder migration — 0.2.1

The default prompt directory changes from `~/Library/Application Support/PromptInsertProbe/Prompts` to `~/Library/Application Support/Ayre/Prompts`. The app, App Intents, and bundled CLI share this resolution; explicit CLI `--store` directories bypass it.

The first default-store access copies regular Markdown files, retaining the legacy originals and modification dates. Hidden staging files and atomic no-clobber publication prevent partially copied files or replacement of existing destination entries. Symlinks are not imported. A completion marker prevents later startup from resurrecting deliberately deleted prompts. The two folders are not synchronized after migration; quit older app versions and use the updated bundled CLI.

If copying or marker creation fails, the error is logged and the legacy folder remains the default when available. A later default-store access retries. No user files are deleted. Diagnostic logs retain the prototype path for now.

Validation: 31 core/integration tests passed locally, including exact Unicode/CRLF bytes, preservation of source files and dates, conflicting destination data, symlink exclusion, staging cleanup, repeated migration, deletion behavior, missing legacy directory, and failure/retry. Plugin helper end-to-end, compatibility and timeout tests passed. These tests use isolated temporary stores, not the user's prompts.
