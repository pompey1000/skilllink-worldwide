-- Optional worker credential / experience category. Does not verify licensing.
alter table public.provider_profiles
add column if not exists credential_type text not null default 'not_specified';
alter table public.provider_profiles
drop constraint if exists provider_profiles_credential_type_check;
alter table public.provider_profiles
add constraint provider_profiles_credential_type_check
check (credential_type in ('not_specified','licensed_self_reported','experienced_unlicensed','apprentice'));
comment on column public.provider_profiles.credential_type is 'Self-reported worker status only; not license verification or legal authorization.';
