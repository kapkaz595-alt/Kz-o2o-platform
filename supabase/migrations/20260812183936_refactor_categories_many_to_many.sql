-- ============================================================
-- Migration: categories多对多重构
-- ============================================================

-- 1. 分类主表（支持多级树状结构）
CREATE TABLE public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name JSONB NOT NULL DEFAULT '{}'::jsonb,  -- {"zh":"中餐厅","ru":"...","kk":"..."}
    slug TEXT NOT NULL UNIQUE,
    parent_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    icon TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_categories_parent_id ON public.categories (parent_id) WHERE is_deleted = false;
CREATE INDEX idx_categories_slug ON public.categories (slug) WHERE is_deleted = false;

CREATE TRIGGER trg_categories_updated_at
    BEFORE UPDATE ON public.categories
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 2. 商家-分类关联表（多对多）
CREATE TABLE public.merchant_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    is_primary BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_merchant_category UNIQUE (merchant_id, category_id)
);

CREATE INDEX idx_merchant_categories_merchant_id ON public.merchant_categories (merchant_id);
CREATE INDEX idx_merchant_categories_category_id ON public.merchant_categories (category_id);

-- 保证每个商家最多一个is_primary=true（部分唯一索引）
CREATE UNIQUE INDEX uq_merchant_categories_one_primary
    ON public.merchant_categories (merchant_id)
    WHERE is_primary = true;

-- 3. 分类树闭包表（快速查询祖先/后代，避免递归CTE）
CREATE TABLE public.category_closure (
    ancestor_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    descendant_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    depth INTEGER NOT NULL,
    PRIMARY KEY (ancestor_id, descendant_id)
);

CREATE INDEX idx_category_closure_descendant ON public.category_closure (descendant_id);

-- 4. 数据迁移：把merchants.category旧文本值搬到新表
-- 4a. 从现有category文本值去重生成categories记录（slug用简单转换，中文/俄文/哈文都存进name.zh兜底）
INSERT INTO public.categories (name, slug)
SELECT DISTINCT
    jsonb_build_object('zh', category, 'ru', category, 'kk', category),
    lower(regexp_replace(category, '[^a-zA-Z0-9\u4e00-\u9fa5]+', '-', 'g'))
FROM public.merchants
WHERE category IS NOT NULL AND category != ''
ON CONFLICT (slug) DO NOTHING;

-- 4b. 每个分类自己是自己的闭包（depth=0）
INSERT INTO public.category_closure (ancestor_id, descendant_id, depth)
SELECT id, id, 0 FROM public.categories
ON CONFLICT DO NOTHING;

-- 4c. 把每个商家原有category值关联到新表，标记为主分类
INSERT INTO public.merchant_categories (merchant_id, category_id, is_primary)
SELECT m.id, c.id, true
FROM public.merchants m
JOIN public.categories c
  ON c.slug = lower(regexp_replace(m.category, '[^a-zA-Z0-9\u4e00-\u9fa5]+', '-', 'g'))
WHERE m.category IS NOT NULL AND m.category != ''
ON CONFLICT (merchant_id, category_id) DO NOTHING;

-- 5. RLS
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_closure ENABLE ROW LEVEL SECURITY;

-- 分类表：所有人可读激活的分类，只有管理员能改
CREATE POLICY categories_select_public
    ON public.categories FOR SELECT
    USING (is_active = true AND is_deleted = false);

CREATE POLICY categories_admin_all
    ON public.categories FOR ALL
    USING (public.get_user_role(auth.uid()) IN ('moderator', 'super_admin'));

-- 商家分类关联表：公开可读；写入走商家更新审核流程或管理员
CREATE POLICY merchant_categories_select_public
    ON public.merchant_categories FOR SELECT
    USING (true);

CREATE POLICY merchant_categories_admin_write
    ON public.merchant_categories FOR ALL
    USING (public.get_user_role(auth.uid()) IN ('moderator', 'super_admin'));

-- 闭包表：公开可读，管理员写（一般由触发器/服务端脚本维护，不开放前端直接写）
CREATE POLICY category_closure_select_public
    ON public.category_closure FOR SELECT
    USING (true);

CREATE POLICY category_closure_admin_write
    ON public.category_closure FOR ALL
    USING (public.get_user_role(auth.uid()) IN ('super_admin'));

-- 6. 暂时保留merchants.category旧字段不删（先双写过渡，等T032接口切换验证完再单独migration删除）
COMMENT ON COLUMN public.merchants.category IS 'DEPRECATED: 待T032接口切换到merchant_categories后删除此字段';