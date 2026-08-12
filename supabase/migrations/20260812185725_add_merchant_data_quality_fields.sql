ALTER TABLE public.merchants
    ADD COLUMN source_type TEXT DEFAULT 'platform_entry',
    ADD COLUMN source_url TEXT,
    ADD COLUMN last_verified_at TIMESTAMPTZ,
    ADD COLUMN verification_level TEXT DEFAULT 'unverified',
    ADD COLUMN data_confidence_score NUMERIC(3,2) DEFAULT 0.50;

COMMENT ON COLUMN public.merchants.source_type IS '数据来源：platform_entry(平台录入)/merchant_claimed(商家认领)/import(批量导入)等';
COMMENT ON COLUMN public.merchants.source_url IS '数据来源链接（如从Google Maps/2GIS抓取的原始页面）';
COMMENT ON COLUMN public.merchants.last_verified_at IS '最后一次人工核实数据准确性的时间';
COMMENT ON COLUMN public.merchants.verification_level IS '核实等级：unverified/basic_verified/fully_verified';
COMMENT ON COLUMN public.merchants.data_confidence_score IS '数据可信度评分0-1，越高越可信';