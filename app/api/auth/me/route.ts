import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireAuth } from '@/lib/supabase/auth-middleware';

export async function GET(req: NextRequest) {
  const authResult = await requireAuth(req);

  if ('error' in authResult) {
    return authResult.error;
  }

  const { user } = authResult;

  const adminClient = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );

  const { data: profile, error: profileError } = await adminClient
    .from('users')
    .select('*')
    .eq('id', user.id)
    .single();

  if (profileError) {
    console.error('fetch profile error:', profileError);
    return NextResponse.json(
      { error: 'PROFILE_NOT_FOUND', message: '用户资料不存在' },
      { status: 404 }
    );
  }

  return NextResponse.json({
    user: { id: user.id, email: user.email },
    profile,
  });
}