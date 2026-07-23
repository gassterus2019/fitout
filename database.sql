-- =====================================================================
-- Project Control Hub - MRT Jakarta Fit-Out  |  database.sql
-- Skema Supabase / PostgreSQL untuk integrasi LIVE dengan index.html.
-- =====================================================================
-- CARA PAKAI (sekali saja):
--   1) Supabase Dashboard -> SQL Editor -> New query -> tempel file ini -> Run.
--   2) Authentication -> Users -> "Add user": buat email + password login.
--   3) Project Settings -> API: salin "Project URL" dan "anon public" key
--      ke index.html (SUPABASE_URL & SUPABASE_ANON_KEY).
--   4) Buka aplikasi -> login. Data contoh ter-seed OTOMATIS dari aplikasi
--      pada login pertama (selama app_meta untuk PROJECT_KEY masih kosong).
--
-- ROLE:
--   Role disimpan di tabel app_users (kolom role): 'Project Management'
--   atau 'Admin'. User pertama yang login otomatis jadi Project Management;
--   berikutnya jadi Admin dan bisa diubah lewat menu Manajemen User.
--   Project Management : CRUD penuh seluruh fitur.
--   Admin              : hanya update dokumen, bukti pembayaran, status Kanban.
--   Catatan: pembatasan role diterapkan di antarmuka aplikasi. Bila perlu
--   penegakan di sisi server, perketat policy RLS di bawah per-tabel.
--
-- KEAMANAN:
--   - RLS aktif di semua tabel; kebijakan: user terautentikasi boleh
--     baca & tulis (cocok untuk satu tim internal, pendaftaran akun
--     dikontrol admin lewat Supabase Auth).
--   - anon key AMAN dipakai di klien (dilindungi RLS). JANGAN pernah
--     menaruh service_role key di index.html atau repo publik.
-- =====================================================================

create extension if not exists pgcrypto;

-- ============================ TABEL ==================================
-- Meta proyek (fee konsultan yang bisa diedit, dll)
create table if not exists app_meta (
  project_key text primary key,
  name        text,
  sub         text,
  status_date date,
  fee         numeric default 0,
  updated_at  timestamptz default now()
);

-- Aktivitas per KEGIATAN (konsultan | kontraktor | transisi)
-- Hirarki: parent_id NULL = Pekerjaan utama, terisi = Sub Pekerjaan.
create table if not exists app_tasks (
  id          text primary key,
  project_key text not null,
  pos         int  default 0,
  act         text not null,              -- 'konsultan' | 'kontraktor' | 'transisi'
  parent_id   text,                       -- NULL = pekerjaan utama
  name        text not null,
  start_date  date,
  finish_date date,
  percent     numeric default 0,
  status      text,                       -- 'Belum Mulai' | 'Berjalan' | 'Selesai' | 'Dibatalkan'
  note        text,                       -- catatan pekerjaan (dari Kanban)
  assignees   text[] default '{}',        -- daftar email user yang ditugaskan
  updated_at  timestamptz default now()
);
create index if not exists idx_tasks_pk     on app_tasks(project_key, pos);
create index if not exists idx_tasks_act    on app_tasks(project_key, act);
create index if not exists idx_tasks_parent on app_tasks(parent_id);

-- Biaya Kontraktor (RAB) + bukti pembayaran PDF per item
create table if not exists app_rab (
  id          text primary key,
  project_key text not null,
  pos         int  default 0,
  item        text not null,
  qty         numeric default 0,
  rate        numeric default 0,
  start_date  date,
  finish_date date,
  proof_url   text,                       -- bukti pembayaran (PDF di Storage)
  proof_name  text,
  updated_at  timestamptz default now()
);
create index if not exists idx_rab_pk on app_rab(project_key, pos);

-- Biaya Transisi + bukti pembayaran PDF per item
create table if not exists app_trans (
  id          text primary key,
  project_key text not null,
  pos         int  default 0,
  item        text not null,
  qty         numeric default 0,
  rate        numeric default 0,
  start_date  date,
  finish_date date,
  proof_url   text,
  proof_name  text,
  updated_at  timestamptz default now()
);
create index if not exists idx_trans_pk on app_trans(project_key, pos);

-- Termin Konsultan + bukti pembayaran PDF per termin
create table if not exists app_terms (
  id          text primary key,
  project_key text not null,
  pos         int  default 0,
  term        text,
  descr       text,
  percent     numeric default 0,
  pay_date    date,
  proof_url   text,
  proof_name  text,
  updated_at  timestamptz default now()
);
create index if not exists idx_terms_pk on app_terms(project_key, pos);

