create type merchant_report_reason as enum ('closed', 'fake', 'duplicate', 'wrong_info', 'offensive', 'other');

create table merchant_reports (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants(id),
  reported_by uuid not null references public.users(id),
  reason merchant_report_reason not null,
  detail text,
  status report_status not null default 'pending',
  resolved_by uuid references public.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index uq_merchant_reports_merchant_user
  on merchant_reports(merchant_id, reported_by);
create index idx_merchant_reports_status on merchant_reports(status);

alter table merchants add column if not exists report_count integer not null default 0;

create or replace function increment_merchant_report_count()
returns trigger language plpgsql security definer as $function$
begin
  update merchants set report_count = report_count + 1 where id = new.merchant_id;
  return new;
end;
$function$;

create trigger trg_increment_merchant_report_count
  after insert on merchant_reports for each row execute function increment_merchant_report_count();

alter table merchant_reports enable row level security;

create policy merchant_reports_insert_own on merchant_reports
  for insert with check (reported_by = auth.uid());

create policy merchant_reports_select_own_or_admin on merchant_reports
  for select using (
    reported_by = auth.uid()
    or public.get_user_role(auth.uid()) in ('moderator', 'super_admin')
  );