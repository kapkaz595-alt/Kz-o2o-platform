create table review_reports (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references reviews(id),
  reported_by uuid not null references public.users(id),
  reason report_reason not null,
  detail text,
  status report_status not null default 'pending',
  resolved_by uuid references public.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index uq_review_reports_review_user
  on review_reports(review_id, reported_by);
create index idx_review_reports_status on review_reports(status);

create or replace function increment_report_count()
returns trigger language plpgsql security definer as $function$
begin
  update reviews set report_count = report_count + 1 where id = new.review_id;
  return new;
end;
$function$;
create trigger trg_increment_report_count
  after insert on review_reports for each row execute function increment_report_count();

create table review_reactions (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references reviews(id),
  user_id uuid not null references public.users(id),
  reaction reaction_type not null,
  created_at timestamptz not null default now()
);
create unique index uq_review_reactions_review_user
  on review_reactions(review_id, user_id);

create or replace function sync_review_reaction_counts()
returns trigger language plpgsql security definer as $function$
begin
  if (tg_op = 'INSERT') then
    if new.reaction = 'helpful' then
      update reviews set helpful_count = helpful_count + 1 where id = new.review_id;
    else
      update reviews set unhelpful_count = unhelpful_count + 1 where id = new.review_id;
    end if;
  elsif (tg_op = 'DELETE') then
    if old.reaction = 'helpful' then
      update reviews set helpful_count = greatest(helpful_count - 1, 0) where id = old.review_id;
    else
      update reviews set unhelpful_count = greatest(unhelpful_count - 1, 0) where id = old.review_id;
    end if;
  end if;
  return null;
end;
$function$;
create trigger trg_sync_review_reaction_counts
  after insert or delete on review_reactions
  for each row execute function sync_review_reaction_counts();