# Security and Privacy

Report security issues privately to the repository owner before opening a public issue.

PetDesk stores the selected avatar under its Application Support directory and settings in `UserDefaults`. Diagnostics are memory-only and omit filenames, file paths, notification contents, and contact data.

The application is intentionally non-sandboxed for personal/GitHub distribution. Hardened Runtime remains enabled. Accessibility permission is optional and requested only when the user explicitly enables notification pulses. If source-app-only detection cannot be maintained, the integration remains disabled.

Forbidden implementations include screen OCR, reading private notification or chat databases, private frameworks, exact SMC temperature access, and retaining raw Accessibility text.
