# Rancangan MVP — AiraNest: Web Mail Client Self-Hosted (Multi User, Multi IMAP)

## 1. Tujuan produk

Membangun web app email client yang terasa seperti Thunderbird versi web, dengan fokus ke kebutuhan inti berikut:

- Multi user
- Setiap user bisa menambahkan beberapa akun email IMAP
- Web-based
- API dan UI dipisahkan ke repo/source code berbeda
- Masing-masing service bisa dibuild menjadi Docker image
- Deployment akhir cukup dengan `docker compose`

## 2. Prinsip desain

Email yang diambil dari server IMAP di-**ingest** ke database internal, lalu ditampilkan dari sana. Dengan pendekatan ini:

- Email dibaca dari server IMAP secara berkala oleh background worker
- Setelah diambil, pesan disimpan lokal (database + object storage)
- UI tidak membaca langsung ke server IMAP
- Status seperti unread/read, starred, archived, dan draft dikelola oleh sistem sendiri
- User bisa memilih untuk **menghapus email di server** setelah diunduh, sehingga email tetap bisa dibaca dari storage lokal meskipun sudah tidak ada di server

## 3. Target MVP

### Fungsi minimal yang wajib ada
1. Authentication user
2. User management dasar
3. Add/remove multiple IMAP accounts per user
4. Fetch email otomatis dari tiap akun IMAP
5. Unified inbox per user
6. View message detail
7. Mark read/unread
8. Reply dan send email
9. Basic search
10. Attachment download
11. Opsi hapus email di server (tetap tersimpan lokal)

### Fungsi yang ditunda
- Threading lanjutan yang sempurna
- Rules/filter otomatis
- Label kompleks
- Full-text search canggih
- Calendar/contacts
- Push real-time inbox (IMAP IDLE)
- Offline support
- Mobile app
- Folder sync dua arah (saat ini hanya ingest INBOX)

## 4. Arsitektur tingkat tinggi

```text
[Browser]
   |
   | HTTPS
   v
[UI Repo / Frontend Container]
   |
   | REST API
   v
[API Repo / Backend Container] -----> [PostgreSQL]
   |                                  [Redis]
   |                                  [Object Storage]
   |
   +---- background jobs ----> IMAP/SMTP servers
```

### Komponen
- **UI**: aplikasi web untuk baca/kirim email
- **API**: auth, account management, message storage, search, send mail
- **Worker**: job polling IMAP, sync email, hapus di server, kirim email, cleanup
- **Database**: metadata user, akun, pesan, status, audit
- **Object storage**: attachment dan raw MIME
- **Redis**: queue / scheduler / cache

## 5. Rekomendasi stack

## API repo
- **Python + FastAPI**
- **Celery + Celery Beat**
- **Redis**
- **PostgreSQL**
- **SQLAlchemy + Alembic**
- **Pydantic**
- **Python standard library imaplib + smtplib**
- **Python email package** untuk parsing MIME
- **MinIO** atau storage lokal untuk attachment

### Alasan
- FastAPI cocok untuk API modern yang cepat dibangun
- Celery Beat cocok untuk job polling berkala
- Python punya dukungan bawaan untuk IMAP, SMTP, dan parsing email
- PostgreSQL cocok untuk penyimpanan relasional multi-user
- MinIO memudahkan nanti kalau mau pindah ke object storage S3-compatible

## UI repo
- **React**
- **Vite**
- **TypeScript**
- **Tailwind CSS**
- **shadcn/ui** atau komponen serupa
- **TanStack Query**
- **Zustand** atau React state biasa

### Alasan
- React cocok untuk komponen UI yang banyak
- Vite cepat untuk development
- TypeScript membantu menjaga kualitas saat proyek mulai besar
- UI email client butuh list, detail pane, composer, account switcher, inbox switcher

## 6. Batasan teknis yang penting

### IMAP sebagai sumber ingest
Walaupun IMAP mendukung sync dua arah, untuk MVP kita gunakan IMAP sebagai **read-only ingest**:
- Fetch email dari INBOX (dan folder lain jika dikonfigurasi)
- Simpan ke database lokal
- Opsional: hapus dari server setelah berhasil diunduh
- Tidak melakukan sync balik (flag read/unread tidak di-push ke server)

### Deduplication
Untuk mencegah email yang sama terunduh berulang:
- Simpan `Message-ID` header sebagai identifier utama
- Simpan UID per mailbox (IMAP UID lebih reliable dari POP UIDL)
- Gunakan UIDVALIDITY untuk mendeteksi reset mailbox
- Fallback ke hash dari (Message-ID + from + date + subject) jika UID berubah

### Hapus di server
Fitur opsional per akun:
- `delete_from_server`: boolean, default false
- Jika aktif, setelah email berhasil disimpan lokal, tandai `\Deleted` lalu EXPUNGE
- Email tetap bisa dibaca dari database lokal
- Memberikan user kontrol penuh atas storage di mail server mereka

### Attachment handling
- Simpan file attachment terpisah dari metadata
- Jangan simpan attachment besar langsung di row database
- Simpan pointer ke object storage atau filesystem lokal

### Send mail
Pengiriman email tetap pakai SMTP:
- SMTP credentials disimpan per akun
- Reply/compose dikirim lewat account yang dipilih user

## 7. Model data inti

### users
- id
- email
- password_hash / auth provider
- created_at
- updated_at

### mail_accounts
- id
- user_id
- display_name
- email_address
- imap_host
- imap_port
- imap_tls
- imap_username
- imap_password_encrypted
- smtp_host
- smtp_port
- smtp_tls
- smtp_username
- smtp_password_encrypted
- sync_interval_minutes
- last_sync_at
- last_uid
- uid_validity
- delete_from_server (boolean, default false)
- is_active

