CREATE OR REPLACE FUNCTION increment_merchant_view_count(p_merchant_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE merchants SET view_count = view_count + 1
  WHERE id = p_merchant_id AND is_deleted = false;
END;
$$;

GRANT EXECUTE ON FUNCTION increment_merchant_view_count(UUID) TO anon, authenticated;