-- Distribusi kode_bang (jenis bangunan) per WILAYAH 16 digit, bersumber dari
-- se2026_keterangan_umum. Dipakai Lembar Kerja untuk memecah "submitted" per
-- wilayah menjadi rincian jenis bangunan.
--
-- HANYA menghitung record SUBMITTED, yaitu assignment_status_alias yang bukan
-- OPEN% dan bukan DRAFT% (definisi sama dengan kolom Submitted di rekap),
-- sehingga total rincian kode_bang selaras dengan angka submitted.
-- CATATAN: filter ini diperbaiki di migration berikutnya (20260713120000)
-- karena assignment_status_alias sering basi/kosong.
--
-- Scope mengikuti role (diderive dari auth.uid()):
--   * admin    : semua wilayah
--   * pengawas : wilayah yang pml_id = petugasnya
--   * pendata  : wilayah yang ppl_id = petugasnya
-- Wilayah dipetakan dari se2026_wilayah_tugas (prefix 16 digit) ke
-- keterangan_umum lewat left(ku.kode_wilayah, 16) = left(wt.id, 16).
-- kode_bang kosong/NULL dikembalikan sebagai NULL (dipetakan "Tidak Diketahui"
-- di aplikasi). Nama kolom output: kode_wilayah (16 digit), kode_bang, jumlah.

create or replace function public.get_se2026_kode_bang_by_wilayah()
returns table (
  kode_wilayah text,
  kode_bang text,
  jumlah bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth_uid   uuid := auth.uid();
  v_user_id    uuid;
  v_petugas_id uuid;
  v_role       text;
  v_is_active  boolean := false;
begin
  if v_auth_uid is null then
    return;
  end if;

  select u.id into v_user_id
  from public.users u
  where u.auth_uid = v_auth_uid
  limit 1;
  if v_user_id is null then
    return;
  end if;

  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;

  if not v_is_active or v_petugas_id is null then
    return;
  end if;

  return query
  with wilayah_scope as (
    -- Satu baris per prefix wilayah 16 digit (ambil versi terbaru bila subsls
    -- ganda) agar pml_id/ppl_id konsisten dan tidak menggandakan hitungan.
    select distinct on (left(wt.id, 16))
      left(wt.id, 16) as w16,
      wt.pml_id,
      wt.ppl_id
    from public.se2026_wilayah_tugas wt
    where wt.id is not null
    order by left(wt.id, 16), wt.created_at desc nulls last
  )
  select
    ws.w16 as kode_wilayah,
    nullif(btrim(ku.kode_bang), '') as kode_bang,
    count(*)::bigint as jumlah
  from public.se2026_keterangan_umum ku
  join wilayah_scope ws
    on ws.w16 = left(ku.kode_wilayah, 16)
  where (
    v_role = 'admin'
    or (v_role = 'pengawas' and ws.pml_id = v_petugas_id)
    or (v_role = 'pendata'  and ws.ppl_id = v_petugas_id)
  )
  -- Hanya record submitted (bukan OPEN & bukan DRAFT); status kosong/NULL
  -- dianggap belum submitted sehingga tidak dihitung.
  and ku.assignment_status_alias is not null
  and upper(btrim(ku.assignment_status_alias)) not like 'OPEN%'
  and upper(btrim(ku.assignment_status_alias)) not like 'DRAFT%'
  group by 1, 2
  order by 1 asc, jumlah desc, 2 asc;
end;
$$;

grant execute on function public.get_se2026_kode_bang_by_wilayah() to authenticated;
