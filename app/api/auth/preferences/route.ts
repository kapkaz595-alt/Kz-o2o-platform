import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth } from '@/lib/supabase/auth-middleware';
import { z } from 'zod';

const preferencesSchema = z.object({
  target_audience: z.enum(['chinese', 'local']).optional(),
  preferred_language: z.enum(['zh', 'ru', 'kk']).optional(),
});

export const GET = withAuth(async (req, { user }) => {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from('users')
    .select('target_audience, preferred_language')
    .eq('id', user.id)
    .single();

  if (error) {
    return NextResponse.json(
      { error: 'PREFERENCES_NOT_FOUND', message: '偏好设置不存在' },
      { status: 404 },
    );
  }

  return NextResponse.json({ preferences: data });
});

export const PATCH = withAuth(async (req, { user }) => {
  try {
    const body = await req.json();
    const parsed = preferencesSchema.safeParse(body);

    if (!parsed.success) {
      return NextResponse.json(
        { error: 'INVALID_INPUT', message: '偏好参数不正确', details: parsed.error.flatten() },
        { status: 400 },
      );
    }

    if (Object.keys(parsed.data).length === 0) {
      return NextResponse.json(
        { error: 'NO_FIELDS', message: '未提供任何偏好字段' },
        { status: 400 },
      );
    }

    const supabase = await createClient();

    const { data, error } = await supabase
      .from('users')
      .update(parsed.data)
      .eq('id', user.id)
      .select('target_audience, preferred_language')
      .single();

    if (error) {
      return NextResponse.json(
        { error: 'UPDATE_FAILED', message: '偏好更新失败' },
        { status: 500 },
      );
    }

    return NextResponse.json({ preferences: data });
  } catch (err) {
    console.error('update preferences error:', err);
    return NextResponse.json(
      { error: 'INTERNAL_ERROR', message: '服务器内部错误' },
      { status: 500 },
    );
  }
});