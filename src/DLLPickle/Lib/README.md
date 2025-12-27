# DLL Pickle Libraries

Libraries (DLLs) tracked and updated by DLL Pickle are maintained in this
directory.

These DLLs typically include Microsoft Identity libraries, authentication-related
components, and supporting assemblies required by the DLLPickle PowerShell
module.

- The list of managed packages and versions is defined in `Packages.json` in
  this directory.
- DLLPickle uses this manifest to download, track, and update the DLLs as
  needed.
- When the DLLPickle module is imported, these libraries are automatically
  loaded and made available to cmdlets that depend on them; you normally do
  not need to reference them directly.
