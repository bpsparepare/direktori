# Panduan Import Data GeoJSON ke Supabase

## Persiapan

### 1. Jalankan Script Perbaikan Kolom (WAJIB)
Sebelum mengimpor data, jalankan script untuk memperbaiki panjang kolom:

```sql
-- Jalankan file ini terlebih dahulu
\i fix_id_sls_length.sql
```

**Mengapa perlu?**
- Kolom `id_sls` di tabel `wilayah` awalnya `VARCHAR(13)`, tapi data GeoJSON memiliki `id_sls` sepanjang 14 karakter
- Kolom `kd_sls` di tabel `wilayah` awalnya `CHAR(3)`, tapi data GeoJSON memiliki `kd_sls` sepanjang 4 digit
- Script ini akan mengubah `id_sls` ke `VARCHAR(15)` dan `kd_sls` ke `CHAR(4)`
- Script juga menangani dependency view `v_direktori_lengkap` secara otomatis

3. **File yang dibutuhkan**
   - `import_all_geojson_data.sql` (sudah dibuat otomatis)
   - Berisi 429 record unik dari file GeoJSON

## Cara Import ke Supabase

### Metode 1: Menggunakan Supabase SQL Editor (Direkomendasikan)

1. **Login ke Supabase Dashboard**
   - Buka https://supabase.com/dashboard
   - Login ke project Anda

2. **Buka SQL Editor**
   - Klik menu "SQL Editor" di sidebar kiri
   - Klik "New query" untuk membuat query baru

3. **Copy dan Paste Script SQL**
   - Buka file `import_all_geojson_data.sql`
   - Copy seluruh isi file
   - Paste ke SQL Editor

4. **Jalankan Script**
   - Klik tombol "Run" atau tekan Ctrl+Enter (Cmd+Enter di Mac)
   - Tunggu hingga proses selesai
   - Periksa hasil di bagian bawah editor

5. **Verifikasi Import**
   - Script akan otomatis menjalankan query verifikasi:
     ```sql
     SELECT COUNT(*) as total_records FROM wilayah;
     SELECT DISTINCT nm_prov FROM wilayah ORDER BY nm_prov;
     ```
   - Pastikan jumlah record sesuai (429 record)

### Metode 2: Menggunakan psql (Command Line)

Jika Anda memiliki akses psql dan connection string Supabase:

```bash
# Ganti dengan connection string Supabase Anda
psql "postgresql://postgres:[PASSWORD]@[HOST]:[PORT]/postgres" -f import_all_geojson_data.sql
```

### Metode 3: Upload File (Jika Ukuran File Kecil)

1. Di Supabase SQL Editor, klik "Upload SQL file"
2. Pilih file `import_all_geojson_data.sql`
3. Klik "Run" untuk menjalankan

## Struktur Data yang Diimport

Script akan mengimport data dengan mapping berikut:

| Field GeoJSON | Kolom Tabel | Contoh Data |
|---------------|-------------|-------------|
| `idsls` | `id_sls` | '73720110010009' |
| `kdprov` | `kd_prov` | '73' |
| `kdkab` | `kd_kab` | '72' |
| `kdkec` | `kd_kec` | '011' |
| `kddesa` | `kd_desa` | '001' |
| `kdsls` | `kd_sls` | '0009' |
| `nmprov` | `nm_prov` | 'SULAWESI SELATAN' |
| `nmkab` | `nm_kab` | 'PAREPARE' |
| `nmkec` | `nm_kec` | 'BACUKIKI BARAT' |
| `nmdesa` | `nm_desa` | 'LUMPUE' |
| `nmsls` | `nm_sls` | 'RT 002 RW 004' |

## Fitur Script

- **Upsert (ON CONFLICT)**: Jika data dengan `id_sls` yang sama sudah ada, akan diupdate
- **Escape Characters**: Single quotes dalam nama wilayah sudah di-escape
- **Unique Records**: Duplikat berdasarkan `id_sls` sudah dihilangkan
- **Verifikasi Otomatis**: Query verifikasi dijalankan setelah import

## Troubleshooting

### Error: relation "wilayah" does not exist
- **Solusi**: Jalankan `create_single_wilayah_table.sql` terlebih dahulu

### Error: duplicate key value violates unique constraint
- **Solusi**: Script sudah menggunakan `ON CONFLICT`, error ini seharusnya tidak terjadi
- Jika tetap terjadi, hapus data existing: `DELETE FROM wilayah;`

### Error: syntax error at or near
- **Solusi**: Pastikan copy-paste script lengkap dan tidak terpotong

### Import berhasil tapi data kosong
- **Solusi**: Periksa query verifikasi di akhir script
- Jalankan: `SELECT COUNT(*) FROM wilayah;`

## Setelah Import Berhasil

1. **Verifikasi Data**
   ```sql
   -- Cek total record
   SELECT COUNT(*) FROM wilayah;
   
   -- Cek distribusi per provinsi
   SELECT nm_prov, COUNT(*) FROM wilayah GROUP BY nm_prov;
   
   -- Cek sample data
   SELECT * FROM wilayah LIMIT 10;
   ```

2. **Test Query Aplikasi**
   - Test dropdown wilayah
   - Test pencarian berdasarkan kode wilayah
   - Test filter berdasarkan nama wilayah

## Informasi Tambahan

- **Total Records**: 429 record unik
- **Source**: final_sls.geojson (570 features, 429 unique)
- **Coverage**: Data SLS (Satuan Lingkungan Setempat) untuk berbagai wilayah
- **Generated**: Otomatis menggunakan script Python

Jika ada pertanyaan atau masalah, periksa log error di Supabase SQL Editor atau hubungi administrator database.