import { NextRequest, NextResponse } from 'next/server';
import { createClient, type SupabaseClient, type User } from '@supabase/supabase-js';

export async function requireAuth(
  req: NextRequest
): Promise<{ user: User; supabase: SupabaseClient } | { error: NextResponse }> {
  const authHeader = req.headers.get('authorization');
  const token = authHeader?.replace('Bearer ', '');

  if (!token) {
    return {
      error: NextResponse.json(
        { error: 'UNAUTHORIZED', message: '未登录或登录已过期' },
        { status: 401 }
      ),
    };
  }

  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    anonKey,
    {
      global: {
        headers: {
          apikey: anonKey,
          Authorization: `Bearer ${token}`,
        },
      },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    }
  );

  const { data: { user }, error } = await supabase.auth.getUser(token);

  if (error || !user) {
    return {
      error: NextResponse.json(
        { error: 'UNAUTHORIZED', message: '未登录或登录已过期' },
        { status: 401 }
      ),
    };
  }

  return { user, supabase };
}