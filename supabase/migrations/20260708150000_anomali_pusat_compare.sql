-- Pratinjau perbandingan file import anomali pusat vs isi database, TANPA
-- mengubah data apa pun. Dipakai halaman "Impor Anomali Pusat" supaya
-- pengguna bisa melihat dampak upload sebelum benar-benar mengunggah.
--
-- Kunci kasus & aturan parsing kategori sama persis dengan
-- import_anomali_pusat_batch (lihat 20260706120000_anomali_pusat_kategori_prefix.sql):
--   kunci = (scope, assignment_id, nama_subjek, kategori_kode)
--   kategori_kode = prefix scope (UP/KP) + nomor dari "Nama Anomali".
--
-- Status per baris hasil:
--   'baru'    -> ada di file, belum ada di database.
--   'berubah' -> ada di keduanya, tapi ada kolom yang nilainya beda
--                (rincian di kolom `perubahan`, termasuk reaktivasi
--                kasus yang sedang nonaktif).
--   'sama'    -> ada di keduanya, isinya identik.
--   'hilang'  -> ada di database (scope sama), tidak ada di file.
--                is_aktif menunjukkan apakah kasus itu sedang aktif.
--
-- `perubahan`: jsonb array of {field, lama, baru}. Kolom yang dibandingkan
-- persis kolom yang di-update oleh upsert import (nama wilayah, kode
-- kec/desa/sls, kategori_nama, status_asal, petugas, link_fasih).
-- null dan string kosong dianggap sama supaya tidak jadi noise.

-- Helper: jsonb array 1 elemen {field, lama, baru} kalau nilai berbeda,
-- array kosong kalau sama (null == '' dianggap sama). Dipakai dengan
-- operator || untuk menyusun daftar perubahan tanpa VALUES korelasi.
create or replace function public._diff_anomali_pusat(
  p_field text, p_lama text, p_baru text
)
returns jsonb
language sql
immutable
as $diff$
  select case
    when coalesce(p_lama, '') <> coalesce(p_baru, '')
      then jsonb_build_array(jsonb_build_object(
             'field', p_field, 'lama', p_lama, 'baru', p_baru))
    else '[]'::jsonb
  end;
$diff$;

create or replace function public.compare_anomali_pusat_batch(
  p_scope text,
  p_rows jsonb
)
returns table(
  status text,
  assignment_id text,
  nama_subjek text,
  kategori_kode text,
  kategori_nama text,
  nama_kec text,
  nama_desa text,
  is_aktif boolean,
  perubahan jsonb
)
language plpgsql
security definer
as $function$
declare
    v_prefix text;
