create or replace function public.sync_merchant_favorite_count()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_merchant_id uuid := coalesce(new.merchant_id, old.merchant_id);
begin
  update public.merchants
  set favorite_count = (
        select count(*) from public.favorites where merchant_id = v_merchant_id
      ),
      updated_at = now()
  where id = v_merchant_id;

  return null;
end;
$$;

create trigger trg_sync_favorite_count_insert
  after insert on public.favorites
  for each row execute function sync_merchant_favorite_count();

create trigger trg_sync_favorite_count_delete
  after delete on public.favorites
  for each row execute function sync_merchant_favorite_count();