-- Arsip dokumen (file di Supabase Storage; url = public URL)
create table if not exists app_docs (
  id          text primary key,
  project_key text not null,
  pos         int  default 0,
  name        text not null,
  file_name   text,
  category    text,
  size_bytes  bigint default 0,
  doc_date    date,
  url         text,
  is_example  boolean default false,
  updated_at  timestamptz default now()
);
create index if not exists idx_docs_pk on app_docs(project_key, pos);

-- Punchlist (temuan)
create table if not exists app_punch (
  id          text primary key,
  project_key text not null,
  pos         int  default 0,
  title       text not null,
  stage       text,
  loc         text,                       -- lokasi temuan (tampil di laporan PDF)
  severity    text,
  status      text,
  due_date    date,
  note        text,
  photo_url   text,                       -- foto temuan di Storage
  updated_at  timestamptz default now()
);
create index if not exists idx_punch_pk on app_punch(project_key, pos);

-- Daftar user & role aplikasi (dikelola dari menu Manajemen User)
-- Catatan: akun login (email+password) tetap dibuat di Supabase Auth;
-- email di sini harus sama dengan email akun Auth-nya.
create table if not exists app_users (
  id          text primary key,
  project_key text not null,
  pos         int  default 0,
  name        text not null,
  email       text not null,
  role        text default 'Admin',       -- 'Project Management' | 'Admin'
  active      boolean default true,
  updated_at  timestamptz default now()
);
create index if not exists idx_users_pk on app_users(project_key, pos);
create index if not exists idx_users_em on app_users(project_key, email);

-- Task management pribadi tiap user (checklist ala OneNote)
create table if not exists app_mytasks (
  id          text primary key,
  project_key text not null,
  pos         int  default 0,
  owner       text not null,              -- email pemilik tugas
  text        text not null,
  done        boolean default false,
  updated_at  timestamptz default now()
);
create index if not exists idx_my_pk    on app_mytasks(project_key, pos);
create index if not exists idx_my_owner on app_mytasks(project_key, owner);

-- Log aktivitas
create table if not exists app_logs (
  id          text primary key,
  project_key text not null,
  pos         int  default 0,
  ts          timestamptz default now(),
  actor       text,
  action      text,
  detail      text
);
create index if not exists idx_logs_pk on app_logs(project_key, pos);
create index if not exists idx_logs_ts on app_logs(project_key, ts desc);

-- ---- MIGRASI (aman dijalankan ulang bila tabel sudah ada sebelumnya) ----
alter table app_tasks add column if not exists note      text;
alter table app_tasks add column if not exists assignees text[] default '{}';
alter table app_rab   add column if not exists proof_url  text;
alter table app_rab   add column if not exists proof_name text;
alter table app_terms add column if not exists proof_url  text;
alter table app_terms add column if not exists proof_name text;

-- ============================= RLS ==================================
alter table app_meta    enable row level security;
alter table app_tasks   enable row level security;
alter table app_rab     enable row level security;
alter table app_trans   enable row level security;
alter table app_terms   enable row level security;
alter table app_docs    enable row level security;
alter table app_punch   enable row level security;
alter table app_users   enable row level security;
alter table app_mytasks enable row level security;
alter table app_logs    enable row level security;

do $$
declare t text;
begin
  foreach t in array array['app_meta','app_tasks','app_rab','app_trans','app_terms',
                           'app_docs','app_punch','app_users','app_mytasks','app_logs'] loop
    execute format('drop policy if exists "auth_all" on %I;', t);
    execute format('create policy "auth_all" on %I for all to authenticated using (true) with check (true);', t);
  end loop;
end $$;

-- ============ STORAGE (foto temuan, dokumen & bukti bayar) ==========
-- Bucket publik: file bisa dibaca lewat public URL; tulis/hapus butuh login.
insert into storage.buckets (id, name, public)
values ('project-files','project-files', true)
on conflict (id) do update set public = true;

drop policy if exists "pf_read"   on storage.objects;
drop policy if exists "pf_write"  on storage.objects;
drop policy if exists "pf_update" on storage.objects;
drop policy if exists "pf_delete" on storage.objects;
create policy "pf_read"   on storage.objects for select using (bucket_id = 'project-files');
create policy "pf_write"  on storage.objects for insert to authenticated with check (bucket_id = 'project-files');
create policy "pf_update" on storage.objects for update to authenticated using (bucket_id = 'project-files');
create policy "pf_delete" on storage.objects for delete to authenticated using (bucket_id = 'project-files');

-- =====================================================================
-- Selesai. Tidak perlu seed manual: aplikasi mengisi data contoh otomatis
-- saat login pertama. Untuk mereset, kosongkan app_meta (dan tabel app_*
-- lain) untuk PROJECT_KEY terkait, lalu login lagi.
-- =====================================================================
