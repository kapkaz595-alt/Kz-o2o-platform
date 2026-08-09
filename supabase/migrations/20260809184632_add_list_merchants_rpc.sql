CREATE OR REPLACE FUNCTION list_merchants(
  p_category TEXT DEFAULT NULL,
  p_target_audience TEXT DEFAULT NULL,
  p_keyword TEXT DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL,
  p_radius_meters INT DEFAULT 5000,
  p_page INT DEFAULT 1,
  p_page_size INT DEFAULT 20
)
RETURNS TABLE (
  id UUID, slug TEXT, name JSONB, category TEXT,
  target_audiences TEXT[], address JSONB,
  whatsapp_number TEXT, rating_avg NUMERIC,
  review_count INT, vip_tier TEXT, featured BOOLEAN,
  distance_meters DOUBLE PRECISION, total_count BIGINT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_offset INT := (p_page - 1) * p_page_size;
  v_point GEOGRAPHY;
BEGIN
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    v_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::GEOGRAPHY;
  END IF;

  RETURN QUERY
  SELECT
    m.id, m.slug, m.name, m.category, m.target_audiences, m.address,
    m.whatsapp_number, m.rating_avg, m.review_count, m.vip_tier, m.featured,
    CASE WHEN v_point IS NOT NULL THEN ST_Distance(m.location, v_point) ELSE NULL END,
    COUNT(*) OVER() AS total_count
  FROM merchants m
  WHERE m.is_deleted = false
    AND m.status = 'active'
    AND (p_category IS NULL OR m.category = p_category)
    AND (p_target_audience IS NULL OR p_target_audience = ANY(m.target_audiences))
    AND (p_keyword IS NULL OR m.search_vector @@ plainto_tsquery('simple', p_keyword))
    AND (v_point IS NULL OR ST_DWithin(m.location, v_point, p_radius_meters))
  ORDER BY
    m.featured DESC,
    CASE m.vip_tier WHEN 'premium' THEN 1 WHEN 'basic' THEN 2 ELSE 3 END,
    CASE WHEN v_point IS NOT NULL THEN ST_Distance(m.location, v_point) END ASC NULLS LAST,
    m.rating_avg DESC NULLS LAST
  LIMIT p_page_size OFFSET v_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION list_merchants TO anon, authenticated;