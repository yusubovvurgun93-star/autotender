/*
# Storage policies for part-images bucket

1. Security
- Public read access for part-images bucket (anyone can view uploaded part photos)
- Anon upload access for image files (jpeg, png, webp, gif)
*/

DROP POLICY IF EXISTS "anon_read_part_images" ON storage.objects;
CREATE POLICY "anon_read_part_images"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (bucket_id = 'part-images');

DROP POLICY IF EXISTS "anon_upload_part_images" ON storage.objects;
CREATE POLICY "anon_upload_part_images"
ON storage.objects FOR INSERT
TO anon, authenticated
WITH CHECK (bucket_id = 'part-images');
