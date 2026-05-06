# Progress Pengerjaan — AiraNest (Web Mail Client IMAP)

## Struktur Repo (Monorepo)

```
airanest/                            # Satu repo git, beda folder per komponen
├── rancangan-mvp-webmail-imap.md    # Dokumen rancangan lengkap
├── PROGRESS.md                      # File ini
├── api/                             # Backend (API + Worker + Beat)
│   └── TAHAPAN.md                   # Detail 9 tahap pengerjaan API
└── ui/                              # Frontend (belum dibuat, ditunda)
```

## Status per Komponen

| Komponen | Status | Catatan |
|----------|--------|---------|
| API (backend) | **Tahap 1 selesai** | Project skeleton & Docker setup sudah jalan |
| UI (frontend) | **Ditunda** | Dikerjakan setelah API selesai |

## Keputusan yang Sudah Diambil

1. **Protokol diganti dari POP ke IMAP** — lebih reliable (UID-based sync, UIDVALIDITY)
2. **Fitur hapus di server** — per akun, opsional (`delete_from_server`), email tetap bisa dibaca dari lokal
3. **API dikerjakan duluan**, UI menyusul setelah API stabil
4. **Semua development dan testing menggunakan `docker-compose.yml`** yang ada di dalam subfolder `api/`
5. **Storage pakai local filesystem** — MinIO sudah archived/discontinued, pakai Docker volume saja untuk MVP
6. **Tahapan pengerjaan API terdiri dari 9 tahap** (detail di `api/TAHAPAN.md`):
   - Tahap 1: Project Skeleton & Docker Setup
   - Tahap 2: Database Models & Migrations
   - Tahap 3: Authentication
   - Tahap 4: Mail Account CRUD
   - Tahap 5: IMAP Fetch Worker (+ delete from server)
   - Tahap 6: Inbox & Message API
   - Tahap 7: Compose & Send (SMTP)
   - Tahap 8: Search & Sync Status
   - Tahap 9: Hardening & Testing

## Tahap Terakhir yang Dikerjakan

> **Tahap 1 — Project Skeleton & Docker Setup** ✔ selesai
>
> Selanjutnya: **Tahap 2 — Database Models & Migrations**
