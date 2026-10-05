# Wine for macOS (CrossOver source)

Build scripts for a self-contained Wine engine for macOS, for running Windows games and apps.

The engine is **CrossOver's open-source Wine**, built from the source CodeWeavers publishes at
<https://media.codeweavers.com/pub/crossover/source/>, packaged so it runs on any Mac without Homebrew.
GitHub Actions builds it on an Intel Mac runner and publishes it under **Releases**.

| | |
|---|---|
| Wine | 11.0 (CrossOver 26.3.0 source) |
| Architecture | x86_64 with new WoW64 (runs 32- and 64-bit Windows programs; Apple Silicon via Rosetta 2) |
| Included | Wine Mono, Wine Gecko, FreeType, GnuTLS, MoltenVK |
| Not included | Apple's D3DMetal. It is Apple software under Apple's license and must come from the user's own Game Porting Toolkit. |

## Patches

Applied on top of CodeWeavers' source by `scripts/build.sh`, from `patches/`:

| Patch | Fixes |
|---|---|
| `0001-ntdll-macos-sigsys-restore-teb` | Games that make Windows system calls directly (e.g. Forza Horizon 6's copy protection) crashed on macOS: the SIGSYS handler resumed Windows code without switching GSBASE back to the TEB, so the syscall dispatcher read a NULL TEB. |

## Build

On GitHub: **Actions → Build engine → Run workflow**.

Locally on an Intel Mac (or under Rosetta, `arch -x86_64`):

```bash
brew install bison mingw-w64 freetype gnutls molten-vk pkgconf
scripts/build.sh 26.3.0
scripts/smoke-test.sh work/wine
```

The package lands in `dist/`.

## Licenses

- Wine is licensed under the GNU LGPL 2.1 or later. Each release includes the exact CrossOver source archive it was built from.
- Bundled libraries keep their own licenses: FreeType (FTL), GnuTLS, Nettle, GMP, libtasn1, libidn2, libunistring and gettext (LGPL), p11-kit (BSD), MoltenVK (Apache 2.0), Wine Mono (MIT and others), Wine Gecko (MPL 2.0).
- The scripts in this repository are MIT licensed (see `LICENSE`).

This project is not affiliated with CodeWeavers, Apple, Microsoft or the Wine project. CrossOver is a trademark of CodeWeavers, Inc.
