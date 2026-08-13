// app/api/merchants/[slug]/claim/route.ts

import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth } from '@/lib/supabase/auth-middleware';

const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB
const ALLOWED_MIME = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
const MAX_FILES = 5;

export const POST = withAuth(async (req: NextRequest, { params, user }) => {
  const { slug } = params as { slug: string };
  const supabase = await createClient();

  // 1. 查商家，校验可认领状态
  const { data: merchant, error: merchantErr } = await supabase
    .from('merchants')
    .select('id, claim_status')
    .eq('slug', slug)
    .eq('is_deleted', false)
    .single();

  if (merchantErr || !merchant) {
    return NextResponse.json({ error: 'Merchant not found' }, { status: 404 });
  }

  if (!['unclaimed', 'claim_rejected'].includes(merchant.claim_status)) {
    return NextResponse.json(
      { error: `Merchant cannot be claimed (current status: ${merchant.claim_status})` },
      { status: 409 }
    );
  }

  // 2. 解析 multipart/form-data
  const formData = await req.formData();
  const binIin = formData.get('bin_iin')?.toString().trim();
  const contactName = formData.get('contact_name')?.toString().trim();
  const contactPhone = formData.get('contact_phone')?.toString().trim();
  const businessLicenseNumber = formData.get('business_license_number')?.toString().trim() || null;
  const files = formData.getAll('files') as File[];

  const whatsappNumber = formData.get('whatsapp_number')?.toString().trim();

const E164_REGEX = /^\+[1-9]\d{1,14}$/;
if (!whatsappNumber || !E164_REGEX.test(whatsappNumber)) {
  return NextResponse.json(
    { error: 'WhatsApp号码格式不正确，需为E.164格式，例如 +77011234567' },
    { status: 400 }
  );
}

  if (!binIin || !contactName || !contactPhone) {
    return NextResponse.json(
      { error: 'bin_iin, contact_name, contact_phone are required' },
      { status: 400 }
    );
  }

  if (files.length === 0) {
    return NextResponse.json({ error: 'At least one proof file is required' }, { status: 400 });
  }
  if (files.length > MAX_FILES) {
    return NextResponse.json({ error: `Max ${MAX_FILES} files allowed` }, { status: 400 });
  }

  for (const file of files) {
    if (!ALLOWED_MIME.includes(file.type)) {
      return NextResponse.json(
        { error: `Unsupported file type: ${file.type}` },
        { status: 400 }
      );
    }
    if (file.size > MAX_FILE_SIZE) {
      return NextResponse.json(
        { error: `File ${file.name} exceeds 5MB limit` },
        { status: 400 }
      );
    }
  }

  // 3. 上传文件到 claim-proofs 私有桶
  const uploadedPaths: string[] = [];
  for (const file of files) {
    const timestamp = Date.now();
    const safeName = file.name.replace(/[^a-zA-Z0-9.\-_]/g, '_');
    const path = `${merchant.id}/${user.id}/${timestamp}_${safeName}`;

    const { error: uploadErr } = await supabase.storage
      .from('claim-proofs')
      .upload(path, file, { contentType: file.type, upsert: false });

    if (uploadErr) {
      // 已上传的先清理，避免留下孤立文件
      if (uploadedPaths.length > 0) {
        await supabase.storage.from('claim-proofs').remove(uploadedPaths);
      }
      return NextResponse.json(
        { error: `File upload failed: ${uploadErr.message}` },
        { status: 500 }
      );
    }
    uploadedPaths.push(path);
  }

  // 4. 插入申请记录（唯一索引会拦截重复 pending 申请）
  const { data: claimRequest, error: insertErr } = await supabase
    .from('merchant_claim_requests')
    .insert({
      merchant_id: merchant.id,
      submitted_by: user.id,
      bin_iin: binIin,
      business_license_number: businessLicenseNumber,
      contact_name: contactName,
      contact_phone: contactPhone,
      proof_files: uploadedPaths,
    })
    .select()
    .single();

  if (insertErr) {
    await supabase.storage.from('claim-proofs').remove(uploadedPaths);
    if (insertErr.code === '23505') {
      return NextResponse.json(
        { error: 'A pending claim request already exists for this merchant' },
        { status: 409 }
      );
    }
    return NextResponse.json({ error: insertErr.message }, { status: 500 });
  }

  return NextResponse.json({ data: claimRequest }, { status: 201 });
});