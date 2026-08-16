drop table if exists reviews cascade;

create table reviews (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants(id),
  user_id uuid not null references public.users(id),
  rating smallint not null check (rating between 1 and 5),
  content text not null check (char_length(content) between 5 and 2000),
  status review_status not null default 'pending',
  is_edited boolean not null default false,
  edit_count int not null default 0,
  version int not null default 1,
  helpful_count int not null default 0,
  unhelpful_count int not null default 0,
  report_count int not null default 0,
  reviewer_id uuid references public.users(id),
  review_note text,
  reviewed_at timestamptz,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index uq_reviews_merchant_user
  on reviews(merchant_id, user_id) where is_deleted = false;
create index idx_reviews_merchant_id on reviews(merchant_id);
create index idx_reviews_user_id on reviews(user_id);
create index idx_reviews_status on reviews(status) where status = 'approved';

create trigger trg_reviews_updated_at
  before update on reviews for each row execute function set_updated_at();

create table review_revisions (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references reviews(id),
  rating smallint not null,
  content text not null,
  edited_by uuid not null references public.users(id),
  created_at timestamptz not null default now()
);
create index idx_review_revisions_review_id on review_revisions(review_id);

create or replace function snapshot_review_revision()
returns trigger language plpgsql security definer as $function$
begin
  if (new.rating is distinct from old.rating or new.content is distinct from old.content) then
    insert into review_revisions (review_id, rating, content, edited_by)
    values (old.id, old.rating, old.content, auth.uid());
    new.is_edited := true;
    new.edit_count := old.edit_count + 1;
    new.version := old.version + 1;
    new.status := 'pending';
    new.reviewed_at := null;
    new.reviewer_id := null;
  end if;
  return new;
end;
$function$;

create trigger trg_snapshot_review_revision
  before update on reviews for each row execute function snapshot_review_revision();

create or replace function public.enqueue_review_moderation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.moderation_queue (target_type, target_id, source, status)
  values ('review', new.id, 'user_submission', 'pending');
  return new;
end;
$$;

create trigger trg_reviews_to_moderation
  after insert on reviews for each row execute function enqueue_review_moderation();

  create or replace function public.sync_moderation_result_to_image()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.target_type = 'merchant_image'
     and new.status in ('approved','rejected')
     and new.status is distinct from old.status then
    update public.merchant_images
    set status = new.status, updated_at = now()
    where id = new.target_id;
  end if;

  if new.target_type = 'review'
     and new.status in ('approved','rejected')
     and new.status is distinct from old.status then
    update public.reviews
    set status = new.status,
        reviewer_id = new.assigned_to,
        review_note = new.resolution_note,
        reviewed_at = coalesce(new.resolved_at, now())
    where id = new.target_id;
  end if;

  return new;
end;
$$;