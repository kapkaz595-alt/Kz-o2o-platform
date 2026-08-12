import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth, requireRole } from '@/lib/supabase/auth-middleware';

export const GET = withAuth(async (req: NextRequest, { user }) => {
  const roleCheck = await requireRole(user, ['moderator', 'super_admin']);
  if (!roleCheck.ok) return roleCheck.response;

  const supabase = await createClient();
  const { searchParams } = new URL(req.url);
  const status = (searchParams.get('status') || 'pending') as
    | 'pending'
    | 'approved'
    | 'rejected';
  const page = parseInt(searchParams.get('page') || '1', 10);
  const pageSize = parseInt(searchParams.get('page_size') || '20', 10);
  const offset = (page - 1) * pageSize;

  const { data, error, count } = await supabase
    .from('merchant_claim_requests')
    .select(
      `
      id,
      merchant_id,
      submitted_by,
      bin_iin,
      business_license_number,
      contact_name,
      contact_phone,
      proof_files,
      status,
      reviewer_id,
      review_note,
      reviewed_at,
      created_at,
      merchants:merchant_id (
        id,
        slug,
        name,
        claim_status
      )
      `,
      { count: 'exact' }
    )
    .eq('status', status)
    .eq('is_deleted', false)
    .order('created_at', { ascending: true })
    .range(offset, offset + pageSize - 1);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const enriched = await Promise.all(
    (data || []).map(async (item) => {
      const proofFiles = (item.proof_files as string[]) || [];
      const signedUrls = await Promise.all(
        proofFiles.map(async (path) => {
          const { data: signed } = await supabase.storage
            .from('claim-proofs')
            .createSignedUrl(path, 600);
          return signed?.signedUrl || null;
        })
      );
      return { ...item, proof_files_signed: signedUrls };
    })
  );

  return NextResponse.json({
    data: enriched,
    pagination: {
      page,
      page_size: pageSize,
      total: count || 0,
      total_pages: Math.ceil((count || 0) / pageSize),
    },
  });
});