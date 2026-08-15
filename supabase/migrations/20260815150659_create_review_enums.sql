create type review_status as enum ('pending', 'approved', 'rejected', 'flagged');
create type report_status as enum ('pending', 'resolved', 'dismissed');
create type report_reason as enum ('spam', 'offensive', 'fake', 'irrelevant', 'other');
create type reaction_type as enum ('helpful', 'unhelpful');