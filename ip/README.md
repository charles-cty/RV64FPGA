# Vivado IP inputs

Only three XCI customizations and the MIG `mig.prj` are versioned. Generated
HDL, checkpoints, caches and simulation products remain local and ignored.
The synthesis script calls `read_ip` / `generate_target all` with Vivado 2026.1.

MIG XCI references `../../mig_0.prj`. `synth-rv64-mig-project.ps1` stages the
external board configuration at precisely that path and checks SHA-256
`baed6883dac282367f835cd71dd312d307bd0efbc786cf6f4a2a5a0909c4e23c`.
Supply `-BoardConfig`; see `docs/project/local-dependencies.md`.

The tracked XCI files are those used by the 2026-09-30 successful bitstream;
`verification/linux-userspace-pass-20260930.json` checks their exact bytes.
