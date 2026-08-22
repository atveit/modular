# Mojo on iOS evidence reports

This directory contains independent scrutiny reports and repository-local
evidence used to keep the [Mojo on iOS roadmap](../../MojoOniOSPlan.md)
honest and reproducible.

- [Claude scrutiny report](Mojo4iOSScrutinyCla.md)
- [Gemini scrutiny report](Mojo4iOSScrutinyGem.md)
- [Simulator evidence screenshot](mojo-ios-simulator.png)

The reports are historical snapshots, not a claim that all iOS support is
complete. When reproducing a result, record the exact Mojo compiler path and
version, target triple, SDK, command, and artifact checks (`file`, `vtool`,
`nm`, `ar`, and `otool`). In particular, distinguish:

1. target-object emission;
2. archive and Apple-link success;
3. signed Simulator installation and launch;
4. development-signed physical-device installation and launch; and
5. runtime, standard-library, framework, and performance coverage.

The screenshot is copied into the repository so the reports do not depend on
an author-specific home-directory path.
