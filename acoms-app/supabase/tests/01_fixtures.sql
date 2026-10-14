-- Fixture users: one per role and scope, plus an outsider and a deactivated user.
do $$
declare
  v_org uuid := (select id from organizations where code = 'UGANDA_AIRLINES');
  r record;
begin
  for r in select * from (values
    ('admin',     'system_admin',                  null),
    ('mgr_ebb',   'station_manager',               'EBB'),
    ('mgr_abj',   'station_manager',               'ABJ'),
    ('sup_ebb',   'catering_supervisor',           'EBB'),
    ('cm_ebb',    'catering_manager',              'EBB'),
    ('asst_ebb',  'catering_assistant_base',       'EBB'),
    ('asst_abj',  'catering_assistant_outstation', 'ABJ'),
    ('stores_ebb','stores_officer',                'EBB'),
    ('outsider',  null,                            null),
    ('inactive',  'station_manager',               'EBB')
  ) as t(name, role_code, station_code)
  loop
    insert into test.users (name, id) values (r.name, gen_random_uuid());
    insert into auth.users (id, email) values (test.uid(r.name), r.name || '@test.local');
    insert into user_profiles (id, organization_id, full_name, email, is_active)
      values (test.uid(r.name), v_org, initcap(r.name), r.name || '@test.local', r.name <> 'inactive');
    if r.role_code is not null then
      insert into user_roles (user_id, role_id, station_id)
        values (test.uid(r.name), test.role(r.role_code), case when r.station_code is null then null else test.st(r.station_code) end);
    end if;
  end loop;
end $$;
select test.ok((select count(*) from test.users) = 10, 'fixtures: 10 users created');
