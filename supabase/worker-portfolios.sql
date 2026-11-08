-- Skill Link Worldwide: public work portfolios (only upload photos you own/have permission to publish)
create table if not exists public.portfolio_photos (
 id uuid primary key default gen_random_uuid(),
 provider_id uuid not null references public.provider_profiles(user_id) on delete cascade,
 storage_path text not null unique,
 caption text not null default '' check (char_length(caption)<=180),
 created_at timestamptz not null default now(),
 constraint portfolio_path_owner check (storage_path like provider_id::text || '/%')
);
alter table public.portfolio_photos enable row level security;
grant select,insert,delete on public.portfolio_photos to authenticated;
grant select on public.portfolio_photos to anon;
drop policy if exists "Anyone can view portfolio photos" on public.portfolio_photos;
create policy "Anyone can view portfolio photos" on public.portfolio_photos for select to anon,authenticated using (true);
drop policy if exists "Provider can add own photos" on public.portfolio_photos;
create policy "Provider can add own photos" on public.portfolio_photos for insert to authenticated with check (provider_id=(select auth.uid()));
drop policy if exists "Provider can delete own photos" on public.portfolio_photos;
create policy "Provider can delete own photos" on public.portfolio_photos for delete to authenticated using (provider_id=(select auth.uid()));
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('worker-portfolios','worker-portfolios',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "Public read worker portfolio images" on storage.objects;
create policy "Public read worker portfolio images" on storage.objects for select to anon,authenticated using (bucket_id='worker-portfolios');
drop policy if exists "Providers upload to own folder" on storage.objects;
create policy "Providers upload to own folder" on storage.objects for insert to authenticated with check (
 bucket_id='worker-portfolios' and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists(select 1 from public.provider_profiles p where p.user_id=(select auth.uid()))
);
drop policy if exists "Providers remove own images" on storage.objects;
create policy "Providers remove own images" on storage.objects for delete to authenticated using (
 bucket_id='worker-portfolios' and (storage.foldername(name))[1]=(select auth.uid())::text
);
