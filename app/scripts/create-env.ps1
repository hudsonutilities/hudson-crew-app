# PowerShell script to create .env.local from environment variables
# This is useful for CI/CD deployments where .env.local is gitignored

$accessKey = $env:MINIO_ACCESS_KEY
$secretKey = $env:MINIO_SECRET_KEY

if ([string]::IsNullOrEmpty($accessKey) -or [string]::IsNullOrEmpty($secretKey)) {
    Write-Error "MINIO_ACCESS_KEY and MINIO_SECRET_KEY environment variables must be set"
    exit 1
}

# Create .env.local file
@"
MINIO_ACCESS_KEY=$accessKey
MINIO_SECRET_KEY=$secretKey
"@ | Out-File -FilePath .env.local -Encoding utf8

Write-Host "Created .env.local file"
Write-Host "MINIO_ACCESS_KEY=$accessKey"
Write-Host "MINIO_SECRET_KEY=***"
