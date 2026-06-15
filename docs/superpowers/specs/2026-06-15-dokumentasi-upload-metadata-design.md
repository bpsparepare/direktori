# Dokumentasi Upload Metadata Design

## Ringkasan

Halaman dokumentasi tetap mengunggah gambar ke Google Drive, lalu menyimpan metadata sederhana ke tabel Supabase `documentation_uploads`. Fokus revisi UI adalah membuat halaman utama lebih bersih dengan memindahkan proses upload ke dialog tengah yang dibuka dari tombol FAB `+`.

Form upload tetap memiliki:

- pilihan kategori berbasis card
- `keterangan` opsional

## Struktur Halaman

Halaman utama dokumentasi disederhanakan menjadi:

- header ringkas berisi judul `Dokumentasi`
- kolom pencarian
- daftar riwayat upload
- tombol FAB `+` untuk membuka dialog upload

Elemen berikut dihapus dari halaman utama:

- hero besar dengan gradient
- teks penjelasan
- badge tambahan
- panel upload inline

## Kategori

Kategori yang tersedia:

- `koordinasi`
- `pendataan`
- `pengawasan`
- `pertemuan`
- `lainnya`
- `bukti paket data`

## Struktur Folder Google Drive

File dokumentasi tidak lagi diunggah langsung ke satu folder induk. Setiap kategori memakai subfolder otomatis di bawah folder induk dokumentasi.

Strukturnya menjadi:

- `Dokumentasi/Koordinasi`
- `Dokumentasi/Pendataan`
- `Dokumentasi/Pengawasan`
- `Dokumentasi/Pertemuan`
- `Dokumentasi/Lainnya`
- `Dokumentasi/Bukti Paket Data`

Saat upload:

- aplikasi membaca kategori yang dipilih
- aplikasi mencari subfolder kategori pada folder induk dokumentasi
- jika subfolder belum ada, aplikasi membuatnya
- file diunggah ke subfolder kategori tersebut

Pendekatan ini memakai subfolder otomatis dan tidak membutuhkan pengisian folder ID manual per kategori.

## Data Yang Disimpan

Metadata yang disimpan ke database:

- `user_id`
- `kategori`
- `keterangan`
- `link_file`
- `nama_file`
- `created_at`

Riwayat lokal tetap dipertahankan agar preview dan daftar upload yang sudah ada tidak berubah besar.

## Riwayat Upload

Riwayat upload memiliki mode pilih untuk menghapus file lokal dari perangkat.

Perilakunya:

- tersedia tombol `Pilih` pada area header riwayat
- saat mode pilih aktif, pengguna dapat memilih beberapa item pada daftar
- saat ada item terpilih, area header menampilkan jumlah item terpilih
- tersedia tombol `Hapus` dan `Batal`
- tombol `Hapus` hanya menghapus file lokal dan entry riwayat lokal
- file di Google Drive tidak dihapus
- metadata di database tidak dihapus

Saat mode pilih tidak aktif, tap item tetap membuka detail seperti sebelumnya.

## Alur Submit

1. Pengguna menekan FAB `+`.
2. Aplikasi membuka dialog tengah untuk upload.
3. Pengguna memilih gambar.
4. Pengguna memilih satu kategori melalui card.
5. Pengguna dapat mengisi `keterangan` bila perlu.
6. Aplikasi memastikan subfolder kategori tersedia di Google Drive.
7. Aplikasi mengunggah file ke subfolder kategori di Google Drive.
8. Aplikasi menyimpan metadata upload ke Supabase.
9. Aplikasi menyimpan entry lokal untuk riwayat dan preview.

## Dialog Upload

Dialog upload menampilkan:

- preview gambar terpilih
- tombol `Galeri`
- tombol `Kamera`
- card pilihan kategori
- input `keterangan`
- tombol `Upload`

Saat upload berhasil:

- dialog ditutup
- daftar utama langsung menampilkan item baru
- form upload dibersihkan untuk penggunaan berikutnya

## Error Handling

- Tombol upload hanya aktif jika file dan kategori sudah dipilih.
- `keterangan` boleh kosong.
- Jika simpan metadata ke database gagal, submit dianggap gagal agar sinkronisasi tidak diam-diam terlewat.
- Jika upload gagal, error tetap ditampilkan dalam dialog agar konteks aksi tidak hilang.
- Jika subfolder kategori belum ada dan pembuatan folder gagal, proses upload dibatalkan dengan pesan error yang jelas.
- Saat hapus lokal dari mode pilih, aplikasi menampilkan konfirmasi sebelum file lokal dihapus.
