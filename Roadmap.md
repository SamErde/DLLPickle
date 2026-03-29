# Roadmap

This roadmap focuses on upcoming work. For released and in-progress engineering
details, see [CHANGELOG.md](CHANGELOG.md).

## Active Work (Near Term)

- Continue migration from legacy PlatyPS help generation to
  `Microsoft.PowerShell.PlatyPS` workflow.
- Keep compatibility and reliability improvements for mixed PowerShell editions
  (PowerShell 7+ and Windows PowerShell 5.1).
- Continue dependency lifecycle and supply chain hardening work.

## Planned Enhancements

- Add functions:
  - import a specific version of MSAL.
  - verify package hash/signature against original source metadata.
- Add option to preload other common assemblies
- Add an option to inspect and preload the newest version of relevant
  assemblies only from those already included with installed modules on the
  current system.
- Add function to import specific sets of assemblies.
- Add function to clean up older DLLPickle module versions.
- List all installed modules that include the MSAL

## Notes

- Items are not guaranteed in order.
- Large dependency or platform shifts may change implementation priority.
