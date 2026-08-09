import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth } from '@/lib/supabase/auth-middleware';
import { z } from 'zod';

const multilingualText = z.object({
  zh: z.string().min(1),
  ru: z.string().optional(),
  kk: z.string().optional(),
});

const createMerchantSchema = z.object({
  name: multilingualText,
  description: multilingualText.partial({ zh: true }).optional(),
  category: z.string().min(1),
  target_audiences: z.array(z.enum(['chinese', 'local'])).min(1),
  location: z.object({
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180),
  }),
  address: multilingualText.partial({ zh: true }).optional(),
  phone: z.string().optional(),
  whatsapp_number: z.string().optional(),
  business_hours: z.record(z.any()).optional(),
  cover_image_url: z.string().url().optional(),
  slug: z.string().min(1).max(100).regex(/^[a-z0-9-]+$/).optional(),
});

function slugify(text: string): string {
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, '')
    .replace(/[\s_]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

export const POST = withAuth(async (req, { user }) => {
  try {
    const supabase = await createClient();

    const { data: role, error: roleError } = await supabase.rpc('get_user_role', {
      user_id: user.id,
    });

    if (roleError || !role || !['moderator', 'super_admin'].includes(role)) {
      return NextResponse.json(
        { error: 'FORBIDDEN', message: '权限不足，仅管理员可创建商家' },
        { status: 403 },
      );
    }

    const body = await req.json();
    const parsed = createMerchantSchema.safeParse(body);

    if (!parsed.success) {
      return NextResponse.json(
        { error: 'INVALID_INPUT', message: '输入格式不正确', details: parsed.error.flatten() },
        { status: 400 },
      );
    }

    const { location, slug: providedSlug, ...rest } = parsed.data;

    let slug = providedSlug ?? slugify(rest.name.zh);
if (!slug) {
  slug = `${rest.category}-${Date.now().toString(36)}`;
}

    const { data: existing } = await supabase
      .from('merchants')
      .select('id')
      .eq('slug', slug)
      .maybeSingle();

    if (existing) {
      slug = `${slug}-${Date.now().toString(36)}`;
    }

    const { data: merchant, error } = await supabase
      .from('merchants')
      .insert({
        ...rest,
        slug,
        location: `SRID=4326;POINT(${location.lng} ${location.lat})`,
        claim_status: 'unclaimed',
        vip_tier: 'free',
        featured: false,
        priority: 0,
      })
      .select()
      .single();

    if (error) {
      console.error('create merchant error:', error);
      return NextResponse.json(
        { error: 'CREATE_FAILED', message: '创建商家失败' },
        { status: 500 },
      );
    }

    return NextResponse.json({ merchant }, { status: 201 });
  } catch (err) {
    console.error('POST /merchants error:', err);
    return NextResponse.json(
      { error: 'INTERNAL_ERROR', message: '服务器内部错误' },
      { status: 500 },
    );
  }
});

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const supabase = createClient();

  const page = parseInt(searchParams.get('page') ?? '1', 10);
  const pageSize = Math.min(parseInt(searchParams.get('page_size') ?? '20', 10), 50);

  const { data, error } = await supabase.rpc('list_merchants', {
    p_category: searchParams.get('category'),
    p_target_audience: searchParams.get('target_audience'),
    p_keyword: searchParams.get('keyword'),
    p_lat: searchParams.get('lat') ? parseFloat(searchParams.get('lat')!) : null,
    p_lng: searchParams.get('lng') ? parseFloat(searchParams.get('lng')!) : null,
    p_radius_meters: searchParams.get('radius') ? parseInt(searchParams.get('radius')!, 10) : 5000,
    p_page: page,
    p_page_size: pageSize,
  });

  if (error) {
    console.error('[merchants/list] query error:', error);
    return NextResponse.json({ error: 'internal server error' }, { status: 500 });
  }

  const total = data?.[0]?.total_count ?? 0;
  const merchants = (data ?? []).map(({ total_count, ...rest }: any) => rest);

  return NextResponse.json({
    data: merchants,
    pagination: { page, page_size: pageSize, total: Number(total), total_pages: Math.ceil(Number(total) / pageSize) },
  });
}