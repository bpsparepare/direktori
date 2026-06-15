drop materialized view if exists public.mv_fasih_assignment_summary;

create materialized view public.mv_fasih_assignment_summary as
with
  base as (
    select
      fad.id,
      fad.assignment_id,
      fad.survey_period_id,
      fad.detail_status,
      fad.detail_fetched_at,
      fad.source_modified_at,
      fad.created_at,
      fad.updated_at,
      fad.payload_json -> 'data'::text as d,
      (((fad.payload_json -> 'data'::text) ->> 'data'::text)::jsonb) -> 'answers'::text as ans
    from public.fasih_assignment_details fad
  ),
  unnested as (
    select
      b.id,
      el.value ->> 'dataKey'::text as key,
      el.value -> 'answer'::text as answer_raw,
      el.value ->> 'answer'::text as answer_text
    from base b,
      lateral jsonb_array_elements(coalesce(b.ans, '[]'::jsonb)) el(value)
  ),
  pivoted as (
    select
      unnested.id,
      max(
        case
          when unnested.key = 'nama_sls'::text then unnested.answer_text
          else null::text
        end
      ) as nama_sls,
      max(
        case
          when unnested.key = 'nama_usaha_bang'::text then unnested.answer_text
          else null::text
        end
      ) as nama_usaha_lengkap,
      max(
        case
          when unnested.key = 'kbli_akhir#1'::text then unnested.answer_text
          else null::text
        end
      ) as kbli_akhir,
      max(
        case
          when unnested.key = 'pengusaha#1'::text then unnested.answer_text
          else null::text
        end
      ) as nama_pengusaha,
      max(
        case
          when unnested.key = 'hp#1'::text then unnested.answer_text
          else null::text
        end
      ) as hp,
      max(
        case
          when unnested.key = 'tahun_operasi#1'::text then unnested.answer_text
          else null::text
        end
      ) as tahun_operasi,
      max(
        case
          when unnested.key = 'badan_usaha#1'::text then (unnested.answer_raw -> 0) ->> 'value'::text
          else null::text
        end
      ) as kode_badan_usaha,
      max(
        case
          when unnested.key = 'badan_usaha#1'::text then (unnested.answer_raw -> 0) ->> 'label'::text
          else null::text
        end
      ) as label_badan_usaha,
      max(
        case
          when unnested.key = 'jaringan#1'::text then (unnested.answer_raw -> 0) ->> 'value'::text
          else null::text
        end
      ) as jaringan,
      max(
        case
          when unnested.key = 'internet#1'::text then (unnested.answer_raw -> 0) ->> 'value'::text
          else null::text
        end
      ) as internet,
      max(
        case
          when unnested.key = 'internet_pesanan#1'::text then (unnested.answer_raw -> 0) ->> 'value'::text
          else null::text
        end
      ) as internet_pesanan,
      max(
        case
          when unnested.key = 'digital#1'::text then (unnested.answer_raw -> 0) ->> 'value'::text
          else null::text
        end
      ) as digital,
      max(
        case
          when unnested.key = 'tk_laki#1'::text then unnested.answer_text::integer
          else null::integer
        end
      ) as tk_laki,
      max(
        case
          when unnested.key = 'tk_pr#1'::text then unnested.answer_text::integer
          else null::integer
        end
      ) as tk_pr,
      max(
        case
          when unnested.key = 'total_tk_jk#1'::text then unnested.answer_text::integer
          else null::integer
        end
      ) as total_tk_jk,
      max(
        case
          when unnested.key = 'tk_dibayar#1'::text then unnested.answer_text::integer
          else null::integer
        end
      ) as tk_dibayar,
      max(
        case
          when unnested.key = 'tk_tdk_dibayar#1'::text then unnested.answer_text::integer
          else null::integer
        end
      ) as tk_tdk_dibayar,
      max(
        case
          when unnested.key = 'no_bang'::text then unnested.answer_text::integer
          else null::integer
        end
      ) as no_bang,
      max(
        case
          when unnested.key = 'nilai_pendapatan#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as nilai_pendapatan,
      max(
        case
          when unnested.key = 'pendapatan_lain#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as pendapatan_lain,
      max(
        case
          when unnested.key = 'total_pendapatan#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as total_pendapatan,
      max(
        case
          when unnested.key = 'pendapatan_online#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as pendapatan_online,
      max(
        case
          when unnested.key = 'gaji#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as gaji,
      max(
        case
          when unnested.key = 'biaya_produksi#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as biaya_produksi,
      max(
        case
          when unnested.key = 'operasional#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as operasional,
      max(
        case
          when unnested.key = 'total_pengeluaran#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as total_pengeluaran,
      max(
        case
          when unnested.key = 'aset_usaha_thn#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as aset_usaha,
      max(
        case
          when unnested.key = 'aset_lain_thn#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as aset_lain,
      max(
        case
          when unnested.key = 'total_aset_thn#1'::text then unnested.answer_text::bigint
          else null::bigint
        end
      ) as total_aset,
      max(
        case
          when unnested.key = 'luas_tanah_thn#1'::text then unnested.answer_text::numeric
          else null::numeric
        end
      ) as luas_tanah
    from unnested
    group by unnested.id
  ),
  extracted as (
    select
      b.id,
      b.assignment_id,
      b.survey_period_id,
      b.detail_status,
      b.detail_fetched_at,
      b.source_modified_at,
      b.created_at,
      b.updated_at,
      b.d ->> 'data1'::text as nama_usaha,
      b.d ->> 'data2'::text as alamat,
      b.d ->> 'data3'::text as idsbr,
      b.d ->> 'data4'::text as nib,
      b.d ->> 'data6'::text as skala_usaha,
      b.d ->> 'source_from'::text as source_from,
      b.d ->> 'assignment_status_alias'::text as status_alias,
      (((((((b.d -> 'region'::text) -> 'level_1'::text) -> 'level_2'::text) -> 'level_3'::text) -> 'level_4'::text) -> 'level_5'::text) -> 'level_6'::text) ->> 'full_code'::text as kode_wilayah,
      ((((b.d -> 'region'::text) -> 'level_1'::text) -> 'level_2'::text) -> 'level_3'::text) ->> 'name'::text as kecamatan,
      (((((b.d -> 'region'::text) -> 'level_1'::text) -> 'level_2'::text) -> 'level_3'::text) -> 'level_4'::text) ->> 'name'::text as desa,
      p.nama_sls,
      p.no_bang,
      p.nama_usaha_lengkap,
      p.kbli_akhir,
      p.kode_badan_usaha,
      p.label_badan_usaha,
      p.nama_pengusaha,
      p.hp,
      p.tahun_operasi,
      p.jaringan,
      p.internet,
      p.internet_pesanan,
      p.digital,
      p.tk_laki,
      p.tk_pr,
      p.total_tk_jk,
      p.tk_dibayar,
      p.tk_tdk_dibayar,
      p.nilai_pendapatan,
      p.pendapatan_lain,
      p.total_pendapatan,
      p.pendapatan_online,
      p.gaji,
      p.biaya_produksi,
      p.operasional,
      p.total_pengeluaran,
      p.aset_usaha,
      p.aset_lain,
      p.total_aset,
      p.luas_tanah,
      (b.d ->> 'latitude'::text)::numeric as latitude,
      (b.d ->> 'longitude'::text)::numeric as longitude
    from base b
    join pivoted p on p.id = b.id
  )
select
  e.id,
  e.assignment_id,
  e.survey_period_id,
  e.nama_usaha,
  e.nama_usaha_lengkap,
  e.alamat,
  e.idsbr,
  e.nib,
  e.nama_pengusaha,
  e.hp,
  e.kecamatan,
  e.desa,
  e.nama_sls,
  e.no_bang,
  e.skala_usaha,
  e.kbli_akhir,
  e.kode_badan_usaha,
  e.label_badan_usaha,
  e.jaringan,
  e.tahun_operasi,
  e.source_from,
  e.status_alias,
  e.tk_laki,
  e.tk_pr,
  e.total_tk_jk,
  e.tk_dibayar,
  e.tk_tdk_dibayar,
  coalesce(e.tk_dibayar, 0) + coalesce(e.tk_tdk_dibayar, 0) as total_tk_hitung,
  e.total_tk_jk <> (coalesce(e.tk_laki, 0) + coalesce(e.tk_pr, 0)) as flag_tk_jk,
  e.total_tk_jk <> (coalesce(e.tk_dibayar, 0) + coalesce(e.tk_tdk_dibayar, 0)) as flag_tk_bayar,
  e.nilai_pendapatan,
  e.pendapatan_lain,
  e.total_pendapatan,
  e.pendapatan_online,
  e.total_pendapatan <> (coalesce(e.nilai_pendapatan, 0::bigint) + coalesce(e.pendapatan_lain, 0::bigint)) as flag_pendapatan,
  e.gaji,
  e.biaya_produksi,
  e.operasional,
  e.total_pengeluaran,
  coalesce(e.gaji, 0::bigint) + coalesce(e.biaya_produksi, 0::bigint) + coalesce(e.operasional, 0::bigint) as total_pengeluaran_hitung,
  e.total_pengeluaran <> (coalesce(e.gaji, 0::bigint) + coalesce(e.biaya_produksi, 0::bigint) + coalesce(e.operasional, 0::bigint)) as flag_pengeluaran,
  coalesce(e.pendapatan_online, 0::bigint) > 0 and e.internet_pesanan = '2'::text as flag_online_vs_internet,
  e.aset_usaha,
  e.aset_lain,
  e.total_aset,
  e.luas_tanah,
  coalesce(e.aset_usaha, 0::bigint) + coalesce(e.aset_lain, 0::bigint) as total_aset_hitung,
  e.total_aset <> (coalesce(e.aset_usaha, 0::bigint) + coalesce(e.aset_lain, 0::bigint)) as flag_aset,
  e.internet,
  e.internet_pesanan,
  e.digital,
  e.latitude,
  e.longitude,
  e.kode_wilayah,
  e.source_modified_at,
  e.detail_fetched_at,
  e.created_at,
  e.updated_at
from extracted e;

create unique index if not exists mv_fasih_assignment_summary_id_idx
on public.mv_fasih_assignment_summary using btree (id);

create index if not exists mv_fasih_assignment_summary_survey_period_id_idx
on public.mv_fasih_assignment_summary using btree (survey_period_id);

create index if not exists mv_fasih_assignment_summary_kecamatan_idx
on public.mv_fasih_assignment_summary using btree (kecamatan);

create index if not exists mv_fasih_assignment_summary_desa_idx
on public.mv_fasih_assignment_summary using btree (desa);

create index if not exists mv_fasih_assignment_summary_status_alias_idx
on public.mv_fasih_assignment_summary using btree (status_alias);

create index if not exists mv_fasih_assignment_summary_kode_wilayah_idx
on public.mv_fasih_assignment_summary using btree (kode_wilayah);

create index if not exists mv_fasih_assignment_summary_source_modified_at_idx
on public.mv_fasih_assignment_summary using btree (source_modified_at desc);

create index if not exists mv_fasih_assignment_summary_kode_wilayah_modified_idx
on public.mv_fasih_assignment_summary using btree (kode_wilayah, source_modified_at desc);

drop function if exists public.get_assignment_places_for_current_user(
  text,
  timestamp with time zone
);

create function public.get_assignment_places_for_current_user(
  p_sync_mode text,
  p_modified_after timestamp with time zone default null
)
returns table (
  assignment_id text,
  no_bang integer,
  nama_usaha text,
  latitude numeric,
  longitude numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_user_id uuid;
  v_petugas_id uuid;
  v_role text;
  v_is_active boolean := false;
begin
  if p_sync_mode not in ('full', 'incremental') then
    raise exception 'Invalid sync mode: %', p_sync_mode
      using errcode = '22023';
  end if;

  if v_auth_uid is null then
    return;
  end if;

  select u.id
    into v_user_id
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

  if v_petugas_id is null or not v_is_active then
    return;
  end if;

  if v_role = 'admin' then
    return query
    select
      mv.assignment_id,
      mv.no_bang,
      mv.nama_usaha,
      mv.latitude,
      mv.longitude
    from public.mv_fasih_assignment_summary mv
    where
      mv.latitude is not null
      and mv.longitude is not null
      and mv.latitude between -90 and 90
      and mv.longitude between -180 and 180
      and (
        p_sync_mode = 'full'
        or p_modified_after is null
        or mv.source_modified_at > p_modified_after
      );
    return;
  end if;

  if v_role not in ('pengawas', 'pendata') then
    return;
  end if;

  return query
  with wilayah_scope as (
    select distinct wt.id as kode_wilayah
    from public.se2026_wilayah_tugas wt
    where (
      v_role = 'pengawas' and wt.pml_id = v_petugas_id
    ) or (
      v_role = 'pendata' and wt.ppl_id = v_petugas_id
    )
  )
  select distinct
    mv.assignment_id,
    mv.no_bang,
    mv.nama_usaha,
    mv.latitude,
    mv.longitude
  from public.mv_fasih_assignment_summary mv
  join wilayah_scope ws
    on mv.kode_wilayah = ws.kode_wilayah
  where
    mv.latitude is not null
    and mv.longitude is not null
    and mv.latitude between -90 and 90
    and mv.longitude between -180 and 180
    and (
      p_sync_mode = 'full'
      or p_modified_after is null
      or mv.source_modified_at > p_modified_after
    );
end;
$$;

grant execute on function public.get_assignment_places_for_current_user(text, timestamp with time zone) to authenticated;
