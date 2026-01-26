# Deployment Guide

## Environment Variables Setup

This app requires MinIO access keys to be configured. The `.env.local` file is gitignored for security, so you need to set up environment variables in your deployment platform.

### Required Environment Variables

- `MINIO_ACCESS_KEY` - MinIO access key
- `MINIO_SECRET_KEY` - MinIO secret key

### For Cloudflare Pages

1. Go to your Cloudflare Pages project settings
2. Navigate to **Settings** > **Environment Variables**
3. Add the following environment variables:
   - `MINIO_ACCESS_KEY` = (your access key)
   - `MINIO_SECRET_KEY` = (your secret key)

4. Update your build command to generate `.env.local` before building:

   **For Linux/Mac builds:**
   ```bash
   bash scripts/create-env.sh && flutter build web
   ```

   **For Windows builds:**
   ```powershell
   powershell -File scripts/create-env.ps1 && flutter build web
   ```

### Alternative: Using --dart-define

You can also pass the values directly during build:

```bash
flutter build web \
  --dart-define=MINIO_ACCESS_KEY=your_access_key \
  --dart-define=MINIO_SECRET_KEY=your_secret_key
```

### Local Development

For local development, create a `.env.local` file in the root directory:

```
MINIO_ACCESS_KEY=your_access_key
MINIO_SECRET_KEY=your_secret_key
```

The app will automatically load this file when running locally.
