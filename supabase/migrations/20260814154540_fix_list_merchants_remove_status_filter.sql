CREATE OR REPLACE FUNCTION public.list_merchants(
  p_category text DEFAULT NULL::text,
  p_target_audience text DEFAULT NULL::text,
  p_keyword text DEFAULT NULL::text,
  p_lat double precision DEFAULT NULL::double precision,
  p_lng double precision DEFAULT NULL::double precision,
  p_radius_meters integer DEFAULT 5000,
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 20
)
 RETURNS TABLE(id uuid, slug text, name jsonb, category text, target_audiences text[], address jsonb, whatsapp_number text, rating_avg numeric, review_count integer, vip_tier text, featured boolean, distance_meters double precision, total_count bigint)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$;