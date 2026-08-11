-- supabase/migrations/<timestamp>_claim_proofs_storage_policies.sql

-- claim-proofs 桶已在阶段一建为 Private，此处补充 RLS 策略
CREATE POLICY "claim_proofs_insert_own"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'claim-proofs'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

CREATE POLICY "claim_proofs_select_own_or_admin"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'claim-proofs'
    AND (
      (storage.foldername(name))[2] = auth.uid()::text
      OR public.get_user_role(auth.uid()) IN ('moderator', 'super_admin')
    )
  );