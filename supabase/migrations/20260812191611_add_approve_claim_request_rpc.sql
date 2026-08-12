CREATE OR REPLACE FUNCTION public.approve_claim_request(
    p_claim_request_id UUID,
    p_reviewer_id UUID,
    p_review_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_claim RECORD;
BEGIN
    -- 锁定并读取认领申请，防止并发重复审核
    SELECT * INTO v_claim
    FROM public.merchant_claim_requests
    WHERE id = p_claim_request_id AND status = 'pending'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'claim_request_not_found_or_already_reviewed';
    END IF;

    -- 1. 更新认领申请状态
    UPDATE public.merchant_claim_requests
    SET status = 'approved',
        reviewer_id = p_reviewer_id,
        review_note = p_review_note,
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_claim_request_id;

    -- 2. 更新商家表：claim_status + owner_id冗余字段
    UPDATE public.merchants
    SET claim_status = 'claimed',
        owner_id = v_claim.submitted_by,
        updated_at = now()
    WHERE id = v_claim.merchant_id;

    -- 3. 写入merchant_member_roles，绑定owner角色
    INSERT INTO public.merchant_member_roles (merchant_id, user_id, role, invited_by)
    VALUES (v_claim.merchant_id, v_claim.submitted_by, 'owner', p_reviewer_id)
    ON CONFLICT (merchant_id, user_id)
    DO UPDATE SET role = 'owner', is_deleted = false, deleted_at = NULL, updated_at = now();

    RETURN jsonb_build_object(
        'claim_request_id', p_claim_request_id,
        'merchant_id', v_claim.merchant_id,
        'owner_id', v_claim.submitted_by,
        'status', 'approved'
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_claim_request(
    p_claim_request_id UUID,
    p_reviewer_id UUID,
    p_review_note TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_claim RECORD;
BEGIN
    SELECT * INTO v_claim
    FROM public.merchant_claim_requests
    WHERE id = p_claim_request_id AND status = 'pending'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'claim_request_not_found_or_already_reviewed';
    END IF;

    UPDATE public.merchant_claim_requests
    SET status = 'rejected',
        reviewer_id = p_reviewer_id,
        review_note = p_review_note,
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_claim_request_id;

    -- 商家claim_status退回unclaimed，允许重新提交
    UPDATE public.merchants
    SET claim_status = 'claim_rejected',
        updated_at = now()
    WHERE id = v_claim.merchant_id;

    RETURN jsonb_build_object(
        'claim_request_id', p_claim_request_id,
        'merchant_id', v_claim.merchant_id,
        'status', 'rejected',
        'review_note', p_review_note
    );
END;
$$;