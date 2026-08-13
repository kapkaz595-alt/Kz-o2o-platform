import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth, requireRole } from '@/lib/supabase/auth-middleware';

export const PATCH = withAuth(async (req: NextRequest, { user, params }) => {
  const roleCheck = await requireRole(user, ['moderator', 'super_admin']);
  if (!roleCheck.ok) return roleCheck.response;

  const supabase = await createClient();
  const { id } = params as { id: string };
  const body = await req.json();
  const { action, review_note, verify_whatsapp } = body;

  if (!['approve', 'reject'].includes(action)) {
    return NextResponse.json(
      { error: 'action must be approve or reject' },
      { status: 400 }
    );
  }

  if (action === 'reject' && !review_note) {
    return NextResponse.json(
      { error: 'review_note is required when rejecting' },
      { status: 400 }
    );
  }

  const rpcArgs =
  action === 'approve'
    ? {
        p_request_id: id,
        p_reviewer_id: user.id,
        p_review_note: review_note || null,
        p_verify_whatsapp: verify_whatsapp === true,
      }
    : {
        p_request_id: id,
        p_reviewer_id: user.id,
        p_review_note: review_note || null,
      };

const rpcFn = action === 'approve' ? 'approve_claim_request' : 'reject_claim_request';
  const { data, error } = await (supabase.rpc as any)(rpcFn, rpcArgs);

  if (error) {
    const status = error.message.includes('not_found_or_already_reviewed') ? 409 : 500;
    return NextResponse.json({ error: error.message }, { status });
  }

  return NextResponse.json({ data });
});