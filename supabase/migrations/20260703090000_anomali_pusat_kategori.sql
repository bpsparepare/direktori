-- Tabel kategori khusus sisi Pusat (usaha/keluarga dari excel Fasih), terpisah
-- total dari se2026_anomali_kategori (yang dipakai sisi Temuan/wilayah, scope
-- keluarga/anggota) -- tidak menyentuh tabel/kode lama sama sekali.
--
-- Skema kode: prefix 2 huruf + nomor, unik lintas scope:
--   KP# = Keluarga, sumber Pusat
--   UP# = Usaha, sumber Pusat
-- (KT#/AT#/UT# adalah kode sisi Temuan, hidup di se2026_anomali_kategori,
--  di luar cakupan migration ini.)

-- ============================================================
-- 1. TABEL REFERENSI KATEGORI PUSAT
-- ============================================================
create table public.anomali_pusat_kategori (
  anomali_id text not null primary key,
  scope text not null check (scope in ('usaha', 'keluarga')),
  kategori text not null,
  deskripsi_rule text,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 2. import_anomali_pusat_batch: kategori_kode kini ber-prefix KP/UP,
--    dan tiap kategori yang ditemukan otomatis ter-registrasi (upsert) ke
--    anomali_pusat_kategori -- tidak perlu seed manual.
-- ============================================================
create or replace function public.import_anomali_pusat_batch(
  p_scope text,
  p_rows jsonb
)
returns table(diperbarui integer, dinonaktifkan integer)
language plpgsql
security definer
as $function$
declare
    v_row           jsonb;
    v_nama_anomali  text;
    v_kategori_kode text;
    v_kategori_nama text;
    v_prefix        text;
    v_count         integer := 0;
    v_deactivated   integer := 0;
begin
    if p_scope not in ('usaha', 'keluarga') then
        raise exception 'scope tidak valid: %', p_scope;
    end if;

    v_prefix := case when p_scope = 'usaha' then 'UP' else 'KP' end;

    update public.anomali_pusat_temuan
    set is_active = false, updated_at = now()
    where scope = p_scope;
    get diagnostics v_deactivated = row_count;

    for v_row in select * from jsonb_array_elements(p_rows)
    loop
        v_nama_anomali := v_row ->> 'nama_anomali';

        select mm[1], mm[2]
        into v_kategori_kode, v_kategori_nama
        from regexp_matches(
            coalesce(v_nama_anomali, ''),
            'Anomali\s+(?:Data\s+)?(\d+)\s*\(([^)]*)\)'
        ) as mm;

        if v_kategori_kode is null then
            v_kategori_kode := 'lainnya';
            v_kategori_nama := coalesce(v_nama_anomali, '-');
        else
            v_kategori_kode := v_prefix || v_kategori_kode;
        end if;

        insert into public.anomali_pusat_kategori (
            anomali_id, scope, kategori, deskripsi_rule
        ) values (
            v_kategori_kode, p_scope, v_kategori_nama, v_nama_anomali
        )
        on conflict (anomali_id) do update set
            kategori       = excluded.kategori,
            deskripsi_rule = excluded.deskripsi_rule;

        insert into public.anomali_pusat_temuan (
            scope, assignment_id, nama_subjek,
            kode_prov, nama_provinsi, kode_kab, nama_kab,
            kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
            kategori_kode, kategori_nama, status_asal,
            id_petugas_asal, email_petugas_asal, link_fasih,
            is_active, imported_at, updated_at
        ) values (
            p_scope,
            v_row ->> 'assignment_id',
            v_row ->> 'nama_subjek',
            v_row ->> 'kode_prov', v_row ->> 'nama_provinsi',
            v_row ->> 'kode_kab', v_row ->> 'nama_kab',
            v_row ->> 'kode_kec', v_row ->> 'nama_kec',
            v_row ->> 'kode_desa', v_row ->> 'nama_desa',
            v_row ->> 'kode_sls', v_row ->> 'sub_sls',
            v_kategori_kode, v_kategori_nama,
            v_row ->> 'tindak_lanjut',
            nullif(v_row ->> 'id_petugas', '-'),
            nullif(v_row ->> 'email_petugas', '-'),
            v_row ->> 'link_fasih',
            true, now(), now()
        )
        on conflict (scope, assignment_id, nama_subjek, kategori_kode)
        do update set
            nama_provinsi       = excluded.nama_provinsi,
            nama_kab            = excluded.nama_kab,
            nama_kec            = excluded.nama_kec,
            nama_desa           = excluded.nama_desa,
            kode_kec            = excluded.kode_kec,
            kode_desa           = excluded.kode_desa,
            kode_sls            = excluded.kode_sls,
            sub_sls             = excluded.sub_sls,
            kategori_nama       = excluded.kategori_nama,
            status_asal         = excluded.status_asal,
            id_petugas_asal     = excluded.id_petugas_asal,
            email_petugas_asal  = excluded.email_petugas_asal,
            link_fasih          = excluded.link_fasih,
            is_active           = true,
            updated_at          = now();

        v_count := v_count + 1;
    end loop;

    return query select v_count, v_deactivated;
end;
$function$;
