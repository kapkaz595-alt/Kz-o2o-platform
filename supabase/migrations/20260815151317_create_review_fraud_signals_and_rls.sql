create table review_fraud_signals (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references reviews(id),
  signal_type text not null,
  severity smallint not null check (severity between 1 and 3),
  details jsonb,
  created_at timestamptz not null default now()
);
create index idx_review_fraud_signals_review_id on review_fraud_signals(review_id);
create index idx_review_fraud_signals_type on review_fraud_signals(signal_type);

alter table reviews enable row level security;
alter table review_revisions enable row level security;
alter table review_media enable row level security;
alter table review_reports enable row level security;
alter table review_reactions enable row level security;
alter table review_fraud_signals enable row level security;

create policy reviews_select_approved on reviews for select
  using (status = 'approved' and is_deleted = false);
create policy reviews_select_own on reviews for select
  using (auth.uid() = user_id);
create policy reviews_select_moderator on reviews for select
  using (public.get_user_role(auth.uid()) in ('moderator', 'super_admin'));
create policy reviews_insert_own on reviews for insert
  with check (auth.uid() = user_id);
create policy reviews_update_own on reviews for update
  using (auth.uid() = user_id and is_deleted = false);
create policy reviews_update_moderator on reviews for update
  using (public.get_user_role(auth.uid()) in ('moderator', 'super_admin'));

create policy review_revisions_select_own on review_revisions for select
  using (auth.uid() = (select user_id from reviews where id = review_id));
create policy review_revisions_select_moderator on review_revisions for select
  using (public.get_user_role(auth.uid()) in ('moderator', 'super_admin'));

create policy review_media_select_public on review_media for select
  using (status = 'approved');
create policy review_media_select_own on review_media for select
  using (auth.uid() = (select user_id from reviews where id = review_id));
create policy review_media_insert_own on review_media for insert
  with check (auth.uid() = (select user_id from reviews where id = review_id));
create policy review_media_moderator_all on review_media for all
  using (public.get_user_role(auth.uid()) in ('moderator', 'super_admin'));

create policy review_reports_insert_authenticated on review_reports for insert
  with check (auth.uid() = reported_by);
create policy review_reports_select_own on review_reports for select
  using (auth.uid() = reported_by);
create policy review_reports_select_moderator on review_reports for select
  using (public.get_user_role(auth.uid()) in ('moderator', 'super_admin'));
create policy review_reports_update_moderator on review_reports for update
  using (public.get_user_role(auth.uid()) in ('moderator', 'super_admin'));

create policy review_reactions_select_public on review_reactions for select
  using (true);
create policy review_reactions_insert_own on review_reactions for insert
  with check (auth.uid() = user_id);
create policy review_reactions_delete_own on review_reactions for delete
  using (auth.uid() = user_id);

-- review_fraud_signals: 无面向普通用户的策略，默认RLS拒绝一切客户端直接访问
-- 仅允许 SECURITY DEFINER 函数或 service_role 写入/读取