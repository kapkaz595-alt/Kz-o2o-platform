import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth } from '@/lib/supabase/auth-middleware';

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_SIZE = 5 * 1024 * 1024; // 5MB

export const POST = withAuth(async (req: NextRequest, { user }, { params }: { params: { slug: string } }) => {
  const supabase = createClient();

  const { data: merchant, error: findError } = await supabase
    .from('merchants')
    .select('id, owner_id, images')
    .eq('slug', params.slug)
    .eq('is_deleted', false)
    .maybeSingle();

  if (findError || !merchant) {
    return NextResponse.json({ error: 'merchant not found' }, { status: 404 });
  }

  const isAdmin = user.role === 'moderator' || user.role === 'super_admin';
  const isOwner = merchant.owner_id === user.id;

  if (!isAdmin && !isOwner) {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const formData = await req.formData();
  const file = formData.get('file') as File | null;

  if (!file) {
    return NextResponse.json({ error: 'file is required' }, { status: 400 });
  }

  if (!ALLOWED_TYPES.includes(file.type)) {
    return NextResponse.json({ error: '仅支持JPEG/PNG/WEBP格式' }, { status: 400 });
  }

  if (file.size > MAX_SIZE) {
    return NextResponse.json({ error: '文件大小不能超过5MB' }, { status: 400 });
  }

  const ext = file.name.split('.').pop();
  const filePath = `${merchant.id}/${Date.now()}-${crypto.randomUUID()}.${ext}`;

  const { error: uploadError } = await supabase.storage
    .from('merchant-images')
    .upload(filePath, file, { contentType: file.type, upsert: false });

  if (uploadError) {
    console.error('[merchants/images] upload error:', uploadError);
    return NextResponse.json({ error: 'upload failed' }, { status: 500 });
  }

  const { data: publicUrlData } = supabase.storage
    .from('merchant-images')
    .getPublicUrl(filePath);

  const { data: imageRecord, error: insertError } = await supabase
    .from('merchant_images')
    .insert({
      merchant_id: merchant.id,
      storage_path: filePath,
      url: publicUrlData.publicUrl,
      uploaded_by: user.id,
      status: 'pending',
    })
    .select()
    .single();

  if (insertError) {
    console.error('[merchants/images] insert error:', insertError);
    return NextResponse.json({ error: 'insert failed' }, { status: 500 });
  }

  await supabase.from('moderation_queue').insert({
    target_type: 'merchant_image',
    target_id: imageRecord.id,
    source: isOwner ? 'merchant_owner' : 'admin_upload',
    status: 'pending',
  });

  return NextResponse.json({ message: '图片已上传，等待审核', data: imageRecord }, { status: 201 });
});