#!/usr/bin/env python3
"""
Script untuk mengekstrak data dari GeoJSON dan menghasilkan SQL INSERT statements
untuk tabel wilayah di Supabase.

Usage:
    python extract_geojson_data.py

Output:
    - import_all_geojson_data.sql (file SQL dengan semua INSERT statements)
"""

import json
import os

def extract_geojson_to_sql():
    # Path ke file GeoJSON
    geojson_path = "../assets/geojson/final_sls.geojson"
    output_sql_path = "import_all_geojson_data.sql"
    
    # Baca file GeoJSON
    try:
        with open(geojson_path, 'r', encoding='utf-8') as f:
            geojson_data = json.load(f)
    except FileNotFoundError:
        print(f"Error: File {geojson_path} tidak ditemukan!")
        return
    except json.JSONDecodeError:
        print(f"Error: File {geojson_path} bukan format JSON yang valid!")
        return
    
    # Ekstrak features
    features = geojson_data.get('features', [])
    if not features:
        print("Error: Tidak ada features dalam GeoJSON!")
        return
    
    print(f"Ditemukan {len(features)} features dalam GeoJSON")
    
    # Kumpulkan semua data unik berdasarkan idsls
    unique_data = {}
    
    for i, feature in enumerate(features):
        properties = feature.get('properties', {})
        
        # Ekstrak field yang dibutuhkan
        idsls = properties.get('idsls', '')
        kdprov = properties.get('kdprov', '')
        kdkab = properties.get('kdkab', '')
        kdkec = properties.get('kdkec', '')
        kddesa = properties.get('kddesa', '')
        kdsls = properties.get('kdsls', '')
        nmprov = properties.get('nmprov', '')
        nmkab = properties.get('nmkab', '')
        nmkec = properties.get('nmkec', '')
        nmdesa = properties.get('nmdesa', '')
        nmsls = properties.get('nmsls', '')
        
        # Debug: print first few records
        if i < 3:
            print(f"Feature {i}: idsls={idsls}, kdprov={kdprov}, nmprov={nmprov}")
        
        # Skip jika id_sls tidak ada (field utama)
        if not idsls:
            print(f"Skipping feature {i}: no idsls")
            continue
        
        # Simpan data unik berdasarkan idsls
        unique_data[idsls] = {
            'idsls': idsls,
            'kdprov': kdprov,
            'kdkab': kdkab,
            'kdkec': kdkec,
            'kddesa': kddesa,
            'kdsls': kdsls,
            'nmprov': nmprov.replace("'", "''") if nmprov else '',  # Escape single quotes
            'nmkab': nmkab.replace("'", "''") if nmkab else '',
            'nmkec': nmkec.replace("'", "''") if nmkec else '',
            'nmdesa': nmdesa.replace("'", "''") if nmdesa else '',
            'nmsls': nmsls.replace("'", "''") if nmsls else ''
        }
    
    print(f"Berhasil mengekstrak {len(unique_data)} record unik")
    
    # Buat SQL INSERT statements
    sql_statements = []
    sql_statements.append("-- Script untuk import semua data GeoJSON ke tabel wilayah")
    sql_statements.append("-- Generated automatically from final_sls.geojson")
    sql_statements.append("")
    sql_statements.append("-- Pastikan tabel wilayah sudah dibuat terlebih dahulu")
    sql_statements.append("-- Jalankan create_single_wilayah_table.sql sebelum script ini")
    sql_statements.append("")
    
    # Generate INSERT statements
    if unique_data:
        sql_statements.append("INSERT INTO wilayah (id_sls, kd_prov, kd_kab, kd_kec, kd_desa, kd_sls, nm_prov, nm_kab, nm_kec, nm_desa, nm_sls) VALUES")
        
        values_list = []
        for data in unique_data.values():
            value_str = f"('{data['idsls']}', '{data['kdprov']}', '{data['kdkab']}', '{data['kdkec']}', '{data['kddesa']}', '{data['kdsls']}', '{data['nmprov']}', '{data['nmkab']}', '{data['nmkec']}', '{data['nmdesa']}', '{data['nmsls']}')"
            values_list.append(value_str)
        
        # Gabungkan semua values
        sql_statements.append(',\n'.join(values_list))
        sql_statements.append("ON CONFLICT (id_sls) DO UPDATE SET")
        sql_statements.append("    kd_prov = EXCLUDED.kd_prov,")
        sql_statements.append("    kd_kab = EXCLUDED.kd_kab,")
        sql_statements.append("    kd_kec = EXCLUDED.kd_kec,")
        sql_statements.append("    kd_desa = EXCLUDED.kd_desa,")
        sql_statements.append("    kd_sls = EXCLUDED.kd_sls,")
        sql_statements.append("    nm_prov = EXCLUDED.nm_prov,")
        sql_statements.append("    nm_kab = EXCLUDED.nm_kab,")
        sql_statements.append("    nm_kec = EXCLUDED.nm_kec,")
        sql_statements.append("    nm_desa = EXCLUDED.nm_desa,")
        sql_statements.append("    nm_sls = EXCLUDED.nm_sls,")
        sql_statements.append("    updated_at = CURRENT_TIMESTAMP;")
        sql_statements.append("")
        sql_statements.append("-- Verifikasi hasil import")
        sql_statements.append("SELECT COUNT(*) as total_records FROM wilayah;")
        sql_statements.append("SELECT DISTINCT nm_prov FROM wilayah ORDER BY nm_prov;")
    else:
        sql_statements.append("-- Tidak ada data untuk diimport")
    
    # Tulis ke file SQL
    try:
        with open(output_sql_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(sql_statements))
        print(f"✅ Berhasil mengekstrak {len(unique_data)} record unik dari GeoJSON")
        print(f"📄 File SQL telah dibuat: {output_sql_path}")
        print(f"🚀 Jalankan file SQL tersebut di Supabase untuk import data")
    except Exception as e:
        print(f"Error menulis file SQL: {e}")

if __name__ == "__main__":
    extract_geojson_to_sql()