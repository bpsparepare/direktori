"""
Konversi excel export Fasih "Data Mikro Kasus Anomali Usaha/Keluarga" jadi
satu JSON gabungan, siap dipakai sebagai p_rows untuk RPC
import_anomali_pusat_batch(p_scope, p_rows) di
supabase/migrations/20260701170000_anomali_pusat_baru.sql.

Usage:
    python3 scripts/convert_anomali_pusat_excel_to_json.py [usaha.xlsx] [keluarga.xlsx] [output.json]

Tanpa argumen, dipakai default path Downloads sesuai file yang sedang diproses.
"""

import json
import sys
import pandas as pd

DEFAULT_USAHA = "/Users/nasrul/Downloads/Data_Mikro_Anomali_usaha_7372_20260630_210254.xlsx"
DEFAULT_KELUARGA = "/Users/nasrul/Downloads/Data_Mikro_Anomali_keluarga_7372_20260630_154253.xlsx"
DEFAULT_OUTPUT = "/Users/nasrul/Downloads/anomali_pusat_gabungan.json"

# Kolom asli (header di row ke-4 / index 3) -> field p_rows RPC.
# Kolom pertama ("No") dan kolom kedua (Nama Usaha/Nama KRT) ditangani terpisah.
COLUMN_MAP = {
    "Kode Prov": "kode_prov",
    "Nama Provinsi": "nama_provinsi",
    "Kode Kab/Kota": "kode_kab",
    "Nama Kab/Kota": "nama_kab",
    "Kode Kec": "kode_kec",
    "Nama Kecamatan": "nama_kec",
    "Kode Desa": "kode_desa",
    "Nama Desa/Kel": "nama_desa",
    "Kode SLS": "kode_sls",
    "Sub SLS": "sub_sls",
    "Assignment ID": "assignment_id",
    "Nama Anomali": "nama_anomali",
    "Tindak Lanjut": "tindak_lanjut",
    "ID Petugas": "id_petugas",
    "Email Petugas": "email_petugas",
    "Link Fasih": "link_fasih",
}


def convert_sheet(path: str, scope: str) -> list[dict]:
    # Row 1-3 judul/metadata cetak, row 4 (index 3) header asli, row 5 header
    # angka placeholder "(1)".."(18)" yang harus ikut dibuang.
    # dtype=str wajib: kolom kode wilayah (Kode SLS, Sub SLS, dst) berformat
    # angka dengan leading zero (mis. "0014", "00") -- tanpa ini pandas
    # membaca sebagai int64 dan leading zero-nya hilang.
    df = pd.read_excel(path, header=3, skiprows=[4], dtype=str)
    df = df.fillna("")

    subjek_col = df.columns[1]  # "Nama Usaha" atau "Nama KRT"

    rows = []
    for _, r in df.iterrows():
        row = {"scope": scope, "nama_subjek": r[subjek_col]}
        for col_asli, field in COLUMN_MAP.items():
            row[field] = r.get(col_asli, "")
        rows.append(row)
    return rows


def main():
    usaha_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_USAHA
    keluarga_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_KELUARGA
    output_path = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_OUTPUT

    result = {
        "usaha": convert_sheet(usaha_path, "usaha"),
        "keluarga": convert_sheet(keluarga_path, "keluarga"),
    }

    with open(output_path, "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"usaha: {len(result['usaha'])} baris")
    print(f"keluarga: {len(result['keluarga'])} baris")
    print(f"output: {output_path}")


if __name__ == "__main__":
    main()
