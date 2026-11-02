-- Skill Link Worldwide private messaging. Run once in Supabase SQL Editor.
create table if not exists public.conversations (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id) on delete cascade,
 provider_id uuid not null references public.provider_profiles(user_id) on delete cascade,
 created_at timestamptz not null default now(),
 unique(customer_id,provider_id),
 check(customer_id <> provider_id)
);
create table if not exists public.messages (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(btrim(body)) between 1 and 2000),
 created_at timestamptz not null default now()
);
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
revoke all on public.conversations, public.messages from anon;
grant select,insert on public.conversations,public.messages to authenticated;
drop policy if exists "Participants view conversations" on public.conversations;
create policy "Participants view conversations" on public.conversations for select to authenticated
using ((select auth.uid()) in (customer_id,provider_id));
drop policy if exists "Customers start conversations" on public.conversations;
create policy "Customers start conversations" on public.conversations for insert to authenticated
with check (customer_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='customer'));
drop policy if exists "Participants view messages" on public.messages;
create policy "Participants view messages" on public.messages for select to authenticated
using(exists(select 1 from public.conversations c where c.id=conversation_id and (select auth.uid()) in(c.customer_id,c.provider_id)));
drop policy if exists "Participants send messages" on public.messages;
create policy "Participants send messages" on public.messages for insert to authenticated
with check(sender_id=(select auth.uid()) and exists(select 1 from public.conversations c where c.id=conversation_id and (select auth.uid()) in(c.customer_id,c.provider_id)));
-- Conversation rows and messages cannot be updated or deleted by browser clients.
