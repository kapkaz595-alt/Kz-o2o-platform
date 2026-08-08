import { NextRequest, NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/supabase/session';
import type { User } from '@supabase/supabase-js';

type AuthedHandler = (
  req: NextRequest,
  ctx: { user: User; params?: any },
) => Promise<NextResponse>;

export function withAuth(handler: AuthedHandler) {
  return async (req: NextRequest, routeCtx?: { params?: any }) => {
    const user = await getCurrentUser();

    if (!user) {
      return NextResponse.json(
        { error: 'UNAUTHORIZED', message: '请先登录' },
        { status: 401 },
      );
    }

    return handler(req, { user, params: routeCtx?.params });
  };
}

export async function requireRole(
  user: User,
  allowedRoles: string[],
): Promise<{ ok: true } | { ok: false; response: NextResponse }> {
  const role = user.app_metadata?.role ?? 'user';

  if (!allowedRoles.includes(role)) {
    return {
      ok: false,
      response: NextResponse.json(
        { error: 'FORBIDDEN', message: '权限不足' },
        { status: 403 },
      ),
    };
  }

  return { ok: true };
}