# Shared scripts

Cross-platform or repository-wide scripts live here and are owned jointly. Machine-specific automation belongs under its owning `platform/` directory.

Run the public-content checker before committing from Windows:

```powershell
./scripts/Test-PublicRepository.ps1
```

The checker detects common accidental disclosures and prohibited binary artifacts. It does not prove that content is safe; staged changes still require human review.
