# AiraNest

Web-based email client self-hosted dengan dukungan multi user dan multi akun IMAP.

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Git

### Clone & Run

```bash
git clone https://github.com/nimdasx/airanest.git
cd airanest/api

# Copy environment file
cp .env.example .env

# Build dan jalankan semua service
docker compose up --build -d
```

### Verifikasi

Pastikan semua service berjalan:

```bash
docker compose ps
```

Harus ada 5 container running: `api`, `worker`, `beat`, `postgres`, `redis`.

Database migration otomatis dijalankan saat container `api` start — tidak perlu manual.

Test health check:

```bash
curl http://localhost:8000/health
```

Response: `{"status":"ok","app":"AiraNest API"}`

### Test Script

Jalankan test otomatis untuk memastikan semua service berjalan:

```bash
./test_tahap1.sh
```

### Stop

```bash
docker compose down
```

## Dokumentasi

- [Rancangan MVP](rancangan-mvp-webmail-imap.md)
- [Progress](PROGRESS.md)
- [Tahapan API](api/TAHAPAN.md)