### messages
- id
- user_id
- mail_account_id
- imap_uid
- message_id_header
- from_addr
- to_addr
- cc_addr
- subject
- body_text
- body_html
- received_at
- sent_at
- is_read
- is_starred
- is_deleted_from_server
- raw_mime_path
- fingerprint

### attachments
- id
- message_id
- filename
- mime_type
- file_size
- storage_path

### sync_logs
- id
- mail_account_id
- started_at
- ended_at
- status
- messages_fetched
- messages_deleted_from_server
- error_message

## 8. Alur kerja utama

### A. Tambah akun email
1. User login
2. User input detail IMAP + SMTP
3. API validasi koneksi
4. Akun disimpan terenkripsi
5. User pilih opsi `delete_from_server` (default: off)
6. Worker mulai sync berkala

### B. Fetch email
1. Celery Beat menjadwalkan job
2. Worker ambil daftar akun aktif
3. Worker connect ke IMAP server
4. SELECT INBOX, cek UIDVALIDITY
5. FETCH pesan dengan UID > last_uid
6. Parse MIME
7. Simpan metadata + raw message + attachment
8. Update last_uid
9. Jika `delete_from_server` aktif: tandai \Deleted + EXPUNGE
10. Update inbox internal user
11. Catat ke sync_logs

### C. Unified inbox
1. UI request `/inbox`
2. API ambil semua pesan milik user dari semua akun aktif
3. Sort berdasarkan received time
4. Tampilkan sebagai satu inbox gabungan

### D. Reply / send
1. User klik reply
2. UI buka composer
3. API kirim via SMTP sesuai akun pengirim
4. Simpan salinan sent mail ke database

## 9. API contract minimal

### Auth
- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/logout`
- `GET /auth/me`

### Mail accounts
- `GET /mail-accounts`
- `POST /mail-accounts`
- `GET /mail-accounts/{id}`
- `PATCH /mail-accounts/{id}`
- `DELETE /mail-accounts/{id}`
- `POST /mail-accounts/{id}/test`

### Messages
- `GET /messages/inbox`
- `GET /messages/{id}`
- `PATCH /messages/{id}/read`
- `PATCH /messages/{id}/star`
- `DELETE /messages/{id}`
- `GET /messages/{id}/attachments/{attachment_id}`

### Compose
- `POST /compose/send`
- `POST /compose/draft`
- `GET /compose/drafts`

### Sync
- `POST /sync/run`  # admin/internal
- `GET /sync/status`

## 10. Repo split

### Repo 1 — api
Berisi:
- FastAPI app
- Celery worker
- database migrations
- IMAP/SMTP integration
- auth
- tests
- Dockerfile

### Repo 2 — ui
Berisi:
- React app
- pages/views
- API client
- auth flow
- message list/detail/compose
- Dockerfile

## 11. Container strategy

### API image
- Base image Python slim
- Install dependencies
- Run `uvicorn` untuk API
- Worker image bisa pakai image yang sama
- Beat image juga bisa pakai image yang sama

### UI image
- Build statik frontend
- Serve dengan Nginx atau Caddy
- UI hanya berbicara ke API lewat HTTPS

### Docker Hub
- Publish image misalnya:
  - `dockerhubuser/airanest-api:latest`
  - `dockerhubuser/airanest-worker:latest`
  - `dockerhubuser/airanest-ui:latest`

### Deploy akhir
Pengguna cukup menulis `docker-compose.yml` yang berisi:
- api
- worker
- beat
- postgres
- redis
- minio
- ui

## 12. Urutan pengerjaan MVP

### Sprint 1
- Auth
- User table
- Mail account CRUD
- Enkripsi credential
- Docker setup dasar

### Sprint 2
- IMAP fetch worker
- Deduplication (UID + Message-ID)
- Message storage
- Delete from server (opsional per akun)
- Unified inbox API

### Sprint 3
- UI inbox list
- Message detail
- Read/unread
- Basic compose and send via SMTP

### Sprint 4
- Attachment handling
- Search sederhana
- Sync logs
- Hardening dan testing

## 13. Risiko utama

1. **IMAP connection management**
   - Mitigasi: connection pooling, timeout handling, retry logic

2. **Duplicate message**
   - Mitigasi: IMAP UID + UIDVALIDITY + Message-ID header

3. **Credential security**
   - Mitigasi: encryption at rest + secret management

4. **Large mailbox performance**
   - Mitigasi: pagination, indexing, incremental sync via UID

5. **Gmail/provider quirks (OAuth, app passwords)**
   - Mitigasi: per-provider config preset dan test connection

6. **Hapus di server tapi gagal simpan lokal**
   - Mitigasi: hanya hapus setelah konfirmasi write berhasil (delete-after-commit)

## 14. Saran keputusan produk

Untuk MVP, fokus utama jangan terlalu luas.

Pilihan yang paling aman:
- login user
- multi IMAP account per user
- unified inbox
- baca email
- reply
- send
- attachment
- opsi hapus di server

Kalau ini sudah stabil, baru pikirkan:
- folder sync (selain INBOX)
- label
- rules
- threading yang lebih pintar
- search full text
- notifikasi real-time (IMAP IDLE)
- mobile responsive polish

## 15. Kesimpulan

Kalau tujuan akhirnya adalah "Thunderbird versi web" untuk workflow email self-hosted, rancangan yang paling masuk akal adalah:

- API terpisah
- UI terpisah
- IMAP diambil oleh background worker
- email disimpan lokal
- inbox ditampilkan dari database internal
- opsi hapus dari server untuk hemat storage
- deploy sederhana lewat Docker Compose
