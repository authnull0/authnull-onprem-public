# tunnel.ps1 — Opens SSH tunnel to Azure VM postgres
# Usage: .\tunnel.ps1
# Keep this terminal open while developing

$VM_IP   = "your-azure-vm-ip"   # replace with actual IP
$VM_USER = "azureuser"           # replace with your SSH user

Write-Host "Opening SSH tunnel: localhost:5432 -> $VM_IP postgres" -ForegroundColor Cyan
Write-Host "Keep this terminal open. Ctrl+C to close tunnel." -ForegroundColor Yellow
Write-Host ""

ssh -L 5432:localhost:5432 "${VM_USER}@${VM_IP}" -N
