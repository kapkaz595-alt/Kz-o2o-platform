alter table public.moderation_queue drop constraint moderation_queue_source_check;

alter table public.moderation_queue add constraint moderation_queue_source_check
  check (source = any (array[
    'report'::text,
    'auto_detect'::text,
    'claim_request'::text,
    'merchant_edit'::text,
    'merchant_upload'::text,
    'user_submission'::text
  ]));