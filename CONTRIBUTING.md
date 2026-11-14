# Contributing

External pull requests are **not accepted** at this stage of the project.
Issues, bug reports and discussions are welcome.

Rules that apply to all code in this repository:

- Chatwoot's `enterprise/` directory is never used, patched or shipped here.
- Features live in our own code (`custom/` overlay and our services). A change
  to a Chatwoot core file is accepted only as a small seam, recorded in the
  change's design and carried as a patch in `patches/`.
- A screen the overlay redraws is the overlay's own component, mounted in
  place of Chatwoot's and recorded in `patches/overlay-screens.txt`; Chatwoot's
  file is not rewritten in a patch.
