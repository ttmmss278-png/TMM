# Default WGS reference genome

The WGS module uses `ToxoDB-68_TgondiiGT1_Genome.fasta` as its default reference genome.

The verified file metadata are stored in `reference_manifest.json`. The 63 MB FASTA itself is installed once through the WGS page and saved locally in this directory by BioSeq Engine. It is intentionally not committed to the GitHub Pages source, so website deployment does not repeatedly package or distribute the genome.

After installation, the WGS module automatically reuses the local reference and its BWA/samtools/bcftools index files. A user-selected reference file is validated against the recorded SHA-256 value before it replaces the local default.
