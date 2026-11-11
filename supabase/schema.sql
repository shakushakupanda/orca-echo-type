-- Orca echo みんなの配列 : Supabase schema
-- Supabase の SQL Editor にそのまま貼って Run してください。

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.keymaps (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  name        text not null check (char_length(btrim(name)) between 1 and 30),
  comment     text not null default '' check (char_length(comment) <= 200),
  host        text not null default 'us' check (host in ('us', 'jis')),
  -- 4段×14列のキーコード（Launcher の val）をレイヤーごとに並べた配列: [[56個], [56個], ...]
  layers      jsonb not null check (
                jsonb_typeof(layers) = 'array'
                and jsonb_array_length(layers) between 1 and 8
                and octet_length(layers::text) < 20000
              ),
  -- 削除用の合言葉の SHA-256（合言葉そのものは投稿したブラウザにだけ残る）
  delete_hash text not null check (char_length(delete_hash) = 64)
);

create index if not exists keymaps_created_at_idx on public.keymaps (created_at desc);

alter table public.keymaps enable row level security;

drop policy if exists "keymaps are readable by everyone" on public.keymaps;
create policy "keymaps are readable by everyone"
  on public.keymaps for select
  to anon, authenticated
  using (true);

drop policy if exists "anyone can submit a keymap" on public.keymaps;
create policy "anyone can submit a keymap"
  on public.keymaps for insert
  to anon, authenticated
  with check (true);

-- 列単位の権限: 読めるのは公開してよい列だけ、書けるのは投稿内容の列だけ。
revoke all on public.keymaps from anon, authenticated;
grant select (id, created_at, name, comment, host, layers) on public.keymaps to anon, authenticated;
grant insert (name, comment, host, layers, delete_hash) on public.keymaps to anon, authenticated;

-- 削除: 合言葉が一致したときだけ消える
create or replace function public.delete_keymap(p_id uuid, p_token text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  n integer;
begin
  delete from public.keymaps
   where id = p_id
     and delete_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

revoke all on function public.delete_keymap(uuid, text) from public;
grant execute on function public.delete_keymap(uuid, text) to anon, authenticated;

-- 2026-11-11 追加: コンボ・マクロ・長押しキーの中身を保存する欄
alter table public.keymaps
  add column if not exists extra jsonb not null default '{}'::jsonb;
alter table public.keymaps drop constraint if exists keymaps_extra_check;
alter table public.keymaps add constraint keymaps_extra_check
  check (jsonb_typeof(extra) = 'object' and octet_length(extra::text) < 20000);
grant select (extra) on public.keymaps to anon, authenticated;
grant insert (extra) on public.keymaps to anon, authenticated;
