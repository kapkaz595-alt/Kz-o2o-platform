-- 2. 商家成员角色枚举
CREATE TYPE merchant_member_role AS ENUM ('owner', 'editor', 'viewer');

-- 3. merchant_member_roles 表
CREATE TABLE public.merchant_member_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role merchant_member_role NOT NULL DEFAULT 'viewer',
    invited_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    deleted_at TIMESTAMPTZ,
    CONSTRAINT uq_merchant_member UNIQUE (merchant_id, user_id)
);

-- 4. 索引
CREATE INDEX idx_merchant_member_roles_merchant_id
    ON public.merchant_member_roles (merchant_id)
    WHERE is_deleted = false;

CREATE INDEX idx_merchant_member_roles_user_id
    ON public.merchant_member_roles (user_id)
    WHERE is_deleted = false;

-- 5. updated_at 自动维护触发器（复用项目里已有的 set_updated_at 函数，若不存在则新建）
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_merchant_member_roles_updated_at
    BEFORE UPDATE ON public.merchant_member_roles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- 6. RLS
ALTER TABLE public.merchant_member_roles ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER 函数：判断当前用户是否是某商家的 owner（避免RLS递归）
CREATE OR REPLACE FUNCTION public.is_merchant_owner(p_merchant_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.merchant_member_roles
        WHERE merchant_id = p_merchant_id
          AND user_id = p_user_id
          AND role = 'owner'
          AND is_deleted = false
    );
$$;

-- 团队成员可读自己所在商家的团队列表；平台管理员/support全读
CREATE POLICY merchant_member_roles_select
    ON public.merchant_member_roles
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_merchant_owner(merchant_id, auth.uid())
        OR public.get_user_role(auth.uid()) IN ('moderator', 'super_admin', 'support')
    );

-- 只有owner或平台管理员能新增成员
CREATE POLICY merchant_member_roles_insert
    ON public.merchant_member_roles
    FOR INSERT
    WITH CHECK (
        public.is_merchant_owner(merchant_id, auth.uid())
        OR public.get_user_role(auth.uid()) IN ('moderator', 'super_admin')
    );

-- 只有owner或平台管理员能修改成员角色
CREATE POLICY merchant_member_roles_update
    ON public.merchant_member_roles
    FOR UPDATE
    USING (
        public.is_merchant_owner(merchant_id, auth.uid())
        OR public.get_user_role(auth.uid()) IN ('moderator', 'super_admin')
    );

-- 只有owner或平台管理员能移除成员（软删除走UPDATE，这里预留物理DELETE给管理员紧急处理用）
CREATE POLICY merchant_member_roles_delete
    ON public.merchant_member_roles
    FOR DELETE
    USING (
        public.get_user_role(auth.uid()) IN ('super_admin')
    );