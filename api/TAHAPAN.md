# Tahapan Pengerjaan API — AiraNest (Web Mail Client IMAP)

## Gambaran Umum

Subfolder `api/` berisi seluruh backend: FastAPI app, Celery worker/beat, migrasi database, dan integrasi IMAP/SMTP. Semua service dijalankan dan ditest menggunakan `docker-compose.yml` yang ada di dalam subfolder ini.

---

## Tahap 1 — Project Skeleton & Docker Setup

**Tujuan:** Struktur project siap, bisa `docker compose up` dan semua service hidup.

- Inisialisasi project Python (pyproject.toml / requirements.txt)
- Buat struktur folder:
  ```
  api/
  ├── app/
  │   ├── __init__.py
  │   ├── main.py            # FastAPI entrypoint
  │   ├── config.py          # Settings / env vars
  │   ├── database.py        # SQLAlchemy engine & session
  │   ├── models/            # SQLAlchemy models
  │   ├── schemas/           # Pydantic schemas
  │   ├── routers/           # API routes
  │   ├── services/          # Business logic
  │   ├── workers/           # Celery tasks
  │   └── utils/             # Helpers (encryption, etc)
  ├── migrations/            # Alembic
  ├── tests/
  ├── Dockerfile
  ├── docker-compose.yml
  ├── alembic.ini
  └── requirements.txt
  ```
- Tulis `Dockerfile` (Python slim, uvicorn)
- Tulis `docker-compose.yml` dengan service:
  - `api` (FastAPI via uvicorn)
  - `worker` (Celery worker, image sama)
  - `beat` (Celery beat, image sama)
  - `postgres` (PostgreSQL 16)
  - `redis` (Redis 7)
  - `minio` (MinIO untuk object storage)
- Pastikan `docker compose up` berhasil tanpa error
- Health check endpoint `GET /health`

---

## Tahap 2 — Database Models & Migrations

**Tujuan:** Semua tabel inti sudah ada di PostgreSQL via Alembic.

- Setup Alembic dengan `alembic init`
- Buat SQLAlchemy models:
  - `users`
  - `mail_accounts` (termasuk field `delete_from_server`, `last_uid`, `uid_validity`)
  - `messages` (termasuk field `imap_uid`, `is_deleted_from_server`)
  - `attachments`
  - `sync_logs` (termasuk field `messages_deleted_from_server`)
- Generate initial migration
- Pastikan migration jalan otomatis saat container start
- Test: `docker compose up` → tabel terbuat di PostgreSQL

---

## Tahap 3 — Authentication

**Tujuan:** User bisa register, login, dan akses endpoint yang dilindungi.

- Implementasi auth dengan JWT (access + refresh token)
- Endpoints:
  - `POST /auth/register`
  - `POST /auth/login`
  - `POST /auth/logout`
  - `GET /auth/me`
- Password hashing (bcrypt)
- Dependency `get_current_user` untuk protected routes
- Test: register → login → akses `/auth/me` dengan token

---

## Tahap 4 — Mail Account CRUD

**Tujuan:** User bisa menambah, mengedit, dan menghapus akun email IMAP/SMTP.

- Enkripsi credential IMAP/SMTP (Fernet symmetric encryption)
- Endpoints:
  - `GET /mail-accounts`
  - `POST /mail-accounts` (termasuk field `delete_from_server`)
  - `GET /mail-accounts/{id}`
  - `PATCH /mail-accounts/{id}` (bisa toggle `delete_from_server`)
  - `DELETE /mail-accounts/{id}`
  - `POST /mail-accounts/{id}/test` (test koneksi IMAP & SMTP)
- Validasi: user hanya bisa akses akun miliknya sendiri
- Test: CRUD lengkap + test koneksi

---

## Tahap 5 — IMAP Fetch Worker

**Tujuan:** Email diambil otomatis dari server IMAP secara berkala, dengan opsi hapus di server.

