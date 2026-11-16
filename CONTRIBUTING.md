# Contributing

External pull requests are **not accepted** at this stage of the project.
Issues, bug reports and discussions are welcome.

Rules that apply to all code in this repository:

- Chatwoot's `enterprise/` directory is never used, patched or shipped here.
- Features live in our own code (`custom/` overlay and our services).
  Chatwoot's files are not edited. Where one has to behave differently, our
  file stands in for it and is recorded in `custom/CHATWOOT_FILES`; a line or
  two inside a screen that stays Chatwoot's may be a patch in `patches/`,
  within `patches/LIMIT`. `docs/chatwoot-files.md` says which to choose.
