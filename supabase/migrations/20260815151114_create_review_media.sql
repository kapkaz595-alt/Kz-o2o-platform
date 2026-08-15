create table review_media (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references reviews(id),
  url text not null,
  storage_path text not null,
  status claim_request_status not null default 'pending',
  display_order int not null default 0,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_review_media_review_id on review_media(review_id);
create index idx_review_media_status on review_media(status);

create trigger trg_review_media_updated_at
  before update on review_media for each row execute function set_updated_at();
create trigger trg_review_media_to_moderation
  after insert on review_media for each row execute function enqueue_moderation('review_media');