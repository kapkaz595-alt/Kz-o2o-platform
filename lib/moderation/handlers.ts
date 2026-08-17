import { SupabaseClient } from '@supabase/supabase-js';

type ContentAction = 'approve' | 'reject';
type ReportAction = 'resolve' | 'dismiss';

interface HandlerContext {
  supabase: SupabaseClient;
  targetId: string;
  reviewerId: string;
  reviewNote?: string;
}

// target_type -> 合法action集合
export const VALID_ACTIONS: Record<string, string[]> = {
  merchant_image: ['approve', 'reject'],
  review: ['approve', 'reject'],
  review_media: ['approve', 'reject'],
  review_report: ['resolve', 'dismiss'],
  merchant_report: ['resolve', 'dismiss'],
};

async function handleContentModeration(
  table: string,
  action: ContentAction,
  ctx: HandlerContext
) {
  const newStatus = action === 'approve' ? 'approved' : 'rejected';
  const { error } = await ctx.supabase
    .from(table)
    .update({
      status: newStatus,
      reviewer_id: ctx.reviewerId,
      review_note: ctx.reviewNote ?? null,
      reviewed_at: new Date().toISOString(),
    })
    .eq('id', ctx.targetId);
  if (error) throw error;
}

async function handleReportResolution(
  table: string,
  action: ReportAction,
  ctx: HandlerContext
) {
  const newStatus = action === 'resolve' ? 'resolved' : 'dismissed';
  const { error } = await ctx.supabase
    .from(table)
    .update({
      status: newStatus,
      resolved_by: ctx.reviewerId,
      resolved_at: new Date().toISOString(),
    })
    .eq('id', ctx.targetId);
  if (error) throw error;
}

export const moderationHandlers: Record<
  string,
  (action: string, ctx: HandlerContext) => Promise<void>
> = {
  merchant_image: (action, ctx) => handleContentModeration('merchant_images', action as ContentAction, ctx),
  review: (action, ctx) => handleContentModeration('reviews', action as ContentAction, ctx),
  review_media: (action, ctx) => handleContentModeration('review_media', action as ContentAction, ctx),
  review_report: (action, ctx) => handleReportResolution('review_reports', action as ReportAction, ctx),
  merchant_report: (action, ctx) => handleReportResolution('merchant_reports', action as ReportAction, ctx),
};