-- supabase/migrations/<timestamp>_create_merchant_claim_requests.sql

-- 复用已存在的 claim_request_status 枚举 (pending/approved/rejected)，无需重建
DROP TABLE IF EXISTS public.merchant_claim_requests CASCADE;

CREATE TABLE public.merchant_claim_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES public.merchants(id),
  submitted_by UUID NOT NULL REFERENCES public.users(id),
  bin_iin TEXT NOT NULL,
  business_license_number TEXT,
  contact_name TEXT NOT NULL,
  contact_phone TEXT NOT NULL,
  proof_files TEXT[] NOT NULL DEFAULT '{}',
  status claim_request_status NOT NULL DEFAULT 'pending',
  reviewer_id UUID REFERENCES public.users(id),
  review_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  deleted_at TIMESTAMPTZ
);

-- 索引
CREATE INDEX idx_merchant_claim_requests_merchant_id
  ON public.merchant_claim_requests (merchant_id);
CREATE INDEX idx_merchant_claim_requests_submitted_by
  ON public.merchant_claim_requests (submitted_by);
CREATE INDEX idx_merchant_claim_requests_status
  ON public.merchant_claim_requests (status)
  WHERE is_deleted = false;

-- 同一商家只允许一条待审 pending 申请
CREATE UNIQUE INDEX uq_merchant_claim_requests_pending
  ON public.merchant_claim_requests (merchant_id)
  WHERE status = 'pending' AND is_deleted = false;

-- updated_at 自动维护（复用项目已有的公共触发器函数 set_updated_at，若不存在则新建）
CREATE TRIGGER trg_merchant_claim_requests_updated_at
  BEFORE UPDATE ON public.merchant_claim_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 提交申请后，联动 merchants.claim_status -> claim_pending
CREATE OR REPLACE FUNCTION public.handle_new_claim_request()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.merchants
  SET claim_status = 'claim_pending',
      updated_at = now()
  WHERE id = NEW.merchant_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER trg_after_insert_claim_request
  AFTER INSERT ON public.merchant_claim_requests
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_claim_request();

  ALTER TABLE public.merchant_claim_requests ENABLE ROW LEVEL SECURITY;

-- 提交者可插入自己的申请
CREATE POLICY "claim_requests_insert_own"
  ON public.merchant_claim_requests FOR INSERT TO authenticated
  WITH CHECK (submitted_by = auth.uid());

-- 提交者可查看自己的申请；管理员可查看全部
CREATE POLICY "claim_requests_select_own_or_admin"
  ON public.merchant_claim_requests FOR SELECT TO authenticated
  USING (
    submitted_by = auth.uid()
    OR public.get_user_role(auth.uid()) IN ('moderator', 'super_admin')
  );

-- 仅管理员可更新（审核在 T038 admin 接口中进行）
CREATE POLICY "claim_requests_update_admin_only"
  ON public.merchant_claim_requests FOR UPDATE TO authenticated
  USING (public.get_user_role(auth.uid()) IN ('moderator', 'super_admin'));