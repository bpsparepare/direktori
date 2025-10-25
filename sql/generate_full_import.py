#!/usr/bin/env python3
"""
Script untuk mengkonversi importbps.csv ke SQL INSERT statements
yang dapat dijalankan langsung di Supabase SQL Editor

Usage: python generate_full_import.py
Output: full_import_bps.sql
"""

import csv
import json
import os

def escape_sql_string(value):
    """Escape string untuk SQL dengan menangani single quotes"""
    if value is None or value == '':
        return 'NULL'
    # Escape single quotes
    escaped = str(value).replace("'", "''")
    return f"'{escaped}'"

def convert_to_decimal(value, max_precision=8):
    """Convert string ke decimal dengan pembatasan presisi atau NULL"""
    if value is None or value == '' or value.strip() == '':
        return 'NULL'
    try:
        decimal_value = float(value)
        # Batasi presisi sesuai schema database (8 digit setelah koma)
        rounded_value = round(decimal_value, max_precision)
        return str(rounded_value)
    except ValueError:
        return 'NULL'

def convert_to_int(value):
    """Convert string ke integer atau default 1"""
    if value is None or value == '' or value.strip() == '':
        return '1'
    try:
        return str(int(value))
    except ValueError:
        return '1'

def generate_sql_from_csv():
    """Generate SQL INSERT statements dari CSV file"""
    
    # Path ke file CSV
    csv_file = '../import/importbps.csv'
    output_file = 'full_import_bps.sql'
    
    if not os.path.exists(csv_file):
        print(f"Error: File {csv_file} tidak ditemukan!")
        print("Pastikan file importbps.csv ada di folder import/")
        return
    
    # Header SQL
    sql_content = """-- ========================================
-- FULL IMPORT BPS CSV DATA TO DIREKTORI TABLE
-- ========================================
-- Generated automatically from importbps.csv
-- Total records: akan dihitung otomatis
-- File: full_import_bps.sql

-- ========================================
-- BULK INSERT ALL DATA
-- ========================================

INSERT INTO direktori (
    id_sbr,
    nama_usaha,
    nama_komersial_usaha,
    alamat,
    nama_sls,
    kd_prov,
    kd_kab,
    kd_kec,
    kd_desa,
    kd_sls,
    id_sls,
    keberadaan_usaha,
    nomor_telepon,
    nomor_whatsapp,
    email,
    website,
    latitude,
    longitude,
    kode_pos,
    sumber_data,
    kegiatan_usaha,
    skala_usaha
) VALUES
"""
    
    values_list = []
    record_count = 0
    
    try:
        with open(csv_file, 'r', encoding='utf-8') as file:
            csv_reader = csv.DictReader(file)
            
            for row in csv_reader:
                record_count += 1
                
                # Extract dan clean data
                id_sbr = row.get('idsbr', '')
                nama_usaha = escape_sql_string(row.get('nama_usaha', 'Usaha Tanpa Nama'))
                nama_komersial = escape_sql_string(row.get('nama_komersial_usaha', ''))
                alamat = escape_sql_string(row.get('alamat', ''))
                nama_sls = escape_sql_string(row.get('nama_sls', ''))
                kd_prov = escape_sql_string(row.get('kdprov', '').zfill(2))
                kd_kab = escape_sql_string(row.get('kdkab', '').zfill(2))
                kd_kec = escape_sql_string(row.get('kdkec', '').zfill(3))
                kd_desa = escape_sql_string(row.get('kddesa', '').zfill(3))
                keberadaan_usaha = convert_to_int(row.get('keberadaan_usaha', '1'))
                nomor_telepon = escape_sql_string(row.get('nomor_telepon', ''))
                nomor_whatsapp = escape_sql_string(row.get('nomor_whatsapp', ''))
                email = escape_sql_string(row.get('email', ''))
                website = escape_sql_string(row.get('website', ''))
                latitude = convert_to_decimal(row.get('latitude', ''), 8)  # DECIMAL(10,8) - max 8 digit setelah koma
                longitude = convert_to_decimal(row.get('longitude', ''), 8)  # DECIMAL(11,8) - max 8 digit setelah koma
                kode_pos = escape_sql_string(row.get('kodepos', ''))
                
                # Default values
                kd_sls = 'NULL'
                id_sls = 'NULL'
                sumber_data = "'BPS'"
                kegiatan_usaha = "'[{\"kegiatan_usaha\": \"Belum Dikategorikan\", \"kategori\": \"Umum\", \"kbli\": \"00000\"}]'::jsonb"
                skala_usaha = "'mikro'"
                
                # Buat VALUES string
                values_string = f"""({id_sbr}, {nama_usaha}, {nama_komersial}, {alamat}, {nama_sls}, {kd_prov}, {kd_kab}, {kd_kec}, {kd_desa}, {kd_sls}, {id_sls}, {keberadaan_usaha}, {nomor_telepon}, {nomor_whatsapp}, {email}, {website}, {latitude}, {longitude}, {kode_pos}, {sumber_data}, {kegiatan_usaha}, {skala_usaha})"""
                
                values_list.append(values_string)
                
                # Progress indicator
                if record_count % 500 == 0:
                    print(f"Processed {record_count} records...")
    
    except Exception as e:
        print(f"Error reading CSV: {e}")
        return
    
    # Gabungkan semua VALUES
    sql_content += ',\n'.join(values_list) + ';\n\n'
    
    # Footer SQL dengan validasi
    sql_content += f"""-- ========================================
-- VALIDASI HASIL IMPORT
-- ========================================

-- Total records yang diimpor: {record_count}

-- Cek jumlah data yang berhasil diimpor
SELECT 'Total BPS records imported' as info, COUNT(*) as count 
FROM direktori 
WHERE sumber_data = 'BPS';

-- Cek data dengan koordinat
SELECT 'Records with coordinates' as info, COUNT(*) as count 
FROM direktori 
WHERE sumber_data = 'BPS' 
  AND latitude IS NOT NULL 
  AND longitude IS NOT NULL;

-- Cek distribusi per wilayah
SELECT 
    kd_prov,
    kd_kab,
    kd_kec,
    kd_desa,
    COUNT(*) as jumlah_usaha
FROM direktori 
WHERE sumber_data = 'BPS'
GROUP BY kd_prov, kd_kab, kd_kec, kd_desa
ORDER BY kd_prov, kd_kab, kd_kec, kd_desa;

-- Sample data yang berhasil diimpor
SELECT 
    id_sbr,
    nama_usaha,
    alamat,
    CONCAT(kd_prov, kd_kab, kd_kec, kd_desa) as kode_wilayah,
    nomor_telepon,
    email,
    created_at
FROM direktori 
WHERE sumber_data = 'BPS'
ORDER BY created_at DESC
LIMIT 10;

-- ========================================
-- CATATAN
-- ========================================
-- File ini berisi {record_count} INSERT statements
-- Dapat dijalankan langsung di Supabase SQL Editor
-- Pastikan tabel direktori sudah ada dan memiliki struktur yang benar
"""
    
    # Tulis ke file
    try:
        with open(output_file, 'w', encoding='utf-8') as file:
            file.write(sql_content)
        
        print(f"✅ Success! Generated {output_file}")
        print(f"📊 Total records: {record_count}")
        print(f"📁 File size: {os.path.getsize(output_file) / 1024:.1f} KB")
        print(f"🚀 Ready to run in Supabase SQL Editor!")
        
    except Exception as e:
        print(f"Error writing SQL file: {e}")

if __name__ == "__main__":
    generate_sql_from_csv()