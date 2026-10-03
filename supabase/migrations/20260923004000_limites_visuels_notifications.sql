-- Les limites doivent être imposées par Storage, pas seulement par le formulaire web.
UPDATE storage.buckets
SET file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'notifications';