- Celery task: `fetch_emails_for_account(account_id)`
- Celery Beat schedule: polling sesuai `sync_interval_minutes` per akun
- Logika fetch:
  1. Connect ke IMAP server (imaplib, TLS)
  2. SELECT INBOX
  3. Cek UIDVALIDITY — jika berubah, reset last_uid (mailbox direset)
  4. SEARCH UID > last_uid untuk dapat pesan baru
  5. FETCH pesan baru (BODY[], ENVELOPE, FLAGS)
  6. Parse MIME (email package Python)
  7. Cek deduplication (Message-ID header)
  8. Simpan metadata ke `messages`
  9. Simpan attachment ke MinIO + catat di `attachments`
  10. Simpan raw MIME ke MinIO
  11. Update `last_uid` dan `uid_validity`
  12. Jika `delete_from_server` aktif:
      - Tandai pesan dengan flag `\Deleted`
      - EXPUNGE
      - Set `is_deleted_from_server = true` pada record message
  13. Catat ke `sync_logs`
- Deduplication strategy:
  - Primary: IMAP UID + UIDVALIDITY
  - Secondary: Message-ID header
  - Fallback: hash dari (Message-ID + from + date + subject)
- Safety: hanya hapus dari server **setelah** write ke database berhasil (delete-after-commit)
- Test: mock IMAP server atau gunakan test account

---

## Tahap 6 — Inbox & Message API

**Tujuan:** UI bisa menampilkan inbox gabungan dan detail pesan.

- Endpoints:
  - `GET /messages/inbox` — unified inbox, paginated, sortable
  - `GET /messages/{id}` — detail pesan (body, headers)
  - `PATCH /messages/{id}/read` — mark read/unread
  - `PATCH /messages/{id}/star` — star/unstar
  - `DELETE /messages/{id}` — soft delete / archive
  - `GET /messages/{id}/attachments/{attachment_id}` — download file
- Query params untuk inbox: `page`, `per_page`, `account_id` (filter per akun), `is_read`
- Response include: sender, subject, preview, date, is_read, is_starred, has_attachments, is_deleted_from_server
- Email yang sudah dihapus dari server tetap muncul di inbox (baca dari lokal)
- Test: fetch dulu via worker, lalu query inbox

---

## Tahap 7 — Compose & Send (SMTP)

**Tujuan:** User bisa mengirim email dan reply.

- Endpoints:
  - `POST /compose/send` — kirim email langsung
  - `POST /compose/draft` — simpan draft
  - `GET /compose/drafts` — list draft
- Kirim via smtplib menggunakan credential SMTP akun yang dipilih
- Support: plain text + HTML body, multiple recipients (to, cc, bcc)
- Simpan salinan sent mail ke database
- Reply: set header In-Reply-To dan References
- Test: kirim email ke test account, verifikasi terkirim

---

## Tahap 8 — Search & Sync Status

**Tujuan:** Pencarian dasar dan monitoring sync.

- Endpoints:
  - `GET /messages/search?q=keyword` — search di subject, from, body_text
  - `POST /sync/run` — trigger manual sync untuk akun tertentu
  - `GET /sync/status` — status sync terakhir per akun (termasuk jumlah yg dihapus dari server)
- Search menggunakan PostgreSQL `ILIKE` atau `tsvector` sederhana
- Test: search keyword yang ada di email yang sudah di-fetch

---

## Tahap 9 — Hardening & Testing

**Tujuan:** API production-ready untuk diintegrasikan dengan UI.

- Rate limiting (slowapi atau middleware)
- Input validation menyeluruh
- Error handling konsisten (format error response)
- Logging terstruktur
- IMAP connection error handling (timeout, disconnect, retry)
- Unit tests untuk service layer
- Integration tests untuk endpoints (pytest + httpx)
- Test docker compose full stack: up → migrate → register → add account → fetch → read inbox → hapus dari server → masih bisa baca
- Dokumentasi API otomatis via Swagger UI (`/docs`)

---

## Catatan Teknis

### Environment Variables yang Dibutuhkan
- `DATABASE_URL`
- `REDIS_URL`
- `SECRET_KEY` (untuk JWT)
- `ENCRYPTION_KEY` (untuk credential IMAP/SMTP)
- `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`

### Menjalankan
```bash
cd api/
docker compose up --build
```

### Testing
```bash
docker compose exec api pytest
```

### Akses Swagger UI
```
http://localhost:8000/docs
```
