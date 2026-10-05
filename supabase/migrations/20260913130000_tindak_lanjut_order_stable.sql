-- get_tindak_lanjut: urutan stabil untuk paging.
--
-- Latar: PostgREST membatasi respons RPC ke max-rows (default 1000), sehingga
-- Flutter mengambil data per halaman lewat Range (.range()). Paging hanya aman
-- bila urutan deterministik; urutan lama (kec, desa, kode, nama) bisa seri
-- (mis. nama kosong di SLS yang sama) → baris bisa terlewat/ganda antarhalaman.
-- Perbaikan: tambah assignment_id (PK) sebagai kunci urut terakhir.
-- Signature & kolom output TIDAK berubah.

create or replace function public.get_tindak_lanjut()
returns table (
  assignment_id           text,
  assignment_status_alias text,
  assignment_status_id    integer,
  level_6_full_code       text,
  level_6_name            text,
  nama                    text,
  alamat                  text,
  no_bang                 text,
  nm_kec                  text,
  nm_desa                 text,
  nm_sls                  text,
  ppl_nama                text,
  pml_nama                text,
  updated_at              timestamptz,
  perlu_hapus             boolean,
  alasan_hapus            text,
  hapus_oleh              text,
  hapus_at                timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select p.id as petugas_id, p.role
    from public.users u
    join public.se2026_petugas p on p.user_id = u.id
    where u.auth_uid = auth.uid()
      and coalesce(p.is_active, false)
    order by p.created_at desc nulls last
    limit 1
  )
  select
    t.assignment_id,
    t.assignment_status_alias,
    t.assignment_status_id,
    t.level_6_full_code,
    t.level_6_name,
    t.nama,
    t.alamat,
    t.no_bang,
    sw.nm_kec,
    sw.nm_desa,
    sw.nm_sls,
    sw.ppl_name,
    sw.pml_name,
    t.updated_at,
    (h.assignment_id is not null) as perlu_hapus,
    h.alasan,
    coalesce(nullif(trim(hu.name), ''), hu.email),
    h.updated_at
  from public.se2026_tindak_lanjut t
  cross join me
  left join public.vw_fasih_wilayah_scope_base sw
    on sw.kode_wilayah = t.level_6_full_code
  left join public.se2026_tindak_lanjut_hapus h
    on h.assignment_id = t.assignment_id
  left join public.se2026_petugas hp on hp.id = h.flagged_by
  left join public.users hu on hu.id = hp.user_id
  where me.role = 'admin'
     or (me.role = 'pengawas' and sw.pml_id = me.petugas_id)
     or (me.role = 'pendata'  and sw.ppl_id = me.petugas_id)
  order by sw.nm_kec nulls last, sw.nm_desa nulls last,
           t.level_6_full_code, t.nama, t.assignment_id;
$$;

grant execute on function public.get_tindak_lanjut() to authenticated;
