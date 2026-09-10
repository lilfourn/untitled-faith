ALTER TABLE users ADD COLUMN first_name TEXT CHECK (first_name IS NULL OR length(first_name) BETWEEN 1 AND 100);
