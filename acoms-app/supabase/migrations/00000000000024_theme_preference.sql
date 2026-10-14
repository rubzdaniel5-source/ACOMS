-- 024: per-user theme preference (ACOMS-DESIGN-001 s4.1, account-synchronised).
-- Direct writes to user_profiles are closed (migration 018), so the user changes
-- only this one column through a SECURITY DEFINER function scoped to their own row.

alter table user_profiles
  add column if not exists theme_preference text
  check (theme_preference in ('light', 'dark', 'system'));

comment on column user_profiles.theme_preference is
  'UI theme: light (Aero Blue), dark (Slate Modern) or system. NULL = never chosen; the app defaults to light.';

create or replace function set_my_theme_preference(p_theme text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  if p_theme is null or p_theme not in ('light', 'dark', 'system') then
    raise exception 'Invalid theme: %', p_theme;
  end if;

  update user_profiles set theme_preference = p_theme where id = auth.uid();
end;
$$;

revoke all on function set_my_theme_preference(text) from public, anon;
grant execute on function set_my_theme_preference(text) to authenticated;
