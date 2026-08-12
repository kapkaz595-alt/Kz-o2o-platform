-- ============================================================
-- Migration: add support/finance platform roles + merchant_member_roles
-- ============================================================

-- 1. 扩展平台角色枚举，新增 support / finance
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'support';
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'finance';

