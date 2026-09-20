-- Run once in the SQL Editor, before importing the new Seoul-specific
-- 경로당 dataset, to remove the previously imported rows (from
-- 전국마을회관및경로당표준데이터.xlsx).
--
-- NOTE: this will fail with a foreign key error if any meetup post
-- (posts.facility_id) already references one of these rows — if so,
-- reassign or delete that meetup first, then re-run this.
delete from public.facilities where category = '경로당';
