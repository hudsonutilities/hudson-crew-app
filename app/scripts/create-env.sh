#!/bin/bash
# Script to create .env.local from environment variables
# This is useful for CI/CD deployments where .env.local is gitignored

# Create .env.local file from environment variables
cat > .env.local << EOF
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY}
EOF

echo "Created .env.local file"
cat .env.local | sed 's/SECRET_KEY=.*/SECRET_KEY=***/' # Show content but hide secret
