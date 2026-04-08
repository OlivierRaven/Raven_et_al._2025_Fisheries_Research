# post-render.ps1
# Run after quarto render to ensure all output files are in docs/

Write-Host "Running post-render cleanup..." -ForegroundColor Green

# Create docs if it doesn't exist
if (-not (Test-Path "docs")) {
    New-Item -ItemType Directory -Path "docs"
}

# Move any .html files from root to docs
Get-ChildItem -Path "." -Filter "*.html" -File | ForEach-Object {
    Move-Item $_.FullName "docs/$($_.Name)" -Force
    Write-Host "Moved $($_.Name) to docs/"
}

# Move embed notebooks to docs
Get-ChildItem -Path "." -Filter "*.embed.ipynb" -File | ForEach-Object {
    Move-Item $_.FullName "docs/$($_.Name)" -Force
    Write-Host "Moved $($_.Name) to docs/"
}

# Move index_files folder if it ended up in root
if (Test-Path "index_files") {
    if (Test-Path "docs/index_files") {
        Remove-Item "docs/index_files" -Recurse -Force
    }
    Move-Item "index_files" "docs/index_files" -Force
    Write-Host "Moved index_files to docs/"
}

Write-Host "Done!" -ForegroundColor Green