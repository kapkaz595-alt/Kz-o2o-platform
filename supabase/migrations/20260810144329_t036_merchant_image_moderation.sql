-- 1. 补齐 merchant_images 缺失字段
alter table public.merchant_images
  add column if not exists display_order integer not null default 0,
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz;

-- 2. status 字段由 text 转为 claim_request_status 枚举
alter table public.merchant_images
  alter column status drop default;

alter table public.merchant_images
  alter column status type claim_request_status
  using status::claim_request_status;

alter table public.merchant_images
  alter column status set default 'pending';

-- 3. 索引
create index if not exists idx_merchant_images_merchant_id
  on public.merchant_images(merchant_id) where is_deleted = false;
create index if not exists idx_merchant_images_status
  on public.merchant_images(status);
create index if not exists idx_moderation_queue_target
  on public.moderation_queue(target_type, target_id);
create index if not exists idx_moderation_queue_status_pending
  on public.moderation_queue(status) where status = 'pending';

-- 4. 图片入队审核（避免已有记录重复触发，先drop再建）
drop trigger if exists trg_enqueue_merchant_image_moderation on public.merchant_images;

create or replace function public.enqueue_merchant_image_moderation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.moderation_queue (target_type, target_id, source, status)
  values ('merchant_image', new.id, 'merchant_upload', 'pending');
  return new;
end;
$$;

create trigger trg_enqueue_merchant_image_moderation
after insert on public.merchant_images
for each row execute function public.enqueue_merchant_image_moderation();

-- 5. 审核结果回写 merchant_images.status
drop trigger if exists trg_sync_moderation_result_to_image on public.moderation_queue;

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
  return new;
end;
$$;

create trigger trg_sync_moderation_result_to_image
after update on public.moderation_queue
for each row execute function public.sync_moderation_result_to_image();

-- 6. merchant_images 变化同步到 merchants.images 缓存数组
drop trigger if exists trg_sync_merchant_images_array on public.merchant_images;

create or replace function public.sync_merchant_images_array()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_merchant_id uuid := coalesce(new.merchant_id, old.merchant_id);
begin
  update public.merchants
  set images = coalesce((
        select array_agg(url order by display_order, created_at)
        from public.merchant_images
        where merchant_id = v_merchant_id
          and status = 'approved' and is_deleted = false
      ), '{}'),
      updated_at = now()
  where id = v_merchant_id;
  return new;
end;
$$;

create trigger trg_sync_merchant_images_array
after insert or update or delete on public.merchant_images
for each row execute function public.sync_merchant_images_array();

-- 7. RLS
alter table public.merchant_images enable row level security;

drop policy if exists merchant_images_select_public on public.merchant_images;
create policy merchant_images_select_public
on public.merchant_images for select
using (
  (status = 'approved' and is_deleted = false)
  or exists (select 1 from public.merchants m
             where m.id = merchant_images.merchant_id and m.owner_id = auth.uid())
  or public.get_user_role(auth.uid()) in ('moderator','super_admin')
);

drop policy if exists merchant_images_insert_owner_or_staff on public.merchant_images;
create policy merchant_images_insert_owner_or_staff
on public.merchant_images for insert
with check (
  uploaded_by = auth.uid()
  and (
    exists (select 1 from public.merchants m
            where m.id = merchant_images.merchant_id
              and m.owner_id = auth.uid() and m.status = 'claimed')
    or public.get_user_role(auth.uid()) in ('moderator','super_admin')
  )
);

drop policy if exists merchant_images_update_staff_only on public.merchant_images;
create policy merchant_images_update_staff_only
on public.merchant_images for update
using (public.get_user_role(auth.uid()) in ('moderator','super_admin'));

drop policy if exists merchant_images_delete_staff_or_owner on public.merchant_images;
create policy merchant_images_delete_staff_or_owner
on public.merchant_images for delete
using (
  public.get_user_role(auth.uid()) in ('moderator','super_admin')
  or exists (select 1 from public.merchants m
             where m.id = merchant_images.merchant_id and m.owner_id = auth.uid())
);

alter table public.moderation_queue enable row level security;

drop policy if exists moderation_queue_select_staff on public.moderation_queue;
create policy moderation_queue_select_staff
on public.moderation_queue for select
using (public.get_user_role(auth.uid()) in ('moderator','super_admin'));

drop policy if exists moderation_queue_update_staff on public.moderation_queue;
create policy moderation_queue_update_staff
on public.moderation_queue for update
using (public.get_user_role(auth.uid()) in ('moderator','super_admin'));