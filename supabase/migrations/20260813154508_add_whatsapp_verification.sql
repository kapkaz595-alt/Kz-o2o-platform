-- migration: add_whatsapp_verification.sql

-- merchants表新增验证状态字段
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS whatsapp_verified BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS whatsapp_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS whatsapp_verified_by UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS whatsapp_verification_method TEXT DEFAULT 'manual'
    CHECK (whatsapp_verification_method IN ('manual', 'api'));

-- E.164格式校验函数（正则：+ 后跟1-15位数字）
CREATE OR REPLACE FUNCTION public.is_valid_e164(phone TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT phone ~ '^\+[1-9]\d{1,14}$';
$$;

-- 数据库层兜底约束：whatsapp_number非空时必须符合E.164
ALTER TABLE public.merchants
  ADD CONSTRAINT chk_whatsapp_e164
  CHECK (whatsapp_number IS NULL OR public.is_valid_e164(whatsapp_number));

-- 认领审核动作追加：审核通过时可选同步勾选whatsapp_verified
-- （复用T039的approve_claim_request函数，增加一个可选参数）
CREATE OR REPLACE FUNCTION public.approve_claim_request(
  p_request_id UUID,
  p_reviewer_id UUID,
  p_review_note TEXT DEFAULT NULL,
  p_verify_whatsapp BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_merchant_id UUID;
  v_user_id UUID;
BEGIN
  SELECT merchant_id, submitted_by INTO v_merchant_id, v_user_id
  FROM public.merchant_claim_requests
  WHERE id = p_request_id AND status = 'pending';

  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'Claim request not found or already processed';
  END IF;

  UPDATE public.merchant_claim_requests
  SET status = 'approved',
      reviewer_id = p_reviewer_id,
      review_note = p_review_note,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  UPDATE public.merchants
  SET claim_status = 'claimed',
      owner_id = v_user_id,
      whatsapp_verified = CASE WHEN p_verify_whatsapp THEN true ELSE whatsapp_verified END,
      whatsapp_verified_at = CASE WHEN p_verify_whatsapp THEN now() ELSE whatsapp_verified_at END,
      whatsapp_verified_by = CASE WHEN p_verify_whatsapp THEN p_reviewer_id ELSE whatsapp_verified_by END,
      updated_at = now()
  WHERE id = v_merchant_id;

  INSERT INTO public.merchant_member_roles (merchant_id, user_id, role)
  VALUES (v_merchant_id, v_user_id, 'owner')
  ON CONFLICT (merchant_id, user_id) DO UPDATE SET role = 'owner';
END;
$$;