begin
    if p_scope not in ('usaha', 'keluarga') then
        raise exception 'scope tidak valid: %', p_scope;
    end if;

    v_prefix := case when p_scope = 'usaha' then 'UP' else 'KP' end;

    return query
    with parsed as (
        select
            e.value ->> 'assignment_id'              as assignment_id,
            e.value ->> 'nama_subjek'                as nama_subjek,
            e.value ->> 'nama_provinsi'              as nama_provinsi,
            e.value ->> 'nama_kab'                   as nama_kab,
            e.value ->> 'kode_kec'                   as kode_kec,
            e.value ->> 'nama_kec'                   as nama_kec,
            e.value ->> 'kode_desa'                  as kode_desa,
            e.value ->> 'nama_desa'                  as nama_desa,
            e.value ->> 'kode_sls'                   as kode_sls,
            e.value ->> 'sub_sls'                    as sub_sls,
            e.value ->> 'tindak_lanjut'              as status_asal,
            nullif(e.value ->> 'id_petugas', '-')    as id_petugas_asal,
            nullif(e.value ->> 'email_petugas', '-') as email_petugas_asal,
            e.value ->> 'link_fasih'                 as link_fasih,
            e.value ->> 'nama_anomali'               as nama_anomali,
            regexp_match(
                coalesce(e.value ->> 'nama_anomali', ''),
                'Anomali\s+(?:Data\s+)?(\d+)\s*\(([^)]*)\)'
            ) as m,
            e.ordinality as urutan
        from jsonb_array_elements(p_rows) with ordinality e(value, ordinality)
        where coalesce(e.value ->> 'assignment_id', '') <> ''
    ),
    kategori as (
        select
            p.*,
            case when p.m is null then v_prefix || 'LAINNYA'
                 else v_prefix || p.m[1] end as kategori_kode,
            case when p.m is null then coalesce(nullif(p.nama_anomali, ''), '-')
                 else trim(p.m[2]) end as kategori_nama
        from parsed p
    ),
    -- Duplikat kunci di dalam file: baris terakhir menang, sama seperti
    -- perilaku upsert berurutan di import_anomali_pusat_batch.
    dedup as (
        select distinct on (k.assignment_id, k.nama_subjek, k.kategori_kode) k.*
        from kategori k
        order by k.assignment_id, k.nama_subjek, k.kategori_kode, k.urutan desc
    ),
    matched as (
        select
            d.*,
            t.id as temuan_id,
            t.is_active as t_is_active,
            case when t.id is null then '[]'::jsonb
            else
                (case when t.is_active then '[]'::jsonb
                      else jsonb_build_array(jsonb_build_object(
                               'field', 'status_aktif',
                               'lama', 'nonaktif',
                               'baru', 'aktif'))
                 end)
                || public._diff_anomali_pusat('nama_provinsi', t.nama_provinsi, d.nama_provinsi)
                || public._diff_anomali_pusat('nama_kab',      t.nama_kab,      d.nama_kab)
                || public._diff_anomali_pusat('kode_kec',      t.kode_kec,      d.kode_kec)
                || public._diff_anomali_pusat('nama_kec',      t.nama_kec,      d.nama_kec)
                || public._diff_anomali_pusat('kode_desa',     t.kode_desa,     d.kode_desa)
                || public._diff_anomali_pusat('nama_desa',     t.nama_desa,     d.nama_desa)
                || public._diff_anomali_pusat('kode_sls',      t.kode_sls,      d.kode_sls)
                || public._diff_anomali_pusat('sub_sls',       t.sub_sls,       d.sub_sls)
                || public._diff_anomali_pusat('kategori_nama', t.kategori_nama, d.kategori_nama)
                || public._diff_anomali_pusat('status_asal',   t.status_asal,   d.status_asal)
                || public._diff_anomali_pusat('id_petugas',    t.id_petugas_asal,    d.id_petugas_asal)
                || public._diff_anomali_pusat('email_petugas', t.email_petugas_asal, d.email_petugas_asal)
                || public._diff_anomali_pusat('link_fasih',    t.link_fasih,    d.link_fasih)
            end as diffs
        from dedup d
        left join public.anomali_pusat_temuan t
          on t.scope = p_scope
         and t.assignment_id = d.assignment_id
         and t.nama_subjek = d.nama_subjek
         and t.kategori_kode = d.kategori_kode
    )
    select
        case
            when m2.temuan_id is null then 'baru'
            when m2.diffs = '[]'::jsonb then 'sama'
            else 'berubah'
        end,
        m2.assignment_id, m2.nama_subjek,
        m2.kategori_kode, m2.kategori_nama,
        m2.nama_kec, m2.nama_desa,
        coalesce(m2.t_is_active, true),
        m2.diffs
    from matched m2
    union all
    select
        'hilang',
        t.assignment_id, t.nama_subjek,
        t.kategori_kode, t.kategori_nama,
        t.nama_kec, t.nama_desa,
        t.is_active,
        '[]'::jsonb
    from public.anomali_pusat_temuan t
    where t.scope = p_scope
      and not exists (
          select 1 from dedup d
          where d.assignment_id = t.assignment_id
            and d.nama_subjek = t.nama_subjek
            and d.kategori_kode = t.kategori_kode
      )
    order by 1, 6, 7, 3;
end;
$function$;
