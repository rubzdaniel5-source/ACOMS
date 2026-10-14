-- Test helpers. Tests run as a superuser connection and switch into the
-- 'authenticated' role (exactly what Supabase does for a signed-in user).
create schema test;
grant usage on schema test to public;

create table test.results (n serial primary key, file text, ok boolean not null, msg text not null);
create table test.users (name text primary key, id uuid not null);
grant all on test.results, test.users to public;
grant usage on all sequences in schema test to public;

-- Become a named fixture user (RLS and auth.uid() apply from here on).
create function test.as_user(p_name text) returns void language plpgsql as $$
declare v_id uuid;
begin
  reset role;
  select id into v_id from test.users where name = p_name;
  if v_id is null then raise exception 'test fixture user % not found', p_name; end if;
  perform set_config('request.jwt.claim.sub', v_id::text, false);
  set role authenticated;
end $$;

-- Signed-out visitor.
create function test.as_anon() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', false);
  set role anon;
end $$;

-- Back to the superuser for checking raw state.
create function test.as_root() returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', '', false); end $$;

create function test.uid(p_name text) returns uuid language sql as $$ select id from test.users where name = p_name $$;
create function test.st(p_code text) returns uuid language sql as $$ select id from public.stations where code = p_code $$;
create function test.eq(p_code text) returns uuid language sql as $$ select id from public.equipment_types where source_code = p_code $$;
create function test.role(p_code text) returns uuid language sql as $$ select id from public.roles where code = p_code $$;

-- Record a check. Always passes through root so the insert cannot be blocked.
create function test.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  insert into test.results (ok, msg) values (coalesce(p_cond, false), p_msg);
  raise notice '% %', case when coalesce(p_cond, false) then 'ok   ' else 'FAIL ' end, p_msg;
end $$;

create function test.eq_int(p_actual bigint, p_expected bigint, p_msg text) returns void language plpgsql as $$
begin
  perform test.ok(p_actual is not distinct from p_expected,
    p_msg || case when p_actual is not distinct from p_expected then '' else format(' (expected %s, got %s)', p_expected, p_actual) end);
end $$;

-- Run SQL and require it to raise an error whose message matches the pattern.
create function test.fails(p_sql text, p_pattern text, p_msg text) returns void language plpgsql as $$
declare v_err text;
begin
  begin
    execute p_sql;
  exception when others then v_err := sqlerrm;
  end;
  if v_err is null then
    perform test.ok(false, p_msg || ' (expected an error, none raised)');
  elsif v_err ilike '%' || p_pattern || '%' then
    perform test.ok(true, p_msg);
  else
    perform test.ok(false, p_msg || ' (wrong error: ' || v_err || ')');
  end if;
end $$;

-- Run SQL and require that it succeeds.
create function test.works(p_sql text, p_msg text) returns void language plpgsql as $$
declare v_err text;
begin
  begin execute p_sql; exception when others then v_err := sqlerrm; end;
  perform test.ok(v_err is null, p_msg || coalesce(' (raised: ' || v_err || ')', ''));
end $$;

create function test.avail(p_station text, p_equipment text) returns integer language sql as $$
  select coalesce((select available_quantity from public.inventory_balances
    where station_id = test.st(p_station) and equipment_type_id = test.eq(p_equipment)), 0) $$;
create function test.bal(p_station text, p_equipment text, p_col text) returns integer language plpgsql as $$
declare v integer;
begin
  execute format('select coalesce((select %I from public.inventory_balances where station_id = $1 and equipment_type_id = $2), 0)', p_col)
    into v using test.st(p_station), test.eq(p_equipment);
  return v;
end $$;

-- Fails the run (and prints a summary) if any check failed.
create function test.finish(p_file text) returns void language plpgsql as $$
declare v_fail integer; v_total integer;
begin
  perform test.as_root();
  select count(*) filter (where not ok), count(*) into v_fail, v_total from test.results;
  raise notice '--- % checks so far, % failed', v_total, v_fail;
  if v_fail > 0 then raise exception 'FAILED: % check(s) in %', v_fail, p_file; end if;
end $$;

-- Scratch variables shared across checks (ids of records created by a test).
create table test.vars (k text primary key, v uuid);
grant all on test.vars to public;
create function test.put(p_k text, p_v uuid) returns void language sql as
  $$ insert into test.vars values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function test.get(p_k text) returns uuid language sql as $$ select v from test.vars where k = p_k $$;
-- Id of a transfer line for an equipment code.
create function test.line(p_transfer text, p_equipment text) returns uuid language sql as
  $$ select id from public.equipment_transfer_items where transfer_id = test.get(p_transfer) and equipment_type_id = test.eq(p_equipment) $$;
create function test.status(p_transfer text) returns text language sql as
  $$ select status from public.equipment_transfers where id = test.get(p_transfer) $$;

-- A check for a bug we know about and have reported but not fixed yet. It never
-- fails the run; when the bug is fixed it says so, so the check can be promoted.
create function test.known(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  raise notice '%', case when coalesce(p_cond, false) then 'FIXED (promote to a normal check): ' else 'known issue: ' end || p_msg;
end $$;

-- Would this statement succeed? Always rolled back, so it leaves no trace.
create function test.probe(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  raise exception 'probe-rollback';
exception when others then
  return sqlerrm = 'probe-rollback';
end $$;
