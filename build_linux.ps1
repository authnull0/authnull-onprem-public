# Build the Linux binary locally, then docker compose build will package it
$env:GOOS        = "linux"
$env:GOARCH      = "amd64"
$env:CGO_ENABLED = "0"
$env:GOTOOLCHAIN = "auto"

Write-Host "Building Linux binary..." -ForegroundColor Cyan
go build -mod=vendor -o main ./cmd/authnull-service/

if ($LASTEXITCODE -eq 0) {
    Write-Host "Binary built: ./main" -ForegroundColor Green
    Write-Host "Now run: docker compose build --no-cache authnull-service && docker compose up -d authnull-service"
} else {
    Write-Host "Build failed" -ForegroundColor Red
}
