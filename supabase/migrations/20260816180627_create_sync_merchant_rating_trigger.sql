create or replace function public.sync_merchant_rating()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_merchant_id uuid := coalesce(new.merchant_id, old.merchant_id);
begin
  update public.merchants
  set rating_avg = coalesce((
        select round(avg(rating)::numeric, 2)
        from public.reviews
        where merchant_id = v_merchant_id
          and status = 'approved'
          and is_deleted = false
      ), 0),
      review_count = (
        select count(*)
        from public.reviews
        where merchant_id = v_merchant_id
          and status = 'approved'
          and is_deleted = false
      ),
      updated_at = now()
  where id = v_merchant_id;

  return null;
end;
$$;

create trigger trg_sync_merchant_rating_insert
  after insert on public.reviews
  for each row execute function sync_merchant_rating();

create trigger trg_sync_merchant_rating_update
  after update on public.reviews
  for each row
  when (
    new.status is distinct from old.status
    or new.rating is distinct from old.rating
    or new.is_deleted is distinct from old.is_deleted
  )
  execute function sync_merchant_rating();

create trigger trg_sync_merchant_rating_delete
  after delete on public.reviews
  for each row execute function sync_merchant_rating();