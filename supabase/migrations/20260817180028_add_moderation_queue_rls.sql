alter table moderation_queue enable row level security;

create policy moderation_queue_select_staff on moderation_queue
  for select using (
    public.get_user_role(auth.uid()) in ('moderator', 'super_admin')
  );

create policy moderation_queue_update_staff on moderation_queue
  for update using (
    public.get_user_role(auth.uid()) in ('moderator', 'super_admin')
  );