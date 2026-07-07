-- Tambah kolom sub_sls pada get_responden_sulit supaya kartu/detail bisa
-- membedakan wilayah dengan nm_sls sama tapi sub-SLS berbeda.
--
-- sub_sls diturunkan dari 2 digit terakhir id se2026_wilayah_tugas (pola
-- 16 digit = kode_desa(10)+kode_sls(4)+sub_sls(2), lihat 20260701170000).
-- Perubahan return type -> drop dulu sebelum recreate.

drop function if exists public.get_responden_sulit(integer, integer);

create function public.get_responden_sulit(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  id uuid,
  kode_wilayah text,
  nm_kec text,
  nm_desa text,
  nm_sls text,
  sub_sls text,
  ppl_id uuid,
  pml_id uuid,
  ppl_nama text,
  pml_nama text,
  created_by uuid,
  created_by_nama text,
  nama text,
  alamat text,
  penjelasan text,
  tindak_lanjut text,
  can_edit boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_petugas_id uuid;
  v_role text;
  v_is_active boolean := false;
begin
  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.users u
  join public.se2026_petugas p on p.user_id = u.id
  where u.auth_uid = auth.uid()
  limit 1;

  if v_petugas_id is null or not v_is_active then
    return;
  end if;

  return query
  select
    r.id,
    r.kode_wilayah,
    wt.nm_kec,
    wt.nm_desa,
    wt.nm_sls,
    case
      when length(coalesce(r.kode_wilayah, '')) >= 16
        then right(r.kode_wilayah, 2)
      else null
    end as sub_sls,
    r.ppl_id,
    r.pml_id,
    ppl.nama,
    pml.nama,
    r.created_by,
    cb.nama,
    r.nama,
    r.alamat,
    r.penjelasan,
    r.tindak_lanjut,
    (
      v_role = 'admin'
      or r.created_by = v_petugas_id
      or (v_role = 'pengawas' and r.pml_id = v_petugas_id)
    ) as can_edit,
    r.created_at,
    r.updated_at
  from public.se2026_responden_sulit r
  left join public.se2026_wilayah_tugas wt on wt.id = r.kode_wilayah
  left join public.se2026_petugas ppl on ppl.id = r.ppl_id
  left join public.se2026_petugas pml on pml.id = r.pml_id
  left join public.se2026_petugas cb on cb.id = r.created_by
  where
    v_role = 'admin'
    or (v_role = 'pengawas' and r.pml_id = v_petugas_id)
    or (v_role = 'pendata' and r.ppl_id = v_petugas_id)
  order by r.updated_at desc
  limit p_limit offset p_offset;
end;
$$;

grant execute on function public.get_responden_sulit(integer, integer) to authenticated;

notify pgrst, 'reload schema';
